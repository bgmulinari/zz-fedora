"""Launcher installation destinations, using launcher-owned directories."""
import os
from pathlib import Path


def discover(steam_roots):
    home = Path.home()
    data = Path(os.environ.get('XDG_DATA_HOME', home / '.local/share'))
    config = Path(os.environ.get('XDG_CONFIG_HOME', home / '.config'))
    result = [dict(path=str(root), directory=str(root / 'compatibilitytools.d'),
                   name='Steam (Flatpak)' if '/.var/app/' in str(root) else 'Steam (Snap)' if '/snap/' in str(root) else 'Steam',
                   launcher='steam', kinds=['proton'], config=str(root / 'config')) for root in steam_roots]
    variants = [(data, config, '')]
    for app in ('com.heroicgameslauncher.hgl', 'net.lutris.Lutris', 'com.usebottles.bottles', 'io.github.fastrizwaan.WineZGUI'):
        base = home / '.var/app' / app
        variants.append((base / 'data', base / 'config', app))
    for data_dir, config_dir, app in variants:
        flatpak = ' (Flatpak)' if app else ''
        candidates = []
        if not app or app == 'com.heroicgameslauncher.hgl':
            base = config_dir / 'heroic'
            for kind in ('proton', 'wine'):
                candidates.append((base, base / 'tools' / kind, 'Heroic · ' + kind.title(), 'heroic', [kind], base))
        if not app or app == 'net.lutris.Lutris':
            base = data_dir / 'lutris'
            candidates.append((base if base.exists() else config_dir / 'lutris', base / 'runners/wine', 'Lutris', 'lutris', ['proton', 'wine'], config_dir / 'lutris'))
        if not app or app == 'com.usebottles.bottles':
            base = data_dir / 'bottles'
            candidates.append((base, base / 'runners', 'Bottles', 'bottles', ['proton', 'wine'], base / 'bottles'))
        if not app or app == 'io.github.fastrizwaan.WineZGUI':
            base = data_dir / 'winezgui'
            candidates.append((base, base / 'Runners', 'WineZGUI', 'winezgui', ['wine'], base))
        for evidence, directory, name, launcher, kinds, settings in candidates:
            if evidence.is_dir():
                result.append(dict(path=str(directory.resolve()), directory=str(directory.resolve()),
                                   name=name + flatpak, launcher=launcher, kinds=kinds,
                                   config=str(settings), app=app))
    result = list({item['path']: item for item in result}.values())
    names = [item['name'] for item in result]
    for item in result:
        if names.count(item['name']) > 1:
            item['name'] += ' · ' + item['path']
    return result


def directory(target, kind):
    base = Path(target['directory'])
    if kind in ('dxvk', 'vkd3d'):
        if target['launcher'] == 'heroic':
            return base.parent / kind
        if target['launcher'] == 'lutris':
            return base.parent.parent / 'runtime' / kind
        raise ValueError('This launcher does not support standalone graphics components')
    if kind not in target['kinds']:
        raise ValueError('This runtime type is not supported by the selected destination')
    return base


def supports(target, kind):
    return not target or kind in target['kinds'] or (kind in ('dxvk', 'vkd3d') and target['launcher'] in ('heroic', 'lutris'))
