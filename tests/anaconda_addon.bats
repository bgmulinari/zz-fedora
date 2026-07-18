#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

setup() {
  setup_test_env
}

@test "Anaconda GUI and TUI profile controls update and persist selections" {
  run python3 "$ROOT_DIR/tests/support/anaconda_profile_controls.py"

  [ "$status" -eq 0 ]
}

@test "Anaconda selection state is atomic, private, and filters invalid choices" {
  run env ZZ_REPO_ROOT="$ROOT_DIR" ZZ_TEST_ROOT="$TEST_ROOT" python3 - <<'PY'
import importlib.util
import os
import stat
import sys
import types
from pathlib import Path

repo = Path(os.environ["ZZ_REPO_ROOT"])
state = Path(os.environ["ZZ_TEST_ROOT"]) / "run/zz-fedora/install-selected"
package = types.ModuleType("org_zz_fedora")
package.__path__ = []
constants = types.ModuleType("org_zz_fedora.constants")
constants.CATEGORY_ORDER = (
    "browsers",
    "desktop",
    "ai",
    "dev",
    "dotnet",
    "office",
    "gaming",
    "media",
)
constants.DEFAULT_DESKTOP_APP_PROFILE = "full"
constants.DESKTOP_APP_PROFILES = ("full", "minimal")
constants.SELECTION_FILE = str(state)
sys.modules["org_zz_fedora"] = package
sys.modules["org_zz_fedora.constants"] = constants

path = repo / "iso/anaconda-addon/org_zz_fedora/selection.py"
spec = importlib.util.spec_from_file_location("zz_fedora_selection_test", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.SOURCE_TREE_CHOICES_DIR = repo / "choices"
module.PACKAGE_CHOICES_DIR = repo / "choices"
profile_file = Path(os.environ["ZZ_TEST_ROOT"]) / "desktop-app-profile"
module.INSTALLER_DESKTOP_APP_PROFILE_FILE = profile_file

categories = module.read_categories()
defaults = module.default_selections(categories)
assert defaults["browsers"] == ["firefox"]
for category in categories:
    if category.id != "browsers":
        assert defaults[category.id] == [choice.id for choice in category.choices]
minimal_defaults = module.default_selections(categories, "minimal")
assert minimal_defaults["desktop"] == []
assert minimal_defaults["browsers"] == ["firefox"]
assert minimal_defaults["dev"] == defaults["dev"]

profile_file.write_text("minimal\n")
enabled, profile, selections, preferred = module.read_state(categories)
assert not enabled
assert profile == "minimal"
assert selections["desktop"] == []
assert preferred == ""
profile_file.write_text("not-valid\n")
assert module.installer_default_desktop_app_profile() == "full"
profile_file.write_text("minimal\n")

module.write_state(
    True,
    "minimal",
    {"browsers": ["firefox", "not-valid"], "dev": ["docker"]},
    "not-valid",
)
assert stat.S_IMODE(state.stat().st_mode) == 0o600
text = state.read_text()
assert "desktop_app_profile=minimal" in text
assert "select.browsers=firefox" in text
assert "select.dev=docker" in text
assert "not-valid" not in text
enabled, profile, selections, preferred = module.read_state(categories)
assert enabled
assert profile == "minimal"
assert selections["browsers"] == ["firefox"]
assert selections["dev"] == ["docker"]
assert selections["desktop"] == []
assert preferred == ""

try:
    module.write_state(True, "invalid", {}, "")
except ValueError as error:
    assert "Unsupported desktop app profile" in str(error)
else:
    raise AssertionError("invalid desktop app profile was accepted")
PY

  [ "$status" -eq 0 ]
}

@test "Anaconda choices prefer the refreshed remote runtime" {
  run env ZZ_REPO_ROOT="$ROOT_DIR" ZZ_TEST_ROOT="$TEST_ROOT" python3 - <<'PY'
import importlib.util
import os
import sys
import types
from pathlib import Path

repo = Path(os.environ["ZZ_REPO_ROOT"])
root = Path(os.environ["ZZ_TEST_ROOT"])
remote_choices = root / "run/zz-fedora/repository/choices"
remote_choices.mkdir(parents=True)
(remote_choices / "browsers.conf").write_text(
    "new-browser\tNew browser\t1\tbrowser-new\tFrom the refreshed runtime\n"
)
(remote_choices / "new-tools.conf").write_text(
    "new-tool\tNew tool\t1\ttool-new\tFrom a new remote catalog\n"
)

package = types.ModuleType("org_zz_fedora")
package.__path__ = []
constants = types.ModuleType("org_zz_fedora.constants")
constants.CATEGORY_ORDER = ("browsers",)
constants.DEFAULT_DESKTOP_APP_PROFILE = "full"
constants.DESKTOP_APP_PROFILES = ("full", "minimal")
constants.SELECTION_FILE = str(root / "run/zz-fedora/install-selected")
sys.modules["org_zz_fedora"] = package
sys.modules["org_zz_fedora.constants"] = constants

path = repo / "iso/anaconda-addon/org_zz_fedora/selection.py"
spec = importlib.util.spec_from_file_location("zz_fedora_remote_selection_test", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.REMOTE_RUNTIME_CHOICES_DIR = remote_choices
module.INSTALL_REPO_CHOICES_DIR = repo / "choices"
module.PACKAGE_CHOICES_DIR = repo / "choices"
module.SOURCE_TREE_CHOICES_DIR = repo / "choices"

categories = module.read_categories()
assert [category.id for category in categories] == ["browsers", "new-tools"]
assert [choice.id for choice in categories[0].choices] == ["new-browser"]
assert categories[1].label == "New tools"
assert [choice.id for choice in categories[1].choices] == ["new-tool"]
PY

  [ "$status" -eq 0 ]
}

@test "Anaconda runtime refresh invokes the embedded loader with source proxy" {
  run env ZZ_REPO_ROOT="$ROOT_DIR" ZZ_TEST_ROOT="$TEST_ROOT" python3 - <<'PY'
import importlib.util
import os
from pathlib import Path

repo = Path(os.environ["ZZ_REPO_ROOT"])
root = Path(os.environ["ZZ_TEST_ROOT"])
runtime_dir = root / "run/zz-fedora/repository"
proxy_log = root / "proxy.log"
loader = root / "runtime-loader.sh"
loader.write_text(
    "#!/usr/bin/env bash\n"
    "set -Eeuo pipefail\n"
    "printf '%s\\n' \"${https_proxy:-}\" >\"$ZZ_TEST_PROXY_LOG\"\n"
    "mkdir -p \"$ZZ_TEST_RUNTIME_DIR/choices\"\n"
    "printf '#!/usr/bin/env bash\\n' >\"$ZZ_TEST_RUNTIME_DIR/install.sh\"\n"
    "chmod +x \"$ZZ_TEST_RUNTIME_DIR/install.sh\"\n"
    "printf 'firefox\\tFirefox\\t1\\tbrowsers-firefox\\tFirefox\\n' "
    ">\"$ZZ_TEST_RUNTIME_DIR/choices/browsers.conf\"\n"
)
loader.chmod(0o755)

path = repo / "iso/anaconda-addon/org_zz_fedora/runtime.py"
spec = importlib.util.spec_from_file_location("zz_fedora_runtime_test", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.EMBEDDED_RUNTIME_LOADER = loader
module.REMOTE_RUNTIME_DIR = runtime_dir
os.environ["ZZ_TEST_PROXY_LOG"] = str(proxy_log)
os.environ["ZZ_TEST_RUNTIME_DIR"] = str(runtime_dir)

module.refresh_runtime("http://proxy.example:8080")
assert module.runtime_is_ready()
assert proxy_log.read_text().strip() == "http://proxy.example:8080"

proxy_log.unlink()
module.refresh_runtime("http://proxy.example:8080")
assert not proxy_log.exists()
module.refresh_runtime("http://proxy.example:8080", force=True)
assert proxy_log.read_text().strip() == "http://proxy.example:8080"
PY

  [ "$status" -eq 0 ]
}

@test "Anaconda installation task parses users and progress behavior" {
  run env ZZ_REPO_ROOT="$ROOT_DIR" ZZ_TEST_ROOT="$TEST_ROOT" python3 - <<'PY'
import importlib.util
import os
import sys
import types
from pathlib import Path

repo = Path(os.environ["ZZ_REPO_ROOT"])
root = Path(os.environ["ZZ_TEST_ROOT"]) / "sysroot"
(root / "etc").mkdir(parents=True)
(root / "etc/passwd").write_text(
    "root:x:0:0:root:/root:/bin/bash\n"
    "zztest:x:1000:1000:Test User:/home/zztest:/bin/bash\n"
)
(root / "etc/group").write_text("root:x:0:\nzztest:x:1000:\n")

task_module = types.ModuleType("pyanaconda.modules.common.task")
class Task:
    def __init__(self):
        self.progress = []
    def report_progress(self, message):
        self.progress.append(message)
task_module.Task = Task
sys.modules["pyanaconda"] = types.ModuleType("pyanaconda")
sys.modules["pyanaconda.modules"] = types.ModuleType("pyanaconda.modules")
sys.modules["pyanaconda.modules.common"] = types.ModuleType("pyanaconda.modules.common")
sys.modules["pyanaconda.modules.common.task"] = task_module

package = types.ModuleType("org_zz_fedora")
package.__path__ = []
constants = types.ModuleType("org_zz_fedora.constants")
constants.DEFAULT_DESKTOP_APP_PROFILE = "full"
constants.DESKTOP_APP_PROFILES = ("full", "minimal")
constants.SELECTION_FILE = str(root / "run/zz-fedora/install-selected")
sys.modules["org_zz_fedora"] = package
sys.modules["org_zz_fedora.constants"] = constants

path = repo / "iso/anaconda-addon/org_zz_fedora/service/installation.py"
spec = importlib.util.spec_from_file_location("zz_fedora_installation_test", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

task = module.ZZFedoraInstallationTask(root)
assert module.SOURCE_REPO_DIR == Path("/run/zz-fedora/repository")
user = task._find_target_user()
assert user["name"] == "zztest"
assert task._target_path("etc/passwd") == root / "etc/passwd"
assert task._progress_detail_from_output("Dependencies resolved.") == "Resolved package dependencies"
assert task._progress_detail_from_output("irrelevant output") == ""
assert task._format_progress("done", "9", "9", "ZZ Fedora", "") == "ZZ Fedora complete"

selection_lines = [
    "selected=1\n",
    "desktop_app_profile=minimal\n",
    "select.desktop=boxes\n",
    "preferred_browser=firefox\n",
]
profile = task._read_desktop_app_profile(selection_lines)
assert profile == "minimal"
assert task._read_desktop_app_profile(["selected=1\n"]) == "full"
try:
    task._read_desktop_app_profile(["desktop_app_profile=invalid\n"])
except RuntimeError as error:
    assert "Unsupported desktop app profile" in str(error)
else:
    raise AssertionError("invalid desktop app profile was accepted")

selection_config = root / "home/zztest/.config/zz-fedora/selections.conf"
task._write_selection_config(
    selection_lines,
    selection_config,
    user,
    profile,
)
selection_text = selection_config.read_text()
assert "desktop_app_profile=minimal\n" in selection_text
assert "select.desktop=boxes\n" in selection_text

task._write_runner_script(
    target_repo_dir=Path("/home/zztest/zz-fedora"),
    state_dir=Path("/home/zztest/.local/state/zz-fedora"),
    cache_dir=Path("/home/zztest/.cache/zz-fedora"),
    config_dir=Path("/home/zztest/.config/zz-fedora"),
    log_dir=Path("/home/zztest/.local/state/zz-fedora/logs"),
    progress_file=Path(
        "/home/zztest/.local/state/zz-fedora/logs/install-progress.tsv"
    ),
    target_user="zztest",
    desktop_app_profile=profile,
)
runner_text = (root / module.RUN_SCRIPT_PATH).read_text()
assert "export DESKTOP_APP_PROFILE=minimal\n" in runner_text
assert '--desktop-app-profile "$DESKTOP_APP_PROFILE"' in runner_text
PY

  [ "$status" -eq 0 ]
}

@test "Fedora Anaconda add-on exposes always-enabled GUI and TUI selection spokes" {
  addon="$ROOT_DIR/iso/anaconda-addon/org_zz_fedora"

  assert_file_contains "$addon/constants.py" "ZZ_FEDORA_NAMESPACE"
  assert_file_contains "$addon/constants.py" '(*ADDONS_NAMESPACE, "ZZFedora")'
  assert_file_contains "$addon/constants.py" 'SELECTION_FILE = "/run/zz-fedora/install-selected"'
  assert_file_contains "$addon/constants.py" 'DEFAULT_DESKTOP_APP_PROFILE = "full"'
  assert_file_contains "$addon/constants.py" '"minimal"'
  assert_file_contains "$addon/constants.py" '"browsers"'
  assert_file_contains "$addon/service/__main__.py" "org_zz_fedora.service.zz_fedora"
  assert_file_contains "$addon/service/zz_fedora.py" "def install_with_tasks"
  assert_file_contains "$addon/service/zz_fedora.py" "ZZFedoraInstallationTask"
  assert_file_contains "$addon/service/installation.py" "self.report_progress(message)"
  assert_file_contains "$addon/service/installation.py" "_report_process_line"
  assert_file_contains "$addon/service/installation.py" "DNF_TRANSACTION_RE"
  assert_file_contains "$addon/service/installation.py" "chroot"
  assert_file_contains "$addon/service/installation.py" "ZZ_INSTALL_PROGRESS_FILE"
  assert_file_contains "$addon/service/installation.py" 'SOURCE_REPO_DIR = Path("/run/zz-fedora/repository")'
  assert_file_contains "$ROOT_DIR/iso/anaconda-addon-data/org.fedoraproject.Anaconda.Addons.ZZFedora.service" "start-module org_zz_fedora.service"
  assert_file_contains "$ROOT_DIR/iso/anaconda-addon-data/org.fedoraproject.Anaconda.Addons.ZZFedora.conf" "org.fedoraproject.Anaconda.Addons.ZZFedora"
  assert_file_contains "$addon/selection.py" "def read_categories"
  assert_file_contains "$addon/selection.py" "def _category_ids"
  assert_file_contains "$addon/selection.py" 'REMOTE_RUNTIME_CHOICES_DIR = Path("/run/zz-fedora/repository/choices")'
  assert_file_contains "$addon/selection.py" "def default_selections"
  assert_file_contains "$addon/selection.py" "desktop_app_profile == \"minimal\""
  assert_file_contains "$addon/selection.py" 'parents[3] / "choices"'
  assert_file_contains "$addon/selection.py" 'root / ("%s.conf" % category_id)'
  assert_file_contains "$addon/selection.py" "select.%s=%s"
  assert_file_contains "$addon/runtime.py" "def refresh_runtime"
  assert_file_contains "$addon/runtime.py" "def payload_proxy_url"
  assert_file_contains "$addon/runtime.py" "THREAD_RUNTIME_REFRESH"
  assert_file_contains "$addon/gui/spokes/zz_fedora.py" "class ZZFedoraSpoke"
  assert_file_contains "$addon/gui/spokes/zz_fedora.py" 'builderObjects = ["zzFedoraSpokeWindow"]'
  assert_file_contains "$addon/gui/spokes/zz_fedora.py" "NormalSpoke"
  assert_file_contains "$addon/gui/spokes/zz_fedora.py" "from pyanaconda.ui.categories.software import SoftwareCategory"
  assert_file_contains "$addon/gui/spokes/zz_fedora.py" "category = SoftwareCategory"
  refute_file_contains "$addon/gui/spokes/zz_fedora.py" "ZZFedoraCategory"
  assert_file_contains "$addon/gui/spokes/zz_fedora.py" "_build_category_rows"
  assert_file_contains "$addon/gui/spokes/zz_fedora.py" "_render_choices"
  assert_file_contains "$addon/gui/spokes/zz_fedora.py" "_update_preferred_browser_combo"
  assert_file_contains "$addon/gui/spokes/zz_fedora.py" "_on_profile_changed"
  assert_file_contains "$addon/gui/spokes/zz_fedora.py" "write_state("
  assert_file_contains "$addon/gui/spokes/zz_fedora.py" "thread_manager.wait(THREAD_PAYLOAD)"
  assert_file_contains "$addon/gui/spokes/zz_fedora.py" "payload_proxy_url(self.payload)"
  assert_file_contains "$addon/gui/spokes/zz_fedora.py" "target=self._retry_runtime"
  assert_file_contains "$addon/gui/spokes/zz_fedora.py" "gtk_call_once(self._finish_runtime_retry)"
  assert_file_contains "$addon/gui/spokes/zz_fedora.glade" "Optional categories"
  assert_file_contains "$addon/gui/spokes/zz_fedora.glade" 'id="zzFedoraSpokeWindow"'
  assert_file_contains "$addon/gui/spokes/zz_fedora.glade" "categoryListBox"
  assert_file_contains "$addon/gui/spokes/zz_fedora.glade" "choiceListBox"
  assert_file_contains "$addon/gui/spokes/zz_fedora.glade" "desktopAppProfileCombo"
  refute_file_contains "$addon/gui/spokes/zz_fedora.glade" "Install ZZ Fedora managed desktop"
  assert_file_contains "$ROOT_DIR/iso/scripts/build-fedora-installer-iso.sh" "org_zz_fedora/choices"
  assert_file_contains "$ROOT_DIR/iso/scripts/build-fedora-installer-iso.sh" "conf.d/100-zz-fedora.conf"
  assert_file_contains "$ROOT_DIR/iso/anaconda-addon-data/conf.d/100-zz-fedora.conf" "hidden_spokes ="
  assert_file_contains "$ROOT_DIR/iso/anaconda-addon-data/conf.d/100-zz-fedora.conf" "SoftwareSelectionSpoke"
  assert_file_contains "$addon/tui/spokes/zz_fedora.py" "NormalTUISpoke"
  assert_file_contains "$addon/tui/spokes/zz_fedora.py" "from pyanaconda.ui.categories.software import SoftwareCategory"
  assert_file_contains "$addon/tui/spokes/zz_fedora.py" "category = SoftwareCategory"
  refute_file_contains "$addon/tui/spokes/zz_fedora.py" "ZZFedoraCategory"
  assert_file_contains "$addon/tui/spokes/zz_fedora.py" "CheckboxWidget"
  assert_file_contains "$addon/tui/spokes/zz_fedora.py" "_toggle_choice"
  assert_file_contains "$addon/tui/spokes/zz_fedora.py" "_toggle_desktop_app_profile"
  assert_file_contains "$addon/tui/spokes/zz_fedora.py" "write_state("
  assert_file_contains "$addon/tui/spokes/zz_fedora.py" "thread_manager.wait(THREAD_PAYLOAD)"
  assert_file_contains "$addon/tui/spokes/zz_fedora.py" "payload_proxy_url(self.payload)"
  assert_file_contains "$addon/tui/spokes/zz_fedora.py" "target=self._retry_runtime"
  refute_file_contains "$addon/tui/spokes/zz_fedora.py" "_toggle_selection"
}

@test "Fedora Anaconda add-on reads flattened choice catalogs" {
  run env ZZ_REPO_ROOT="$ROOT_DIR" python3 - <<'PY'
import importlib.util
import os
import sys
import types
from pathlib import Path

repo_root = Path(os.environ["ZZ_REPO_ROOT"])
package = types.ModuleType("org_zz_fedora")
package.__path__ = []
constants = types.ModuleType("org_zz_fedora.constants")
constants.CATEGORY_ORDER = (
    "browsers",
    "desktop",
    "ai",
    "dev",
    "dotnet",
    "office",
    "gaming",
    "media",
)
constants.DEFAULT_DESKTOP_APP_PROFILE = "full"
constants.DESKTOP_APP_PROFILES = ("full", "minimal")
constants.SELECTION_FILE = "/tmp/zz-fedora-test-selection"
sys.modules["org_zz_fedora"] = package
sys.modules["org_zz_fedora.constants"] = constants

selection_file = repo_root / "iso/anaconda-addon/org_zz_fedora/selection.py"
spec = importlib.util.spec_from_file_location("zz_fedora_selection", selection_file)
selection = importlib.util.module_from_spec(spec)
spec.loader.exec_module(selection)

assert selection.SOURCE_TREE_CHOICES_DIR == repo_root / "choices"
categories = selection.read_categories()
category_by_id = {category.id: category for category in categories}
assert [category.id for category in categories] == list(constants.CATEGORY_ORDER)
assert any(choice.id == "firefox" for choice in category_by_id["browsers"].choices)
assert category_by_id["desktop"].label == "Desktop apps"
assert [choice.id for choice in category_by_id["desktop"].choices] == [
    "calculator",
    "characters",
    "text-editor",
    "disks",
    "logs",
    "disk-usage-analyzer",
    "image-viewer",
    "document-viewer",
    "video-player",
    "audio-player",
    "camera",
    "document-scanner",
    "file-roller",
    "software",
    "system-monitor",
    "boxes",
    "connections",
]
assert any(choice.id == "docker" for choice in category_by_id["dev"].choices)
PY

  [ "$status" -eq 0 ]
}
