"""Choice catalog and selection-file helpers for the Anaconda add-on."""

import os
import subprocess
import sys
import tempfile
from pathlib import Path

from org_zz_fedora.constants import (
    CATEGORY_ORDER,
    DEFAULT_DESKTOP_APP_PROFILE,
    DESKTOP_APP_PROFILES,
    SELECTION_FILE,
)

PACKAGE_ROOT = Path(__file__).resolve().parent
REMOTE_RUNTIME_ROOT = Path("/run/zz-fedora/repository")
INSTALLER_DESKTOP_APP_PROFILE_FILE = Path(
    "/etc/zz-fedora/desktop-app-profile"
)
INSTALL_REPO_ROOT = Path("/run/install/repo/zz-fedora")
SOURCE_TREE_ROOT = Path(__file__).resolve().parents[3]

CATEGORY_LABELS = {
    "browsers": "Browsers",
    "desktop": "Desktop apps",
    "ai": "AI tools",
    "dev": "Development tools",
    "dotnet": ".NET SDK",
    "office": "Office",
    "gaming": "Gaming",
    "media": "Multimedia",
}


class Choice:
    """A single optional install choice from the compiled choice catalog."""

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


def _catalog_root():
    for root in (
        REMOTE_RUNTIME_ROOT,
        INSTALL_REPO_ROOT,
        PACKAGE_ROOT,
        SOURCE_TREE_ROOT,
    ):
        if (root / "catalog/units").is_dir() and (root / "lib/catalog.py").is_file():
            return root
    return PACKAGE_ROOT


