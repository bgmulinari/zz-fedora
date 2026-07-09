"""Text Anaconda spoke for selecting ZZ Linux Setup."""

from simpleline.render.containers import ListColumnContainer
from simpleline.render.prompt import Prompt
from simpleline.render.screen import InputState
from simpleline.render.widgets import CheckboxWidget

from pyanaconda.ui.categories.software import SoftwareCategory
from pyanaconda.ui.tui.spokes import NormalTUISpoke

from org_zz_linux_setup.selection import (
    default_selections,
    read_categories,
    read_state,
    selected_choice_count,
    write_state,
)

__all__ = ["ZZLinuxSetupSpoke"]

_ = lambda x: x
N_ = lambda x: x


class ZZLinuxSetupSpoke(NormalTUISpoke):
    """Optional TUI spoke that controls repository post-install setup."""

    category = SoftwareCategory

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self.title = N_("ZZ Linux Setup")
        self._categories = []
        self._container = None
        self._selections = {}
        self._preferred_browser = ""

    @classmethod
    def should_run(cls, environment, data):
        return True

    def setup(self, args=None):
        super().setup(args)
        self._categories = read_categories()
        enabled, self._selections, self._preferred_browser = read_state(self._categories)
        if not enabled:
            self._selections = default_selections(self._categories)
            self._preferred_browser = ""
            self.apply()
        return True

    def refresh(self, args=None):
        super().refresh(args)
        self._container = ListColumnContainer(columns=1)
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
        write_state(True, self._selections, self._preferred_browser)

    def execute(self):
        pass

    @property
    def completed(self):
        return True

    @property
    def mandatory(self):
        return False

    @property
    def status(self):
        count = selected_choice_count(self._selections)
        if count == 0:
            return _("Base desktop")
        if count == 1:
            return _("Base desktop + 1 option")
        return _("Base desktop + %d options") % count

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
