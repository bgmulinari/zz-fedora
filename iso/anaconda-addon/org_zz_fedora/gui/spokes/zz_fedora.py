"""Graphical Anaconda spoke for selecting ZZ Fedora options."""

from gi.repository import GLib, Gtk

from pyanaconda.core.constants import THREAD_PAYLOAD
from pyanaconda.core.threads import thread_manager
from pyanaconda.ui.categories.software import SoftwareCategory
from pyanaconda.ui.communication import hubQ
from pyanaconda.ui.gui.spokes import NormalSpoke
from pyanaconda.ui.gui.utils import gtk_call_once

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


class ZZFedoraSpoke(NormalSpoke):
    """Mandatory custom-ISO spoke for selecting optional setup components."""

    builderObjects = ["zzFedoraSpokeWindow"]
    mainWidgetName = "zzFedoraSpokeWindow"
    uiFile = "zz_fedora.glade"

    category = SoftwareCategory
    icon = "system-software-install-symbolic"
    title = N_("ZZ Fedora")

    @classmethod
    def should_run(cls, environment, data):
        """Show the spoke during the installer flow."""

        return True

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        self._categories = []
        self._category_by_id = {}
        self._category_rows = {}
        self._category_summary_labels = {}
        self._choice_buttons = {}
        self._selections = {}
        self._preferred_browser = ""
        self._current_category_id = ""
        self._runtime_ready = False
        self._runtime_error = ""
        self._refreshing = False
        self._category_list_box = None
        self._choice_list_box = None
        self._choice_header_label = None
        self._preferred_browser_box = None
        self._preferred_browser_combo = None

    def initialize(self):
        super().initialize()
        self._category_list_box = self.builder.get_object("categoryListBox")
        self._choice_list_box = self.builder.get_object("choiceListBox")
        self._choice_header_label = self.builder.get_object("choiceHeaderLabel")
        self._preferred_browser_box = self.builder.get_object("preferredBrowserBox")
        self._preferred_browser_combo = self.builder.get_object(
            "preferredBrowserCombo"
        )
        self._preferred_browser_combo.connect(
            "changed",
            self._on_preferred_browser_changed,
        )
        self._category_list_box.connect("row-selected", self._on_category_selected)

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
            hubQ.send_ready(self.__class__.__name__)
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
        self._category_by_id = {
            category.id: category for category in self._categories
        }
        enabled, selections, preferred_browser = read_state(self._categories)
        if enabled:
            self._selections = selections
            self._preferred_browser = preferred_browser
        else:
            self._selections = default_selections(self._categories)
            self._preferred_browser = ""
            self._persist_state()
        self._runtime_ready = True
        self._runtime_error = ""
        return True

    def refresh(self):
        if not self._runtime_ready:
            if not thread_manager.get(THREAD_RUNTIME_REFRESH):
                self._start_runtime_retry()
            self._show_runtime_progress()
            return

        self._build_category_rows()
        enabled, selections, preferred_browser = read_state(self._categories)
        if enabled:
            self._selections = selections
            self._preferred_browser = preferred_browser
        else:
            self._selections = default_selections(self._categories)
            self._preferred_browser = ""
            self._persist_state()

        self._refreshing = True
        self._update_category_summaries()
        self._refreshing = False

        if not self._current_category_id and self._categories:
            first_row = self._category_list_box.get_row_at_index(0)
            if first_row is not None:
                self._category_list_box.select_row(first_row)
        else:
            self._render_choices()

    def _start_runtime_retry(self):
        self._runtime_error = ""
        hubQ.send_not_ready(self.__class__.__name__)
        thread_manager.add_thread(
            name=THREAD_RUNTIME_REFRESH,
            target=self._retry_runtime,
        )

    def _retry_runtime(self):
        try:
            self._load_latest_choices(force=True)
        finally:
            gtk_call_once(self._finish_runtime_retry)
            hubQ.send_ready(self.__class__.__name__)

    def _finish_runtime_retry(self):
        if self._runtime_ready:
            self.refresh()
        else:
            self._show_runtime_error()

    def _clear_runtime_view(self, message):
        for list_box in (self._category_list_box, self._choice_list_box):
            for child in list_box.get_children():
                list_box.remove(child)
        self._choice_header_label.set_text(message)
        self._preferred_browser_box.set_visible(False)

    def _show_runtime_progress(self):
        self._clear_runtime_view(_("Refreshing latest choices"))

    def _show_runtime_error(self):
        self._clear_runtime_view(
            _("Latest choices unavailable. Configure networking and return "
              "to retry. %s") % self._runtime_error
        )

    def apply(self):
        if not self._runtime_ready:
            return
        self._persist_state()

    def execute(self):
        # The add-on D-Bus installation task consumes the persisted selection.
        pass

    @property
    def ready(self):
        return not thread_manager.get(THREAD_RUNTIME_REFRESH)

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
        enabled, selections, _preferred_browser = read_state(self._categories)
        if not enabled:
            selections = default_selections(self._categories)

        count = selected_choice_count(selections)
        if count == 0:
            return _("Base desktop")
        if count == 1:
            return _("Base desktop + 1 option")
        return _("Base desktop + %d options") % count

    def _build_category_rows(self):
        for child in self._category_list_box.get_children():
            self._category_list_box.remove(child)

        self._category_rows = {}
        self._category_summary_labels = {}

        for category in self._categories:
            row = Gtk.ListBoxRow()
            row.category_id = category.id

            box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            box.set_margin_top(8)
            box.set_margin_bottom(8)
            box.set_margin_left(12)
            box.set_margin_right(12)

            title = Gtk.Label()
            title.set_markup(
                "<b>%s</b>" % GLib.markup_escape_text(category.label)
            )
            title.set_xalign(0)
            title.set_line_wrap(True)

            summary = Gtk.Label()
            summary.set_xalign(0)
            summary.set_line_wrap(True)
            summary.get_style_context().add_class("dim-label")

            box.pack_start(title, False, False, 0)
            box.pack_start(summary, False, False, 0)
            row.add(box)

            self._category_rows[category.id] = row
            self._category_summary_labels[category.id] = summary
            self._category_list_box.add(row)

        self._category_list_box.show_all()
        self._update_category_summaries()

    def _on_category_selected(self, _list_box, row):
        if row is None:
            return

        self._current_category_id = row.category_id
        self._render_choices()

    def _render_choices(self):
        category = self._category_by_id.get(self._current_category_id)
        if category is None:
            return

        self._choice_header_label.set_text(
            _("Optional software for %s") % category.label
        )

        for child in self._choice_list_box.get_children():
            self._choice_list_box.remove(child)

        self._choice_buttons = {}
        for choice in category.choices:
            row = Gtk.ListBoxRow()
            row.set_selectable(False)
            row.set_activatable(True)

            row_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            row_box.set_margin_top(6)
            row_box.set_margin_bottom(6)
            row_box.set_margin_left(12)
            row_box.set_margin_right(12)

            button = Gtk.CheckButton()
            button.set_valign(Gtk.Align.START)
            button.set_active(choice.id in self._selections.get(category.id, []))
            button.connect(
                "toggled",
                self._on_choice_toggled,
                category.id,
                choice.id,
            )

            text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            title = Gtk.Label()
            title.set_markup("<b>%s</b>" % GLib.markup_escape_text(choice.label))
            title.set_xalign(0)
            title.set_line_wrap(True)

            description = Gtk.Label(label=choice.description)
            description.set_xalign(0)
            description.set_line_wrap(True)
            description.get_style_context().add_class("dim-label")

            text_box.pack_start(title, False, False, 0)
            if choice.description:
                text_box.pack_start(description, False, False, 0)

            row_box.pack_start(button, False, False, 0)
            row_box.pack_start(text_box, True, True, 0)
            row.add(row_box)
            row.connect("activate", self._on_choice_row_activated, button)

            self._choice_buttons[(category.id, choice.id)] = button
            self._choice_list_box.add(row)

        self._choice_list_box.show_all()
        self._update_preferred_browser_combo()

    def _on_choice_row_activated(self, _row, button):
        button.set_active(not button.get_active())

    def _on_choice_toggled(self, button, category_id, choice_id):
        if self._refreshing:
            return

        selected = self._selections.setdefault(category_id, [])
        if button.get_active():
            if choice_id not in selected:
                selected.append(choice_id)
        else:
            self._selections[category_id] = [
                item for item in selected if item != choice_id
            ]
            if category_id == "browsers" and self._preferred_browser == choice_id:
                self._preferred_browser = ""

        self._update_category_summaries()
        self._update_preferred_browser_combo()
        self._persist_state()

    def _on_preferred_browser_changed(self, combo):
        if self._refreshing:
            return

        self._preferred_browser = combo.get_active_id() or ""
        self._persist_state()

    def _update_category_summaries(self):
        for category in self._categories:
            count = len(self._selections.get(category.id, []))
            if count == 0:
                summary = _("No optional choices")
            elif count == 1:
                summary = _("1 selected")
            else:
                summary = _("%d selected") % count
            self._category_summary_labels[category.id].set_text(summary)

    def _update_preferred_browser_combo(self):
        if (
            self._preferred_browser_combo is None
            or self._preferred_browser_box is None
        ):
            return

        selected_browsers = self._selections.get("browsers", [])
        browser_category = self._category_by_id.get("browsers")
        browser_choices = []
        if browser_category is not None:
            browser_choices = [
                choice
                for choice in browser_category.choices
                if choice.id in selected_browsers
            ]

        self._refreshing = True
        self._preferred_browser_combo.remove_all()
        for choice in browser_choices:
            self._preferred_browser_combo.append(choice.id, choice.label)

        visible = self._current_category_id == "browsers" and len(browser_choices) > 1
        if len(browser_choices) > 1:
            if self._preferred_browser not in selected_browsers:
                self._preferred_browser = browser_choices[0].id
            if visible:
                self._preferred_browser_combo.set_active_id(self._preferred_browser)
        else:
            self._preferred_browser = ""
        self._preferred_browser_box.set_visible(visible)
        self._refreshing = False

    def _persist_state(self):
        write_state(True, self._selections, self._preferred_browser)
