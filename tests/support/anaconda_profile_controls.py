#!/usr/bin/env python3
"""Behavioral tests for the Anaconda desktop profile controls."""

import importlib.util
import sys
import types
import unittest
from pathlib import Path


ROOT_DIR = Path(__file__).resolve().parents[2]
ADDON_DIR = ROOT_DIR / "iso/anaconda-addon/org_zz_fedora"
SELECTION_WRITES = []
GUI_BUILDER = None


class Choice:
    def __init__(self, choice_id, default):
        self.id = choice_id
        self.label = choice_id.title()
        self.default = default
        self.description = ""


class Category:
    def __init__(self, category_id, choices):
        self.id = category_id
        self.label = category_id.title()
        self.choices = choices


CATEGORIES = [
    Category("desktop", [Choice("boxes", True), Choice("papers", True)]),
    Category("dev", [Choice("docker", True)]),
]


def install_module(name, **attributes):
    module = types.ModuleType(name)
    for key, value in attributes.items():
        setattr(module, key, value)
    sys.modules[name] = module
    return module


def install_package(name):
    module = install_module(name)
    module.__path__ = []
    return module


def load_module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    sys.modules[name] = module
    spec.loader.exec_module(module)
    return module


def default_selections(categories, desktop_app_profile="full"):
    selections = {}
    for category in categories:
        if category.id == "desktop" and desktop_app_profile == "minimal":
            selections[category.id] = []
        else:
            selections[category.id] = [
                choice.id for choice in category.choices if choice.default
            ]
    return selections


def write_state(enabled, profile, selections, preferred_browser=""):
    SELECTION_WRITES.append(
        (
            enabled,
            profile,
            {category: list(values) for category, values in selections.items()},
            preferred_browser,
        )
    )


class ThreadManager:
    def __init__(self):
        self.added = []

    def add_thread(self, **kwargs):
        self.added.append(kwargs)

    def get(self, name):
        del name
        return None

    def wait(self, name):
        del name


class HubQueue:
    def send_ready(self, name):
        del name

    def send_not_ready(self, name):
        del name


class SignalWidget:
    def __init__(self):
        self.handlers = {}

    def connect(self, signal, callback, *args):
        self.handlers.setdefault(signal, []).append((callback, args))


class ComboBoxText(SignalWidget):
    def __init__(self):
        super().__init__()
        self.items = []
        self.active_id = None

    def append(self, item_id, label):
        self.items.append((item_id, label))

    def get_active_id(self):
        return self.active_id

    def set_active_id(self, item_id):
        if item_id == self.active_id:
            return
        self.active_id = item_id
        for callback, args in self.handlers.get("changed", []):
            callback(self, *args)


class Builder:
    def __init__(self):
        self.objects = {
            "categoryListBox": SignalWidget(),
            "choiceListBox": SignalWidget(),
            "choiceHeaderLabel": SignalWidget(),
            "desktopAppProfileCombo": ComboBoxText(),
            "preferredBrowserBox": SignalWidget(),
            "preferredBrowserCombo": ComboBoxText(),
        }

    def get_object(self, name):
        return self.objects[name]


class Window:
    def __init__(self):
        self.containers = []

    def add_with_separator(self, container):
        self.containers.append(container)


class NormalSpoke:
    def __init__(self, *args, **kwargs):
        del args, kwargs
        self.builder = GUI_BUILDER
        self.payload = None

    def initialize(self):
        pass

    def initialize_start(self):
        pass

    def initialize_done(self):
        pass


class NormalTUISpoke:
    def __init__(self, *args, **kwargs):
        del args, kwargs
        self.window = Window()
        self.payload = None

    def initialize(self):
        pass

    def initialize_start(self):
        pass

    def initialize_done(self):
        pass

    def setup(self, args=None):
        del args

    def refresh(self, args=None):
        del args

    def input(self, args, key):
        del args, key
        return "unhandled"


class CheckboxWidget:
    def __init__(self, title, completed):
        self.title = title
        self.completed = completed


class TextWidget:
    def __init__(self, title):
        self.title = title


class ListColumnContainer:
    def __init__(self, columns):
        self.columns = columns
        self.entries = []

    def add(self, widget, callback=None):
        self.entries.append((widget, callback))

    def process_user_input(self, key):
        if not key.isdigit():
            return False
        index = int(key) - 1
        if index < 0 or index >= len(self.entries):
            return False
        callback = self.entries[index][1]
        if callback is None:
            return False
        callback(None)
        return True


class InputState:
    PROCESSED_AND_REDRAW = "redraw"
    PROCESSED_AND_CLOSE = "close"


class Prompt:
    CONTINUE = "c"


