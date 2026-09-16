"""Offline tests of the registry request used by the first-login action."""
import contextlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch, MagicMock

spec = importlib.util.spec_from_file_location('registry', Path(sys.argv.pop(1)) / 'lib/dms_registry_theme.py')
registry = importlib.util.module_from_spec(spec)
spec.loader.exec_module(registry)


class RegistryThemeTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.config = self.home / '.config/DankMaterialShell'
        self.config.mkdir(parents=True)
        self.theme = self.config / 'themes/catppuccin/theme.json'
        self.settings = self.config / 'settings.json'
        self.settings.write_text(json.dumps({'currentThemeName': 'custom', 'customThemeFile': str(self.theme)}))

    def downloaded(self, *args):
        self.theme.parent.mkdir(parents=True, exist_ok=True)
        self.theme.write_text('{"id":"catppuccin"}')

    def test_install_and_repeat(self):
        with patch.object(registry, 'backend_socket', return_value='/test.sock'), \
                patch.object(registry, 'install_theme', side_effect=self.downloaded) as install, \
                contextlib.redirect_stdout(io.StringIO()) as output:
            registry.install_default(self.home)
            registry.install_default(self.home)
            install.assert_called_once_with('/test.sock', 'catppuccin')
            self.assertEqual(output.getvalue(), 'installed\n')

    def test_user_selection(self):
        self.settings.write_text('{"currentThemeName":"dynamic"}')
        with patch.object(registry, 'install_theme') as install:
            registry.install_default(self.home)
            install.assert_not_called()

    def test_failed_download_retries(self):
        with patch.object(registry, 'backend_socket', return_value='/test.sock'), \
                patch.object(registry, 'install_theme', side_effect=RuntimeError('offline')):
            with self.assertRaisesRegex(RuntimeError, 'offline'):
                registry.install_default(self.home)
        self.assertFalse(self.theme.exists())
        with patch.object(registry, 'backend_socket', return_value='/test.sock'), \
                patch.object(registry, 'install_theme', side_effect=self.downloaded), \
                contextlib.redirect_stdout(io.StringIO()):
            registry.install_default(self.home)
        self.assertTrue(self.theme.is_file())

    def test_verifies_backend_output(self):
        with patch.object(registry, 'backend_socket', return_value='/test.sock'), \
                patch.object(registry, 'install_theme'):
            with self.assertRaisesRegex(RuntimeError, 'valid Catppuccin'):
                registry.install_default(self.home)

    def test_request_protocol_and_error(self):
        for response, error in [({'id': 1, 'result': {}}, None),
                                ({'id': 1, 'error': 'download failed'}, 'download failed')]:
            client = MagicMock()
            client.makefile.return_value.__enter__.return_value = io.StringIO(json.dumps(response)+'\n')
            with patch.object(registry.socket, 'socket') as factory:
                factory.return_value.__enter__.return_value = client
                if error:
                    with self.assertRaisesRegex(RuntimeError, error):
                        registry.install_theme('/test.sock', 'catppuccin')
                else:
                    registry.install_theme('/test.sock', 'catppuccin')
            request = json.loads(client.sendall.call_args.args[0])
            self.assertEqual(request, {'id': 1, 'method': 'themes.install', 'params': {'name': 'catppuccin'}})


unittest.main()
