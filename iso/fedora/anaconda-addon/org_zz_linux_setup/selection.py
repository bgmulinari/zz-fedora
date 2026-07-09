"""Choice catalog and selection-file helpers for the Anaconda add-on."""

import os
from pathlib import Path

from org_zz_linux_setup.constants import CATEGORY_ORDER, SELECTION_FILE

PACKAGE_CHOICES_DIR = Path(__file__).resolve().parent / "choices"
INSTALL_REPO_CHOICES_DIR = Path("/run/install/repo/zz-linux-setup/choices")
SOURCE_TREE_CHOICES_DIR = Path(__file__).resolve().parents[4] / "choices"

CATEGORY_LABELS = {
    "browsers": "Browsers",
    "ai": "AI tools",
    "dev": "Development tools",
    "dotnet": ".NET SDK",
    "office": "Office",
    "gaming": "Gaming",
    "media": "Multimedia",
}


class Choice:
    """A single optional install choice from choices/fedora/*.conf."""

    def __init__(self, choice_id, label, default, description):
        self.id = choice_id
        self.label = label
        self.default = default
        self.description = description


class Category:
    """A grouped set of optional install choices."""

    def __init__(self, category_id, label, choices):
        self.id = category_id
        self.label = label
        self.choices = choices


def _choice_catalog_root():
    for root in (
        PACKAGE_CHOICES_DIR,
        INSTALL_REPO_CHOICES_DIR,
        SOURCE_TREE_CHOICES_DIR,
    ):
        if (root / "fedora").is_dir():
            return root
    return PACKAGE_CHOICES_DIR


def _catalog_path(root, category_id):
    return root / "fedora" / ("%s.conf" % category_id)


def read_categories():
    """Read Fedora optional choices from the embedded catalog snapshot."""

    root = _choice_catalog_root()
    categories = []
    for category_id in CATEGORY_ORDER:
        path = _catalog_path(root, category_id)
        if not path.exists():
            continue

        choices = []
        with open(path, "r", encoding="utf-8") as catalog:
            for raw_line in catalog:
                line = raw_line.rstrip("\n")
                if not line or line.startswith("#"):
                    continue

                fields = line.split("\t")
                if len(fields) != 5:
                    continue

                choice_id, label, default_flag, _bundle_ids, description = fields
                choices.append(
                    Choice(
                        choice_id=choice_id,
                        label=label,
                        default=default_flag == "1",
                        description=description,
                    )
                )

        if choices:
            categories.append(
                Category(
                    category_id=category_id,
                    label=CATEGORY_LABELS.get(category_id, category_id.title()),
                    choices=choices,
                )
            )

    return categories


def default_selections(categories):
    selections = {}
    for category in categories:
        selections[category.id] = [
            choice.id for choice in category.choices if choice.default
        ]
    return selections


def _valid_choice_ids(categories):
    return {
        category.id: {choice.id for choice in category.choices}
        for category in categories
    }


def _split_selection(value):
    if not value:
        return []
    return [item for item in value.split(",") if item]


def read_state(categories=None):
    """Return enabled state, category selections, and preferred browser."""

    categories = categories or read_categories()
    selections = default_selections(categories)
    preferred_browser = ""

    if not os.path.exists(SELECTION_FILE):
        return False, selections, preferred_browser

    valid_ids = _valid_choice_ids(categories)
    with open(SELECTION_FILE, "r", encoding="utf-8") as state_file:
        for raw_line in state_file:
            line = raw_line.strip()
            if not line or "=" not in line:
                continue

            key, value = line.split("=", 1)
            if key.startswith("select."):
                category_id = key[len("select.") :]
                if category_id not in valid_ids:
                    continue
                selections[category_id] = [
                    item
                    for item in _split_selection(value)
                    if item in valid_ids[category_id]
                ]
            elif key == "preferred_browser":
                preferred_browser = value

    selected_browsers = selections.get("browsers", [])
    if preferred_browser not in selected_browsers:
        preferred_browser = ""

    return True, selections, preferred_browser


def write_state(enabled, selections, preferred_browser=""):
    """Persist the Anaconda choices for the installation task."""

    if not enabled:
        try:
            os.unlink(SELECTION_FILE)
        except FileNotFoundError:
            pass
        return

    categories = read_categories()
    valid_ids = _valid_choice_ids(categories)
    selected_browsers = selections.get("browsers", [])
    if preferred_browser not in selected_browsers:
        preferred_browser = ""

    os.makedirs(os.path.dirname(SELECTION_FILE), exist_ok=True)
    with open(SELECTION_FILE, "w", encoding="utf-8") as state_file:
        state_file.write("selected=1\n")
        for category in categories:
            selected_ids = [
                item
                for item in selections.get(category.id, [])
                if item in valid_ids[category.id]
            ]
            state_file.write(
                "select.%s=%s\n" % (category.id, ",".join(selected_ids))
            )
        state_file.write("preferred_browser=%s\n" % preferred_browser)


def selected_choice_count(selections):
    return sum(len(selected) for selected in selections.values())
