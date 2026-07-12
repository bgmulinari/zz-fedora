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
loader = root / "iso-runtime.sh"
loader.write_text(
    "#!/usr/bin/env bash\n"
    "set -Eeuo pipefail\n"
    "printf '%s\\n' \"${https_proxy:-}\" >\"$ZZ_TEST_PROXY_LOG\"\n"
    "mkdir -p \"$ZZ_TEST_RUNTIME_DIR/choices\"\n"
    "printf '#!/usr/bin/env bash\\n' >\"$ZZ_TEST_RUNTIME_DIR/install.sh\"\n"
    "chmod +x \"$ZZ_TEST_RUNTIME_DIR/install.sh\"\n"
    "printf 'firefox\\tFirefox\\t1\\tbrowser-firefox\\tFirefox\\n' "
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
constants.SELECTION_FILE = str(root / "run/zz-fedora/install-selected")
sys.modules["org_zz_fedora"] = package
sys.modules["org_zz_fedora.constants"] = constants

path = repo / "iso/anaconda-addon/org_zz_fedora/service/installation.py"
spec = importlib.util.spec_from_file_location("zz_fedora_installation_test", path)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

task = module.ZZFedoraInstallationTask(root)
assert module.SOURCE_REPO_DIR == Path("/run/zz-fedora/repository")
assert task._find_target_user()["name"] == "zztest"
assert task._target_path("etc/passwd") == root / "etc/passwd"
assert task._progress_detail_from_output("Dependencies resolved.") == "Resolved package dependencies"
assert task._progress_detail_from_output("irrelevant output") == ""
assert task._format_progress("done", "9", "9", "ZZ Fedora", "") == "ZZ Fedora complete"
PY

  [ "$status" -eq 0 ]
}
