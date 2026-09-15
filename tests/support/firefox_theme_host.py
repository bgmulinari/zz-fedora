"""Exercise startup initialization without installing Pywalfox in the test runner."""

from pathlib import Path
import runpy
import sys
from types import ModuleType
from unittest.mock import Mock, patch


host = Path(__file__).resolve().parents[2] / "dotfiles/browser-theme/firefox-theme-host"
modules = {name: ModuleType(name) for name in (
    "pywalfox", "pywalfox.config", "pywalfox.fetcher",
    "pywalfox.messenger", "pywalfox.response",
)}
modules["pywalfox.config"].ACTIONS = {"COLORS": "action:colors"}
fetch = modules["pywalfox.fetcher"].get_pywal_colors = Mock()
messenger = modules["pywalfox.messenger"].Messenger = Mock()
modules["pywalfox.response"].Message = lambda action, **data: {"action": action, **data}

with patch.dict(sys.modules, modules):
    main = runpy.run_path(str(host))["main"]

palette = {"colors": ["#123456"] * 16, "wallpaper": "test"}
for success in (True, False):
    fetch.return_value = success, palette if success else None, None
    messenger.reset_mock()
    with patch.object(sys, "argv", [str(host), "manifest.json", "pywalfox@frewacom.org"]), \
            patch("os.execv") as execute:
        main()
        execute.assert_called_once_with(sys.executable, [
            sys.executable, "-m", "pywalfox", "manifest.json", "pywalfox@frewacom.org",
        ])
    if success:
        messenger.return_value.send_message.assert_called_once_with({
            "action": "action:colors", "data": palette,
        })
    else:
        messenger.assert_not_called()