def install_import_stubs():
    gi = install_package("gi")
    repository = install_module("gi.repository")
    repository.GLib = types.SimpleNamespace()
    repository.Gtk = types.SimpleNamespace()
    gi.repository = repository

    install_package("pyanaconda")
    install_package("pyanaconda.core")
    install_module("pyanaconda.core.constants", THREAD_PAYLOAD="payload")
    install_module(
        "pyanaconda.core.threads",
        thread_manager=ThreadManager(),
    )
    install_package("pyanaconda.ui")
    install_package("pyanaconda.ui.categories")
    install_module(
        "pyanaconda.ui.categories.software",
        SoftwareCategory=type("SoftwareCategory", (), {}),
    )
    install_module("pyanaconda.ui.communication", hubQ=HubQueue())
    install_package("pyanaconda.ui.gui")
    install_module("pyanaconda.ui.gui.spokes", NormalSpoke=NormalSpoke)
    install_module(
        "pyanaconda.ui.gui.utils",
        gtk_call_once=lambda callback: callback(),
    )
    install_package("pyanaconda.ui.tui")
    install_module("pyanaconda.ui.tui.spokes", NormalTUISpoke=NormalTUISpoke)

    install_package("simpleline")
    install_package("simpleline.render")
    install_module(
        "simpleline.render.containers",
        ListColumnContainer=ListColumnContainer,
    )
    install_module("simpleline.render.prompt", Prompt=Prompt)
    install_module("simpleline.render.screen", InputState=InputState)
    install_module(
        "simpleline.render.widgets",
        CheckboxWidget=CheckboxWidget,
        TextWidget=TextWidget,
    )

    install_package("org_zz_fedora")
    install_package("org_zz_fedora.gui")
    install_package("org_zz_fedora.gui.spokes")
    install_package("org_zz_fedora.tui")
    install_package("org_zz_fedora.tui.spokes")
    install_module(
        "org_zz_fedora.constants",
        DEFAULT_DESKTOP_APP_PROFILE="full",
    )
    install_module(
        "org_zz_fedora.runtime",
        THREAD_RUNTIME_REFRESH="runtime-refresh",
        payload_proxy_url=lambda payload: "",
        refresh_runtime=lambda proxy_url, force=False: None,
    )
    install_module(
        "org_zz_fedora.selection",
        default_selections=default_selections,
        read_categories=lambda: CATEGORIES,
        read_state=lambda categories: (
            False,
            "full",
            default_selections(categories),
            "",
        ),
        selected_choice_count=lambda selections: sum(
            len(values) for values in selections.values()
        ),
        write_state=write_state,
    )


install_import_stubs()
GUI_MODULE = load_module(
    "org_zz_fedora.gui.spokes.zz_fedora",
    ADDON_DIR / "gui/spokes/zz_fedora.py",
)
TUI_MODULE = load_module(
    "org_zz_fedora.tui.spokes.zz_fedora",
    ADDON_DIR / "tui/spokes/zz_fedora.py",
)


class ProfileControlTests(unittest.TestCase):
    def setUp(self):
        SELECTION_WRITES.clear()

    def test_gui_combo_changes_profile_defaults_and_persists(self):
        global GUI_BUILDER
        GUI_BUILDER = Builder()
        spoke = GUI_MODULE.ZZFedoraSpoke()
        spoke.initialize()
        spoke._categories = CATEGORIES
        spoke._selections = {
            "desktop": ["boxes", "papers"],
            "dev": ["docker"],
        }
        events = []
        spoke._render_choices = lambda: events.append(
            ("render", spoke._refreshing)
        )
        spoke._update_category_summaries = lambda: events.append(
            ("summaries", spoke._refreshing)
        )

        combo = GUI_BUILDER.get_object("desktopAppProfileCombo")
        self.assertEqual(
            combo.items,
            [
                ("full", "Full desktop"),
                ("minimal", "Minimal desktop apps"),
            ],
        )

        combo.set_active_id("minimal")
        self.assertEqual(spoke._desktop_app_profile, "minimal")
        self.assertEqual(spoke._selections["desktop"], [])
        self.assertEqual(spoke._selections["dev"], ["docker"])
        self.assertEqual(
            SELECTION_WRITES[-1],
            (True, "minimal", {"desktop": [], "dev": ["docker"]}, ""),
        )
        self.assertEqual(events, [("render", True), ("summaries", True)])
        self.assertFalse(spoke._refreshing)

        spoke._selections["desktop"] = ["boxes"]
        combo.set_active_id("full")
        self.assertEqual(spoke._desktop_app_profile, "full")
        self.assertEqual(spoke._selections["desktop"], ["boxes", "papers"])
        self.assertEqual(spoke._selections["dev"], ["docker"])
        self.assertEqual(SELECTION_WRITES[-1][1], "full")
        self.assertEqual(SELECTION_WRITES[-1][2]["desktop"], ["boxes", "papers"])

    def test_tui_checkbox_changes_profile_defaults_and_persists(self):
        spoke = TUI_MODULE.ZZFedoraSpoke()
        spoke._runtime_ready = True
        spoke._categories = CATEGORIES
        spoke._selections = {
            "desktop": ["boxes", "papers"],
            "dev": ["docker"],
        }

        spoke.refresh()
        profile_widget, callback = spoke._container.entries[0]
        self.assertIsNotNone(callback)
        self.assertIn("Minimal desktop apps", profile_widget.title)
        self.assertFalse(profile_widget.completed)

        result = spoke.input(None, "1")
        self.assertEqual(result, InputState.PROCESSED_AND_REDRAW)
        self.assertEqual(spoke._desktop_app_profile, "minimal")
        self.assertEqual(spoke._selections["desktop"], [])
        self.assertEqual(spoke._selections["dev"], ["docker"])
        self.assertEqual(
            SELECTION_WRITES[-1],
            (True, "minimal", {"desktop": [], "dev": ["docker"]}, ""),
        )

        spoke._selections["desktop"] = ["boxes"]
        spoke.refresh()
        profile_widget, _callback = spoke._container.entries[0]
        self.assertTrue(profile_widget.completed)
        spoke.input(None, "1")
        self.assertEqual(spoke._desktop_app_profile, "full")
        self.assertEqual(spoke._selections["desktop"], ["boxes", "papers"])
        self.assertEqual(spoke._selections["dev"], ["docker"])
        self.assertEqual(SELECTION_WRITES[-1][1], "full")
        self.assertEqual(SELECTION_WRITES[-1][2]["desktop"], ["boxes", "papers"])


if __name__ == "__main__":
    unittest.main()