def _compile_catalog(root, out_dir):
    result = subprocess.run(
        [
            sys.executable or "python3",
            str(root / "lib/catalog.py"),
            "--root",
            str(root),
            "compile",
            "--out",
            str(out_dir),
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if result.returncode != 0:
        detail = result.stderr.strip().splitlines()
        detail = detail[-1] if detail else "catalog compilation failed"
        raise RuntimeError(
            "Could not read the choice catalog: {}".format(detail)
        )


def _category_ids(compiled_dir):
    listing = compiled_dir / "categories.list"
    try:
        lines = listing.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return []
    discovered = {line.strip() for line in lines if line.strip()}
    ordered = [category_id for category_id in CATEGORY_ORDER if category_id in discovered]
    ordered.extend(sorted(discovered.difference(ordered)))
    return ordered


def _category_label(category_id):
    generated = category_id.replace("-", " ").replace("_", " ").capitalize()
    return CATEGORY_LABELS.get(category_id, generated)


def _read_choice_rows(path):
    choices = []
    with open(path, "r", encoding="utf-8") as catalog:
        for raw_line in catalog:
            line = raw_line.rstrip("\n")
            if not line or line.startswith("#"):
                continue

            fields = line.split("\t")
            if len(fields) != 5:
                continue

            choice_id, label, default_flag, _unit_ids, description = fields
            choices.append(
                Choice(
                    choice_id=choice_id,
                    label=label,
                    default=default_flag == "1",
                    description=description,
                )
            )
    return choices


def read_categories():
    """Read Fedora optional choices from the refreshed catalog snapshot."""

    root = _catalog_root()
    with tempfile.TemporaryDirectory(prefix="zz-fedora-catalog.") as out_dir:
        compiled_dir = Path(out_dir)
        _compile_catalog(root, compiled_dir)

        categories = []
        for category_id in _category_ids(compiled_dir):
            path = compiled_dir / "choices" / ("%s.tsv" % category_id)
            if not path.is_file():
                continue

            choices = _read_choice_rows(path)
            if choices:
                categories.append(
                    Category(
                        category_id=category_id,
                        label=_category_label(category_id),
                        choices=choices,
                    )
                )

    return categories


def validate_desktop_app_profile(desktop_app_profile):
    """Return a supported desktop app profile or reject the value."""

    if desktop_app_profile not in DESKTOP_APP_PROFILES:
        raise ValueError(
            "Unsupported desktop app profile: {}".format(desktop_app_profile)
        )
    return desktop_app_profile


def installer_default_desktop_app_profile():
    """Read an installer-image profile override when one is provided."""

    try:
        desktop_app_profile = (
            INSTALLER_DESKTOP_APP_PROFILE_FILE.read_text(encoding="utf-8")
            .strip()
        )
    except FileNotFoundError:
        return DEFAULT_DESKTOP_APP_PROFILE

    if desktop_app_profile not in DESKTOP_APP_PROFILES:
        return DEFAULT_DESKTOP_APP_PROFILE
    return desktop_app_profile


def default_selections(
    categories,
    desktop_app_profile=DEFAULT_DESKTOP_APP_PROFILE,
):
    desktop_app_profile = validate_desktop_app_profile(desktop_app_profile)
    selections = {}
    for category in categories:
        if category.id == "desktop" and desktop_app_profile == "minimal":
            selections[category.id] = []
            continue
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
    """Return enabled state, profile, category selections, and browser."""

    categories = categories or read_categories()
    desktop_app_profile = installer_default_desktop_app_profile()
    selections = default_selections(categories, desktop_app_profile)
    preferred_browser = ""

    if not os.path.exists(SELECTION_FILE):
        return False, desktop_app_profile, selections, preferred_browser

    valid_ids = _valid_choice_ids(categories)
    stored_selections = {}
    with open(SELECTION_FILE, "r", encoding="utf-8") as state_file:
        for raw_line in state_file:
            line = raw_line.strip()
            if not line or "=" not in line:
                continue

            key, value = line.split("=", 1)
            if key == "desktop_app_profile":
                if value in DESKTOP_APP_PROFILES:
                    desktop_app_profile = value
            elif key.startswith("select."):
                category_id = key[len("select.") :]
                if category_id not in valid_ids:
                    continue
                stored_selections[category_id] = [
                    item
                    for item in _split_selection(value)
                    if item in valid_ids[category_id]
                ]
            elif key == "preferred_browser":
                preferred_browser = value

    selections = default_selections(categories, desktop_app_profile)
    selections.update(stored_selections)

    selected_browsers = [
        item
        for item in selections.get("browsers", [])
        if item in valid_ids.get("browsers", set())
    ]
    if preferred_browser not in selected_browsers:
        preferred_browser = ""

    return True, desktop_app_profile, selections, preferred_browser


def write_state(
    enabled,
    desktop_app_profile,
    selections,
    preferred_browser="",
):
    """Persist the Anaconda choices for the installation task."""

    if not enabled:
        try:
            os.unlink(SELECTION_FILE)
        except FileNotFoundError:
            pass
        return

    desktop_app_profile = validate_desktop_app_profile(desktop_app_profile)
    categories = read_categories()
    valid_ids = _valid_choice_ids(categories)
    selected_browsers = [
        item
        for item in selections.get("browsers", [])
        if item in valid_ids.get("browsers", set())
    ]
    if preferred_browser not in selected_browsers:
        preferred_browser = ""

    state_dir = os.path.dirname(SELECTION_FILE)
    os.makedirs(state_dir, mode=0o700, exist_ok=True)
    temporary_path = None
    try:
        with tempfile.NamedTemporaryFile(
            "w",
            encoding="utf-8",
            dir=state_dir,
            prefix=".install-selected.",
            delete=False,
        ) as state_file:
            temporary_path = state_file.name
            state_file.write("selected=1\n")
            state_file.write(
                "desktop_app_profile=%s\n" % desktop_app_profile
            )
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
        os.chmod(temporary_path, 0o600)
        os.replace(temporary_path, SELECTION_FILE)
    finally:
        if temporary_path and os.path.exists(temporary_path):
            os.unlink(temporary_path)


def selected_choice_count(selections):
    return sum(len(selected) for selected in selections.values())
