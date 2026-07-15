"""Text Anaconda spoke for selecting ZZ Fedora."""

from simpleline.render.containers import ListColumnContainer
from simpleline.render.prompt import Prompt
from simpleline.render.screen import InputState
from simpleline.render.widgets import CheckboxWidget, TextWidget

from pyanaconda.core.constants import THREAD_PAYLOAD
from pyanaconda.core.threads import thread_manager
from pyanaconda.ui.categories.software import SoftwareCategory
from pyanaconda.ui.tui.spokes import NormalTUISpoke

from org_zz_fedora.constants import DEFAULT_DESKTOP_APP_PROFILE
from org_zz_fedora.runtime import (
    THREAD_RUNTIME_REFRESH,
    payload_proxy_url,
    refresh_runtime,
)
from org_zz_fedora.selection import (
    default_selections,
    read_categories,
    read_state,
    selected_choice_count,
    write_state,
)

__all__ = ["ZZFedoraSpoke"]

_ = lambda x: x
N_ = lambda x: x


class ZZFedoraSpoke(NormalTUISpoke):
    """Optional TUI spoke that controls repository post-install setup."""

    category = SoftwareCategory

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.title = N_("ZZ Fedora")
        self._categories = []
        self._container = None
        self._desktop_app_profile = DEFAULT_DESKTOP_APP_PROFILE
        self._selections = {}
        self._preferred_browser = ""
        self._runtime_ready = False
        self._runtime_error = ""

    @classmethod
    def should_run(cls, environment, data):
        return True

    def initialize(self):
        super().initialize()
        self.initialize_start()
        thread_manager.add_thread(
            name=THREAD_RUNTIME_REFRESH,
            target=self._initialize_runtime,
        )

    def _initialize_runtime(self):
        try:
            try:
                thread_manager.wait(THREAD_PAYLOAD)
            except Exception as error:  # pylint: disable=broad-except
                self._runtime_ready = False
                self._runtime_error = str(error)
            else:
                self._load_latest_choices()
        finally:
            self.initialize_done()

    def _load_latest_choices(self, force=False):
        try:
            refresh_runtime(payload_proxy_url(self.payload), force=force)
            categories = read_categories()
            if not categories:
                raise RuntimeError("The refreshed runtime has no optional choices")
        except Exception as error:  # pylint: disable=broad-except
            self._runtime_ready = False
            self._runtime_error = str(error)
            return False

        self._categories = categories
        (
            enabled,
            self._desktop_app_profile,
            self._selections,
            self._preferred_browser,
        ) = read_state(self._categories)
        self._runtime_ready = True
        if not enabled:
            self._selections = default_selections(
                self._categories,
                self._desktop_app_profile,
            )
            self._preferred_browser = ""
            self.apply()
        self._runtime_error = ""
        return True

    def setup(self, args=None):
        super().setup(args)
        if not self._runtime_ready and not thread_manager.get(THREAD_RUNTIME_REFRESH):
            self._start_runtime_retry()
        return True

    def _start_runtime_retry(self):
        self._runtime_error = ""
        thread_manager.add_thread(
            name=THREAD_RUNTIME_REFRESH,
            target=self._retry_runtime,
        )

    def _retry_runtime(self):
        self._load_latest_choices(force=True)

    def refresh(self, args=None):
        super().refresh(args)
        self._container = ListColumnContainer(columns=1)
        if thread_manager.get(THREAD_RUNTIME_REFRESH):
            self._container.add(
                TextWidget(
                    title=_("Refreshing latest choices. Return to the hub and "
                            "re-enter this spoke when the refresh completes.")
                )
            )
            self.window.add_with_separator(self._container)
            return
        if not self._runtime_ready:
            self._container.add(
                TextWidget(
                    title=_("Latest choices unavailable. Configure networking "
                            "and return to retry. %s") % self._runtime_error
                )
            )
            self.window.add_with_separator(self._container)
            return
        self._container.add(
            CheckboxWidget(
                title=_(
                    "Minimal desktop apps - keep the Niri and Noctalia "
                    "baseline without default desktop applications"
                ),
                completed=self._desktop_app_profile == "minimal",
            ),
            callback=self._toggle_desktop_app_profile(),
        )
        for category in self._categories:
            for choice in category.choices:
                title = "%s: %s" % (category.label, choice.label)
                if choice.description:
                    title = "%s - %s" % (title, choice.description)
                self._container.add(
                    CheckboxWidget(
                        title=title,
                        completed=choice.id
                        in self._selections.get(category.id, []),
                    ),
                    callback=self._toggle_choice(category.id, choice.id),
                )
        self.window.add_with_separator(self._container)

    def apply(self):
        if not self._runtime_ready:
            return
        write_state(
            True,
            self._desktop_app_profile,
            self._selections,
            self._preferred_browser,
        )

    @property
    def ready(self):
        return not thread_manager.get(THREAD_RUNTIME_REFRESH)

    def execute(self):
        pass

    @property
    def completed(self):
        return self._runtime_ready

    @property
    def mandatory(self):
        return True

    @property
    def status(self):
        if thread_manager.get(THREAD_RUNTIME_REFRESH):
            return _("Refreshing latest choices")
        if not self._runtime_ready:
            return _("Latest choices unavailable")
        count = selected_choice_count(self._selections)
        profile_label = (
            _("Minimal desktop")
            if self._desktop_app_profile == "minimal"
            else _("Full desktop")
        )
        if count == 0:
            return profile_label
        if count == 1:
            return _("%s + 1 option") % profile_label
        return _("%s + %d options") % (profile_label, count)

    def input(self, args, key):
        if self._container.process_user_input(key):
            self.apply()
            return InputState.PROCESSED_AND_REDRAW

        if key.lower() == Prompt.CONTINUE:
            self.apply()
            self.execute()
            return InputState.PROCESSED_AND_CLOSE

        return super().input(args, key)

    def _toggle_choice(self, category_id, choice_id):
        def toggle(data):
            selected = self._selections.setdefault(category_id, [])
            if choice_id in selected:
                self._selections[category_id] = [
                    item for item in selected if item != choice_id
                ]
            else:
                selected.append(choice_id)

            if category_id == "browsers" and self._preferred_browser == choice_id:
                self._preferred_browser = ""

        return toggle

    def _toggle_desktop_app_profile(self):
        def toggle(data):
            del data
            if self._desktop_app_profile == "minimal":
                self._desktop_app_profile = "full"
            else:
                self._desktop_app_profile = "minimal"

            profile_defaults = default_selections(
                self._categories,
                self._desktop_app_profile,
            )
            self._selections["desktop"] = profile_defaults.get("desktop", [])

        return toggle
