#!/usr/bin/env bats

load "helpers/common"

setup() {
  setup_test_env
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
    "ai",
    "dev",
    "dotnet",
    "office",
    "gaming",
    "media",
)
constants.SELECTION_FILE = str(state)
sys.modules["org_zz_fedora"] = package
sys.modules["org_zz_fedora.constants"] = constants

path = repo / "iso/anaconda-addon/org_zz_fedora/selection.py"
spec = importlib.util.spec_from_file_location("zz_fedora_selection_test", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
module.SOURCE_TREE_CHOICES_DIR = repo / "choices"
module.PACKAGE_CHOICES_DIR = repo / "choices"

categories = module.read_categories()
defaults = module.default_selections(categories)
assert defaults["browsers"] == ["firefox"]
for category in categories:
    if category.id != "browsers":
        assert defaults[category.id] == [choice.id for choice in category.choices]

module.write_state(
    True,
    {"browsers": ["firefox", "not-valid"], "dev": ["docker"]},
    "not-valid",
)
assert stat.S_IMODE(state.stat().st_mode) == 0o600
text = state.read_text()
assert "select.browsers=firefox" in text
assert "select.dev=docker" in text
assert "not-valid" not in text
enabled, selections, preferred = module.read_state(categories)
assert enabled
assert selections["browsers"] == ["firefox"]
assert selections["dev"] == ["docker"]
assert preferred == ""
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
constants.SELECTION_FILE = str(root / "run/zz-fedora/install-selected")
sys.modules["org_zz_fedora"] = package
sys.modules["org_zz_fedora.constants"] = constants

path = repo / "iso/anaconda-addon/org_zz_fedora/service/installation.py"
spec = importlib.util.spec_from_file_location("zz_fedora_installation_test", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

task = module.ZZFedoraInstallationTask(root)
assert task._find_target_user()["name"] == "zztest"
assert task._target_path("etc/passwd") == root / "etc/passwd"
assert task._progress_detail_from_output("Dependencies resolved.") == "Resolved package dependencies"
assert task._progress_detail_from_output("irrelevant output") == ""
assert task._format_progress("done", "9", "9", "ZZ Fedora", "") == "ZZ Fedora complete"
PY

  [ "$status" -eq 0 ]
}
