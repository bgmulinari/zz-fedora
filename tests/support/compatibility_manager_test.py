"""Exercise Proton operations using disposable Steam libraries and fake executables."""
import contextlib
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

PLUGIN = Path(__file__).resolve().parents[2] / 'dotfiles/dms/.config/DankMaterialShell/plugins/CompatibilityManager'
sys.path.insert(0, str(PLUGIN / 'scripts'))
spec = importlib.util.spec_from_file_location('manager', PLUGIN / 'scripts/manager.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)


class ManagerTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.home = Path(self.temp.name)
        self.root = self.home / '.local/share/Steam'
        self.root.mkdir(parents=True)
        self.environment = patch.dict(os.environ, {'HOME': str(self.home), 'XDG_DATA_HOME': str(self.home / '.local/share'), 'XDG_CONFIG_HOME': str(self.home / '.config'), 'XDG_CACHE_HOME': str(self.home / '.cache'), 'STEAM_EXTRA_COMPAT_TOOLS_PATHS': ''})
        self.environment.start()
        self.addCleanup(self.environment.stop)
        self.gh_auth = patch.object(m.github_cli, 'authenticated', return_value=False)
        self.gh_auth.start()
        self.addCleanup(self.gh_auth.stop)
        self.first = self.tool('GE build with spaces')
        self.second = self.tool('Other build')

    def tool(self, name, runtime='1628350', parent=None):
        path = (parent or self.root / 'compatibilitytools.d') / name
        path.mkdir(parents=True)
        (path / 'proton').write_text('#!/usr/bin/python3\nimport json, os, sys\nprint(json.dumps({"args": sys.argv[1:], "target": os.environ.get("PROTON_MANAGER_TARGET"), "paths": os.environ.get("STEAM_COMPAT_TOOL_PATHS")}))\n')
        (path / 'proton').chmod(0o755)
        (path / 'toolmanifest.vdf').write_text('"manifest" { "commandline" "/proton %verb%" "require_tool_appid" "' + runtime + '" }')
        (path / 'compatibilitytool.vdf').write_text('"compatibilitytools" { "compat_tools" { "test" { "display_name" "' + name + '" } } }')
        return path

    def select(self, tool=None, scope='default', game=''):
        with m.locked(self.root):
            return m.select(self.root, str(tool or self.first), scope, game)

    def launch(self, **values):
        env = {k: v for k, v in os.environ.items() if k not in ('SteamGameId', 'SteamAppId', 'STEAM_COMPAT_APP_ID')}
        env.update(values)
        return subprocess.run(['/usr/bin/python3', str(self.root / 'compatibilitytools.d' / m.SLOT / 'proton'), 'waitforexitandrun', 'a b', '$(literal)'], env=env, text=True, capture_output=True)

    def test_root_aliases_and_flatpak_are_separate(self):
        (self.home / '.steam').mkdir()
        (self.home / '.steam/root').symlink_to(self.root)
        flatpak = self.home / '.var/app/com.valvesoftware.Steam/data/Steam'
        flatpak.mkdir(parents=True)
        self.assertEqual(m.steam_roots(self.home), [self.root, flatpak])

    def test_secondary_library_games_official_tools_and_manual_overrides(self):
        library = self.home / 'More Games'
        apps = library / 'steamapps'
        apps.mkdir(parents=True)
        (self.root / 'steamapps').mkdir()
        (self.root / 'steamapps/libraryfolders.vdf').write_text('"libraryfolders" { "1" { "path" "' + str(library) + '" } }')
        (apps / 'appmanifest_42.acf').write_text('"AppState" { "appid" "42" "name" "A \\"quoted\\" game" "installdir" "Game" }'.replace('\\\\"', '\\"'))
        official = self.tool('Proton Official', parent=apps / 'common')
        (apps / 'appmanifest_99.acf').write_text('"AppState" { "appid" "99" "name" "Proton Official" "installdir" "Proton Official" }')
        self.select()
        self.select(self.second, 'game', '123')
        data = m.inventory(self.root)
        self.assertEqual({g['id'] for g in data['games']}, {'42', '123'})
        self.assertTrue(next(t for t in data['tools'] if t['path'] == str(official))['official'])
        self.assertNotIn(m.SLOT, [Path(t['path']).name for t in data['tools']])

    def test_first_registration_and_switch_keep_steam_metadata_stable(self):
        self.assertIn('Restart Steam once', self.select())
        slot = self.root / 'compatibilitytools.d' / m.SLOT
        metadata = {p.name: p.read_bytes() for p in slot.iterdir() if p.name != 'selection.json'}
        self.select(self.second)
        self.assertEqual(metadata, {p.name: p.read_bytes() for p in slot.iterdir() if p.name != 'selection.json'})
        self.assertEqual(m.read_selection(self.root)['default'], str(self.second))
        self.assertTrue(self.first.exists())

    def test_dispatch_preserves_arguments_and_runtime_tail(self):
        self.select()
        self.select(self.second, 'game', '42')
        result = self.launch(SteamGameId='42', STEAM_COMPAT_TOOL_PATHS='/selector:/runtime:/extra')
        self.assertEqual(result.returncode, 0, result.stderr)
        data = json.loads(result.stdout)
        self.assertEqual(data['target'], str(self.second))
        self.assertEqual(data['paths'], str(self.second) + ':/runtime:/extra')
        self.assertEqual(data['args'], ['waitforexitandrun', 'a b', '$(literal)'])
        self.assertEqual(json.loads(self.launch(SteamGameId='777').stdout)['target'], str(self.first))

    def test_missing_build_fails_and_clear_game_override_uses_active(self):
        self.select()
        self.select(self.second, 'game', '42')
        (self.second / 'proton').unlink()
        result = self.launch(SteamGameId='42')
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('missing or incompatible', result.stderr)
        m.select(self.root, '', 'game', '42')
        self.assertEqual(json.loads(self.launch(SteamGameId='42').stdout)['target'], str(self.first))
        (self.first / 'proton').unlink()
        result = self.launch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('choose an installed build', result.stderr)

    def test_different_runtime_and_invalid_game_leave_selection_unchanged(self):
        self.select()
        old = m.read_selection(self.root)
        other = self.tool('Old runtime', '1391110')
        for tool, scope, game in [(other, 'default', ''), (self.second, 'game', '../42')]:
            with self.assertRaises(m.ManagerError):
                self.select(tool, scope, game)
            self.assertEqual(m.read_selection(self.root), old)

    def test_runtime_changed_by_steam_fails_clearly(self):
        self.select()
        (self.first / 'toolmanifest.vdf').write_text('"manifest" { "require_tool_appid" "999" }')
        result = self.launch()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('missing or incompatible', result.stderr)

    def test_unknown_slot_is_not_overwritten(self):
        slot = self.root / 'compatibilitytools.d' / m.SLOT
        slot.mkdir()
        (slot / 'personal-file').write_text('keep')
        with self.assertRaises(m.ManagerError):
            self.select()
        self.assertEqual((slot / 'personal-file').read_text(), 'keep')

    def test_concurrent_writer_is_rejected(self):
        with m.locked(self.root):
            with self.assertRaisesRegex(m.ManagerError, 'Another Proton'):
                with m.locked(self.root):
                    pass

    def test_removal_requires_ownership_and_checks_selection_and_steam(self):
        with self.assertRaises(m.ManagerError):
            m.remove(self.root, str(self.first))
        (self.first / '.proton-manager-install.json').write_text(json.dumps({'owner': m.OWNER}))
        with patch.object(m, 'steam_running', return_value=True):
            with self.assertRaisesRegex(m.ManagerError, 'Close Steam'):
                m.remove(self.root, str(self.first))
        self.select()
        with self.assertRaisesRegex(m.ManagerError, 'Set another build as active'):
            m.remove(self.root, str(self.first))
        self.select(self.second)
        with patch.object(m, 'steam_running', return_value=False):
            m.remove(self.root, str(self.first))
        self.assertFalse(self.first.exists())

    def test_broken_selectors_preserve_inventory_and_protect_relevant_builds(self):
        self.select()
        slot = self.root / 'compatibilitytools.d' / m.SLOT
        selection = slot / 'selection.json'
        (self.first / '.proton-manager-install.json').write_text(json.dumps({'owner': m.OWNER}))
        apps = self.root / 'steamapps'
        apps.mkdir(exist_ok=True)
        (apps / 'appmanifest_42.acf').write_text('"AppState" { "appid" "42" "name" "Test game" "installdir" "Test" }')
        for state in ('corrupt', 'missing', 'unowned'):
            with self.subTest(state=state):
                if state == 'corrupt':
                    selection.write_text('{broken')
                elif state == 'missing':
                    selection.unlink()
                else:
                    (slot / '.owner').write_text('someone else')
                data = m.inventory(self.root)
                self.assertIn(str(self.first), [tool['path'] for tool in data['tools']])
                self.assertIn('42', [game['id'] for game in data['games']])
                self.assertIsNone(data['selection'])
                self.assertTrue(any('Selector at' in warning for warning in data['warnings']))
                with self.assertRaisesRegex(m.ManagerError, 'Cannot verify whether this build is selected'):
                    m.remove(self.root, str(self.first))
                self.assertTrue(self.first.exists())

    def test_broken_selector_does_not_block_an_unrelated_launcher(self):
        self.select()
        (self.root / 'compatibilitytools.d' / m.SLOT / 'selection.json').write_text('{broken')
        directory = self.home / '.config/heroic/tools/proton'
        build = self.tool('Heroic build', parent=directory)
        (build / '.proton-manager-install.json').write_text(json.dumps({'owner': m.OWNER}))
        target = dict(directory=str(directory), launcher='heroic', config=str(directory.parent.parent))
        with patch.object(m, 'steam_running', return_value=False), patch.object(m, 'launcher_running', return_value=False):
            # Steam can also see external builds explicitly registered in its search path.
            with patch.dict(os.environ, {'STEAM_EXTRA_COMPAT_TOOLS_PATHS': str(directory)}):
                with self.assertRaisesRegex(m.ManagerError, 'Cannot verify whether this build is selected'):
                    m.remove(directory, str(build), target)
            m.remove(directory, str(build), target)
        self.assertFalse(build.exists())

    def archive(self, member=None):
        archive = self.home / 'fixture.tar.gz'
        with tarfile.open(archive, 'w:gz') as tar:
            if member:
                tar.addfile(member, io.BytesIO(b'x') if member.isfile() else None)
            else:
                tar.add(self.first, arcname='GE-Proton-test')
        return archive

    def test_safe_extraction_and_internal_links(self):
        (self.first / 'version').write_text('1')
        (self.first / 'version-link').symlink_to('version')
        dest = self.home / 'extract'
        dest.mkdir()
        result = m.unpack(self.archive(), dest)
        self.assertEqual((result / 'version-link').read_text(), '1')

    def test_traversal_and_external_symlinks_are_rejected(self):
        for name, kind, link in [('../escape', tarfile.REGTYPE, ''), ('/escape', tarfile.REGTYPE, ''), ('GE/x', tarfile.SYMTYPE, '/tmp/escape'), ('GE/x', tarfile.LNKTYPE, '../escape'), ('GE/dev', tarfile.CHRTYPE, '')]:
            with self.subTest(name=name, kind=kind):
                member = tarfile.TarInfo(name)
                member.type, member.linkname = kind, link
                member.size = 1 if kind == tarfile.REGTYPE else 0
                with tempfile.TemporaryDirectory(dir=self.home) as dest:
                    with self.assertRaises((m.ManagerError, tarfile.TarError)):
                        m.unpack(self.archive(member), Path(dest))

    def release(self, archive):
        name = 'GE-Proton-test-x86_64'
        return {'tag_name': 'GE-Proton-test', 'assets': [
            {'name': name + '.tar.gz', 'size': archive.stat().st_size, 'browser_download_url': m.providers.PROVIDERS['ge']['origin'] + 'releases/download/test/build.tar.gz'},
            {'name': name + '.sha512sum', 'browser_download_url': m.providers.PROVIDERS['ge']['origin'] + 'releases/download/test/build.sha512sum'}]}

    def test_architecture_release_matching(self):
        release = self.release(self.archive())
        self.assertTrue(m.providers.assets(release, 'ge', 'x86_64'))
        self.assertFalse(m.providers.assets(release, 'ge', 'aarch64'))
        release['assets'][0]['name'] = 'GE-Proton-test-aarch64.tar.gz'
        release['assets'][1]['name'] = 'GE-Proton-test-aarch64.sha512sum'
        self.assertTrue(m.providers.assets(release, 'ge', 'aarch64'))
        self.assertFalse(m.providers.assets(release, 'ge', 'x86_64'))

    def test_release_notes_preserve_github_rendered_links_and_markdown(self):
        release = self.release(self.archive())
        url = m.providers.PROVIDERS['ge']['origin'] + 'commit/' + 'abcdef01' * 5
        release['body'] = '[Launcher fix](' + url + ')'
        release['body_html'] = '<p><a href="' + url + '">Launcher fix</a></p>'
        with patch.object(m.urllib.request, 'urlopen', return_value=io.BytesIO(json.dumps([release]).encode())) as fetch:
            result = m.releases()["releases"][0]
        self.assertEqual(fetch.call_args.args[0].get_header('Accept'), 'application/vnd.github.full+json')
        self.assertEqual(result['notesHtml'], release['body_html'])
        self.assertEqual(result['notes'], release['body'])
        release['body_html'] = None
        self.assertEqual(m.providers.assets(release, 'ge', 'x86_64')[0]['notesHtml'], '')

    def test_release_pagination_counts_source_records_before_asset_filtering(self):
        # A full page may have zero compatible assets. It must not end browsing.
        records = [dict(tag_name=str(i), assets=[]) for i in range(30)]
        with patch.object(m, 'fetch_json', return_value=records) as fetch:
            result = m.releases('cachyos', 2)
        self.assertEqual(result, dict(releases=[], page=2, hasMore=True))
        self.assertIn('page=2', fetch.call_args.args[0])
        with patch.object(m, 'fetch_json', return_value=records[:2]):
            self.assertFalse(m.releases('cachyos', 3)['hasMore'])
        with patch.object(m, 'fetch_json', return_value=[]):
            self.assertFalse(m.releases('cachyos', 4)['hasMore'])
        with patch.object(m, 'fetch_json', return_value=records):
            self.assertFalse(m.releases('cachyos', 100)['hasMore'])

    def test_release_cache_reuses_pages_and_install_metadata(self):
        url = m.providers.PROVIDERS['ge']['api'] + '?per_page=30&page=1'
        payload = [dict(tag_name='test/tag', assets=[])]
        with patch.object(m, 'request', return_value=io.BytesIO(json.dumps(payload).encode())) as network:
            self.assertEqual(m.fetch_json(url), payload)
            self.assertEqual(m.fetch_json(url), payload)
            self.assertEqual(m.fetch_json(m.providers.PROVIDERS['ge']['api'] + '/tags/test%2Ftag'), payload[0])
        self.assertEqual(network.call_count, 1)
        self.assertTrue(m.FETCH_STATUS['cached'])

    def test_expired_cache_revalidates_with_etag(self):
        url = m.providers.PROVIDERS['ge']['api'] + '?per_page=30&page=1'
        response = io.BytesIO(b'[]')
        response.headers = {'ETag': '"release-version"'}
        with patch.object(m.release_cache.time, 'time', return_value=1000), patch.object(m, 'request', return_value=response):
            m.fetch_json(url)
        error = m.urllib.error.HTTPError(url, 304, 'Not Modified', {}, io.BytesIO())
        with patch.object(m.release_cache.time, 'time', return_value=5000), patch.object(m, 'request', side_effect=error) as network:
            self.assertEqual(m.fetch_json(url), [])
        self.assertEqual(network.call_args.kwargs['headers']['If-None-Match'], '"release-version"')
        self.assertFalse(m.FETCH_STATUS['stale'])
        with patch.object(m.release_cache.time, 'time', return_value=5010), patch.object(m, 'request') as network:
            self.assertEqual(m.fetch_json(url), [])
            network.assert_not_called()

    def test_rate_limit_preserves_stale_cache_and_blocks_other_sources(self):
        url = m.providers.PROVIDERS['ge']['api'] + '?per_page=30&page=1'
        with patch.object(m.release_cache.time, 'time', return_value=1000), patch.object(m, 'request', return_value=io.BytesIO(b'[]')):
            m.fetch_json(url)
        error = m.urllib.error.HTTPError(url, 403, 'Forbidden', {'X-RateLimit-Remaining': '0', 'X-RateLimit-Reset': '9000'}, io.BytesIO(b'{"message":"API rate limit exceeded"}'))
        with patch.object(m.release_cache.time, 'time', return_value=5000), patch.object(m, 'request', side_effect=error):
            self.assertEqual(m.fetch_json(url), [])
            self.assertTrue(m.FETCH_STATUS['stale'])
            self.assertGreaterEqual(m.FETCH_STATUS['retryAt'], 9000)
        with patch.object(m.release_cache.time, 'time', return_value=5010), patch.object(m, 'request') as network:
            self.assertEqual(m.fetch_json(url), [])
            with self.assertRaises(m.release_cache.RateLimited):
                m.fetch_json(m.providers.PROVIDERS['cachyos']['api'] + '?per_page=30&page=1')
            network.assert_not_called()
        with patch.object(m.release_cache.time, 'time', return_value=9002), patch.object(m, 'request', return_value=io.BytesIO(b'[]')) as network:
            self.assertEqual(m.fetch_json(url), [])
            self.assertEqual(network.call_count, 1)

    def test_secondary_limit_honors_retry_after_without_cached_page(self):
        url = m.providers.PROVIDERS['ge']['api'] + '?per_page=30&page=1'
        error = m.urllib.error.HTTPError(url, 429, 'Too Many Requests', {'Retry-After': '120'}, io.BytesIO())
        with patch.object(m.release_cache.time, 'time', return_value=1000), patch.object(m, 'request', side_effect=error):
            with self.assertRaises(m.release_cache.RateLimited) as caught:
                m.fetch_json(url)
        self.assertGreaterEqual(caught.exception.retry_at, 1120)
        with patch.object(m.release_cache.time, 'time', return_value=1010), patch.object(m, 'request') as network:
            with self.assertRaises(m.release_cache.RateLimited):
                m.fetch_json(url)
            network.assert_not_called()

    def test_offline_cache_fallback_and_non_rate_limit_errors(self):
        url = m.providers.PROVIDERS['ge']['api'] + '?per_page=30&page=1'
        with patch.object(m.release_cache.time, 'time', return_value=1000), patch.object(m, 'request', return_value=io.BytesIO(b'[]')):
            m.fetch_json(url)
        with patch.object(m.release_cache.time, 'time', return_value=5000), patch.object(m, 'request', side_effect=m.urllib.error.URLError('offline')):
            self.assertEqual(m.fetch_json(url), [])
            self.assertTrue(m.FETCH_STATUS['stale'])
        error = m.urllib.error.HTTPError(url, 403, 'Forbidden', {}, io.BytesIO(b'Access denied'))
        with patch.object(m.release_cache.time, 'time', return_value=5000), patch.object(m, 'request', side_effect=error):
            with self.assertRaises(m.urllib.error.HTTPError):
                m.fetch_json(url)

    def test_authenticated_cli_is_preferred_and_cache_skips_auth_probe(self):
        url = m.providers.PROVIDERS['ge']['api'] + '?per_page=30&page=1'
        with patch.object(m.github_cli, 'authenticated', return_value=True) as auth, patch.object(m.github_cli, 'request', return_value=io.BytesIO(b'[]')) as cli, patch.object(m, 'request') as direct:
            self.assertEqual(m.fetch_json(url), [])
            self.assertEqual(m.fetch_json(url), [])
            self.assertEqual(auth.call_count, 1)
            self.assertEqual(cli.call_count, 1)
            direct.assert_not_called()

    def test_cli_auth_failure_falls_back_to_direct_fetch(self):
        url = m.providers.PROVIDERS['ge']['api'] + '?per_page=30&page=1'
        with patch.object(m.github_cli, 'authenticated', return_value=True), patch.object(m.github_cli, 'request', side_effect=m.github_cli.Unavailable('signed out')), patch.object(m, 'request', return_value=io.BytesIO(b'[]')) as direct:
            self.assertEqual(m.fetch_json(url), [])
            direct.assert_called_once()

    def test_cli_cooldown_does_not_switch_to_anonymous_requests(self):
        url = m.providers.PROVIDERS['ge']['api'] + '?per_page=30&page=1'
        error = m.urllib.error.HTTPError(url, 429, 'Rate limited', {'Retry-After': '120'}, io.BytesIO())
        with patch.object(m.github_cli, 'authenticated', return_value=True), patch.object(m.github_cli, 'request', side_effect=error) as cli, patch.object(m, 'request') as direct:
            with self.assertRaises(m.release_cache.RateLimited):
                m.fetch_json(url)
            with self.assertRaises(m.release_cache.RateLimited):
                m.fetch_json(url)
            self.assertEqual(cli.call_count, 1)
            direct.assert_not_called()

    def test_anonymous_cooldown_does_not_block_authenticated_cli(self):
        url = m.providers.PROVIDERS['ge']['api'] + '?per_page=30&page=1'
        m.release_cache.write(m.release_cache.cooldown_path('api.github.com'), dict(until=m.release_cache.time.time() + 3600))
        with patch.object(m.github_cli, 'authenticated', return_value=True), patch.object(m.github_cli, 'request', return_value=io.BytesIO(b'[]')) as cli:
            self.assertEqual(m.fetch_json(url), [])
            cli.assert_called_once()

    def test_cli_parses_http_headers_and_preserves_rate_limits(self):
        gh = m.github_cli
        success = subprocess.CompletedProcess([], 0, b'HTTP/2.0 200 OK\r\nETag: "one"\r\n\r\n[]', b'')
        with patch.object(gh.shutil, 'which', return_value='/usr/bin/gh'), patch.object(gh.subprocess, 'run', return_value=success) as run:
            with gh.request(m.providers.PROVIDERS['ge']['api'], {'If-None-Match': '"one"'}) as response:
                self.assertEqual(response.read(), b'[]')
                self.assertEqual(response.headers['ETag'], '"one"')
            command = run.call_args.args[0]
            self.assertIn('--include', command)
            self.assertIn('GET', command)
            self.assertIn('If-None-Match: "one"', command)
            self.assertNotIn('token', command)
        limited = subprocess.CompletedProcess([], 1, b'HTTP/2.0 403 Forbidden\nX-RateLimit-Remaining: 0\nX-RateLimit-Reset: 9000\n\n{"message":"API rate limit exceeded"}', b'')
        with patch.object(gh.shutil, 'which', return_value='/usr/bin/gh'), patch.object(gh.subprocess, 'run', return_value=limited):
            with self.assertRaises(m.urllib.error.HTTPError) as caught:
                gh.request(m.providers.PROVIDERS['ge']['api'])
            self.assertEqual(caught.exception.headers['X-RateLimit-Remaining'], '0')

    def test_cli_authentication_probe_is_cached_and_optional(self):
        self.gh_auth.stop()
        gh = m.github_cli
        with patch.object(gh.shutil, 'which', return_value=None), patch.object(gh.subprocess, 'run') as run:
            self.assertFalse(gh.authenticated())
            run.assert_not_called()
        with patch.object(gh.shutil, 'which', return_value='/usr/bin/gh'), patch.object(gh.subprocess, 'run', return_value=subprocess.CompletedProcess([], 0)) as run:
            self.assertTrue(gh.authenticated())
            self.assertTrue(gh.authenticated())
            self.assertEqual(run.call_count, 1)

    def test_launcher_targets_are_separate_and_support_the_right_sources(self):
        config = self.home / '.config'
        data = self.home / '.local/share'
        for path in (config / 'heroic', data / 'lutris', data / 'bottles', data / 'winezgui',
                     self.home / '.var/app/com.heroicgameslauncher.hgl/config/heroic'):
            path.mkdir(parents=True)
        with patch.dict(os.environ, {'XDG_CONFIG_HOME': str(config)}):
            found = m.targets.discover(m.steam_roots())
        self.assertEqual(len(found), 8)
        heroic = next(t for t in found if t['name'] == 'Heroic · Proton')
        flatpak = next(t for t in found if t['name'] == 'Heroic · Proton (Flatpak)')
        self.assertNotEqual(heroic['directory'], flatpak['directory'])
        self.assertFalse(Path(heroic['directory']).exists())
        self.assertTrue(m.targets.supports(heroic, 'proton'))
        self.assertFalse(m.targets.supports(heroic, 'wine'))
        self.assertEqual(m.targets.directory(heroic, 'dxvk'), config / 'heroic/tools/dxvk')
        lutris = next(t for t in found if t['launcher'] == 'lutris')
        self.assertEqual(m.targets.directory(lutris, 'vkd3d'), data / 'lutris/runtime/vkd3d')

    def test_cli_scans_heroic_without_steam_and_rejects_wrong_source(self):
        (self.home / '.config/heroic').mkdir(parents=True)
        target = self.home / '.config/heroic/tools/wine'
        command = ['/usr/bin/python3', str(PLUGIN / 'scripts/manager.py')]
        scan = subprocess.run(command + ['scan', '--root', str(target)], capture_output=True, text=True)
        self.assertEqual(scan.returncode, 0, scan.stdout)
        data = json.loads(scan.stdout)
        self.assertEqual(data['target']['launcher'], 'heroic')
        self.assertEqual(data['root'], str(target))
        self.assertIn('wine', [p['id'] for p in data['providers']])
        self.assertNotIn('cachyos', [p['id'] for p in data['providers']])
        self.assertEqual(data['games'], [])
        rejected = subprocess.run(command + ['install', '--root', str(target), '--provider', 'cachyos', '--tag', 'test'], capture_output=True, text=True)
        self.assertNotEqual(rejected.returncode, 0)
        self.assertIn('does not support', rejected.stdout)
        self.assertFalse(list(target.glob('proton-*')))

    def test_cpu_variants_and_architectures_are_filtered(self):
        check = m.providers.matches_arch
        self.assertTrue(check('proton-x86_64.tar.xz', 'x86_64', set()))
        self.assertFalse(check('proton-arm64.tar.xz', 'x86_64', set()))
        self.assertTrue(check('proton-arm64.tar.xz', 'aarch64', set()))
        self.assertFalse(check('wine-11-x86.tar.xz', 'x86_64', set()))
        self.assertFalse(check('proton-x86_64_v3.tar.xz', 'x86_64', {'avx2'}))
        flags = {'cx16', 'lahf_lm', 'popcnt', 'pni', 'ssse3', 'sse4_1', 'sse4_2',
                 'avx', 'avx2', 'bmi1', 'bmi2', 'f16c', 'fma', 'abm', 'movbe', 'xsave'}
        self.assertTrue(check('proton-x86_64_v3.tar.xz', 'x86_64', flags))
        self.assertFalse(check('proton-x86_64_v4.tar.xz', 'x86_64', flags))

    def test_assets_keep_distinct_variants_and_verification(self):
        release = {'tag_name': 'test', 'assets': []}
        for variant in ('x86_64', 'x86_64_wow64', 'arm64'):
            name = 'proton-cachyos-test-' + variant + '.tar.xz'
            release['assets'].append(dict(name=name, size=42, browser_download_url='https://example.com/' + name, digest='sha256:' + 'a' * 64))
        rows = m.providers.assets(release, 'cachyos', 'x86_64', set())
        self.assertEqual(len(rows), 2)
        self.assertNotEqual(rows[0]['asset'], rows[1]['asset'])
        self.assertEqual(rows[0]['verification'], 'SHA256')
        release['assets'][0]['digest'] = None
        self.assertEqual(m.providers.assets(release, 'cachyos', 'x86_64', set())[0]['verification'], 'HTTPS only')
        release['assets'][0]['name'] = '../../proton-cachyos.tar.xz'
        self.assertEqual(len(m.providers.assets(release, 'cachyos', 'x86_64', set())), 1)

    def wine_release(self):
        archive = self.home / 'wine.tar.xz'
        with tarfile.open(archive, 'w:xz') as tar:
            entry = tarfile.TarInfo('wine-test/bin/wine')
            payload = b'#!/bin/sh\nexit 0\n'
            entry.mode, entry.size = 0o755, len(payload)
            tar.addfile(entry, io.BytesIO(payload))
        content = archive.read_bytes()
        source = m.providers.PROVIDERS['wine']
        release = dict(tag_name='test', assets=[dict(name='wine-test-amd64.tar.xz', size=len(content),
                       browser_download_url=source['origin'] + 'releases/download/test/wine-test-amd64.tar.xz',
                       digest='sha256:' + hashlib.sha256(content).hexdigest())])
        directory = self.home / '.config/heroic/tools/wine'
        target = dict(path=str(directory), directory=str(directory), launcher='heroic', kinds=['wine'],
                      config=str(self.home / '.config/heroic'))
        return content, release, target

    def test_wine_install_inventory_reference_guard_and_removal(self):
        content, release, target = self.wine_release()
        directory = Path(target['directory'])
        with m.locked(directory, target), patch.object(m, 'MAX_EXPANDED', 1024 * 1024), patch.object(m, 'fetch_json', return_value=release), patch.object(m, 'request', return_value=io.BytesIO(content)):
            m.install(directory, 'test', 'wine', release['assets'][0]['name'], target)
        installed = m.target_inventory(target)['tools']
        self.assertEqual(len(installed), 1)
        self.assertTrue(installed[0]['managed'])
        build = Path(installed[0]['path'])
        self.assertTrue((build / 'bin/wine').is_file())
        config = Path(target['config']) / 'GamesConfig'
        config.mkdir()
        settings = config / 'game.json'
        settings.write_text(json.dumps({'wineVersion': {'bin': str(build / 'bin/wine')}}))
        with patch.object(m, 'steam_running', return_value=False), patch.object(m, 'launcher_running', return_value=False):
            with self.assertRaisesRegex(m.ManagerError, 'referenced'):
                m.remove(directory, str(build), target)
            settings.unlink()
            m.remove(directory, str(build), target)
        self.assertFalse(build.exists())

    def test_wine_digest_failure_and_wrong_target_leave_no_build(self):
        content, release, target = self.wine_release()
        directory = Path(target['directory'])
        release['assets'][0]['digest'] = 'sha256:' + '0' * 64
        with m.locked(directory, target), patch.object(m, 'MAX_EXPANDED', 1024 * 1024), patch.object(m, 'fetch_json', return_value=release), patch.object(m, 'request', return_value=io.BytesIO(content)):
            with self.assertRaisesRegex(m.ManagerError, 'mismatch'):
                m.install(directory, 'test', 'wine', release['assets'][0]['name'], target)
        self.assertFalse(list(directory.glob('wine-*')))
        self.assertFalse(list(directory.glob('.proton-manager-download-*')))
        target['kinds'] = ['proton']
        with self.assertRaisesRegex(m.ManagerError, 'does not support'):
            m.install(directory, 'test', 'wine', '', target)

    def test_unexpected_release_hosts_are_rejected_before_network(self):
        with patch.object(m.urllib.request, 'urlopen') as fetch:
            for url in ('https://github.com/attacker/build/releases/download/a/b', m.providers.PROVIDERS['ge']['api'] + '-evil',
                        'file:///etc/passwd', 'https://dawn.wine.evil/attachments/file'):
                with self.assertRaises(m.ManagerError):
                    m.request(url)
            fetch.assert_not_called()

    def install_fixture(self, bad_checksum=False, cancel=False, checksum_name="GE-Proton-test-x86_64.tar.gz"):
        archive = self.archive()
        content = archive.read_bytes()
        checksum = '0' * 128 if bad_checksum else hashlib.sha512(content).hexdigest()
        def response(url):
            if url.endswith('.sha512sum'):
                return io.BytesIO((checksum + '  ' + checksum_name + '\n').encode())
            if cancel:
                raise SystemExit(130)
            return io.BytesIO(content)
        with patch.object(m, 'fetch_json', return_value=self.release(archive)), patch.object(m, 'request', side_effect=response), patch.object(m.shutil, 'disk_usage') as disk, contextlib.redirect_stdout(io.StringIO()):
            disk.return_value.free = 20 * 1024**3
            with m.locked(self.root):
                return m.install(self.root, 'GE-Proton-test')

    def test_download_is_verified_and_atomically_published(self):
        self.install_fixture()
        installed = self.root / 'compatibilitytools.d/GE-Proton-test-x86_64'
        self.assertTrue((installed / 'proton').is_file())
        self.assertEqual(json.loads((installed / '.proton-manager-install.json').read_text())['owner'], m.OWNER)
        self.assertEqual(list(installed.parent.glob('.proton-manager-download-*')), [])

    def test_bad_checksum_and_cancellation_never_publish(self):
        with self.assertRaisesRegex(m.ManagerError, 'Checksum'):
            self.install_fixture(bad_checksum=True)
        with self.assertRaises(SystemExit):
            self.install_fixture(cancel=True)
        self.assertFalse((self.root / 'compatibilitytools.d/GE-Proton-test-x86_64').exists())
        self.assertEqual(list((self.root / 'compatibilitytools.d').glob('.proton-manager-download-*')), [])

    def test_refresh_recovers_from_missing_launcher_but_mutation_rejects_it(self):
        command = ['/usr/bin/python3', str(PLUGIN / 'scripts/manager.py')]
        missing = str(self.home / 'missing')
        result = subprocess.run(command + ['scan', '--root', missing], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotEqual(json.loads(result.stdout)['root'], missing)
        result = subprocess.run(command + ['remove', '--root', missing], capture_output=True, text=True)
        self.assertEqual(result.returncode, 1)
        self.assertEqual(json.loads(result.stdout)['type'], 'error')

    def test_checksum_for_another_archive_is_rejected(self):
        with self.assertRaisesRegex(m.ManagerError, 'checksum is invalid'):
            self.install_fixture(checksum_name='another-build.tar.gz')
        self.assertFalse((self.root / 'compatibilitytools.d/GE-Proton-test-x86_64').exists())

    def test_game_assignment_blocks_removal_until_cleared(self):
        (self.second / '.proton-manager-install.json').write_text(json.dumps({'owner': m.OWNER}))
        self.select()
        self.select(self.second, 'game', '42')
        with patch.object(m, 'steam_running', return_value=False):
            with self.assertRaisesRegex(m.ManagerError, 'assigned to a game'):
                m.remove(self.root, str(self.second))
            m.select(self.root, '', 'game', '42')
            m.remove(self.root, str(self.second))
        self.assertFalse(self.second.exists())

    def test_inventory_requires_valid_ownership_and_excludes_symlink_authority(self):
        marker = self.first / '.proton-manager-install.json'
        marker.write_text('{invalid')
        self.assertFalse(m.tool_info(self.first)['managed'])
        marker.write_text(json.dumps({'owner': 'someone-else'}))
        self.assertFalse(m.tool_info(self.first)['managed'])
        marker.write_text(json.dumps({'owner': m.OWNER}))
        self.assertTrue(m.tool_info(self.first)['managed'])
        link = self.first.parent / 'alias'
        link.symlink_to(self.first, target_is_directory=True)
        self.assertFalse(m.tool_info(link)['managed'])

    def test_scan_warns_when_active_build_disappears_or_changes_runtime(self):
        self.select()
        (self.first / 'toolmanifest.vdf').write_text('"manifest" { "require_tool_appid" "999" }')
        self.assertTrue(any('Active build is missing or incompatible' in warning for warning in m.inventory(self.root)['warnings']))
        (self.first / 'proton').unlink()
        self.assertTrue(any('Active build is missing or incompatible' in warning for warning in m.inventory(self.root)['warnings']))

    def test_build_timestamp_uses_embedded_date_with_local_fallback(self):
        version = self.first / 'version'
        version.write_text('1786437966 GE-Proton11-5\n')
        self.assertEqual(m.tool_info(self.first)['buildTime'], 1786437966)
        version.write_text('unknown version\n')
        self.assertEqual(m.tool_info(self.first)['buildTime'], self.first.stat().st_mtime)

    def test_invalid_selection_reports_a_configuration_error(self):
        self.select()
        path = self.root / 'compatibilitytools.d' / m.SLOT / 'selection.json'
        valid = m.read_selection(self.root)
        for data in ([], {**valid, 'default': ''}, {**valid, 'runtime': 42},
                     {**valid, 'games': {'42': None}}, {**valid, 'games': {'bad-id': str(self.first)}}):
            path.write_text(json.dumps(data))
            with self.assertRaisesRegex(m.ManagerError, 'configuration is invalid'):
                m.read_selection(self.root)


if __name__ == '__main__':
    unittest.main()
