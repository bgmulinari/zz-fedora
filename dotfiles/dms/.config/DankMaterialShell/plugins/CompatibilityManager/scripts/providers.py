"""Release sources and asset selection, independent of launcher filesystem state."""
import platform
import re
from pathlib import Path


def github(name, repo, kind, pattern, description):
    return dict(name=name, api=f'https://api.github.com/repos/{repo}/releases',
                origin=f'https://github.com/{repo}/', kind=kind, pattern=pattern,
                description=description)


PROVIDERS = {
    'ge': github('GE-Proton', 'GloriousEggroll/proton-ge-custom', 'proton', r'GE-Proton.*', 'Community Proton builds with game fixes.'),
    'cachyos': github('Proton-CachyOS', 'CachyOS/proton-cachyos', 'proton', r'proton-cachyos.*', 'CachyOS Proton builds; CPU variants are filtered for this machine.'),
    'em': github('Proton-EM', 'Etaash-mathamsetty/Proton', 'proton', r'proton.*', 'Proton with Wine-Wayland and additional game patches.'),
    'wineland': github('Proton-Wineland', 'nanomatters/proton-cachyos', 'proton', r'proton-wineland.*', 'Proton builds focused on Wine-Wayland.'),
    'rtsp': github('Proton-RTSP', 'SpookySkeletons/proton-rtsp', 'proton', r'proton.*', 'Community Proton fork.'),
    'tkg': github('Proton-TKG (releases)', 'Frogging-Family/wine-tkg-git', 'proton', r'proton.*', 'Published Proton-TKG releases; excludes CI artifacts.'),
    'wine-ge': github('Wine-GE (legacy)', 'GloriousEggroll/wine-ge-custom', 'wine', r'wine.*', 'Archived Wine-GE builds for older game configurations.'),
    'wine-lutris': github('Lutris-Wine (legacy)', 'lutris/wine', 'wine', r'wine.*', 'Published Lutris Wine runners.'),
    'wine': github('Wine / Staging / TKG (Kron4ek)', 'Kron4ek/Wine-Builds', 'wine', r'wine.*', 'Vanilla, Staging and TKG Wine builds, including WoW64 variants.'),
    'dxvk': github('DXVK', 'doitsujin/dxvk', 'dxvk', r'dxvk-[0-9].*', 'Direct3D 8–11 components for Heroic and Lutris.'),
    'vkd3d': github('VKD3D-Proton', 'HansKristian-Work/vkd3d-proton', 'vkd3d', r'vkd3d-proton.*', 'Direct3D 12 components for Heroic and Lutris.'),
    'dw': dict(name='DWProton', api='https://dawn.wine/api/v1/repos/dawn-winery/dwproton/releases',
               origin='https://dawn.wine/dawn-winery/dwproton/', kind='proton', pattern=r'.*proton.*',
               description='Dawn Winery Proton builds.'),
}
EXTENSION = re.compile(r'\.tar\.(gz|xz|bz2|zst)$')


def cpu_flags():
    # Intersect cores: a process may be scheduled on any of them.
    cores = [set(line.split(':', 1)[1].split()) for line in Path('/proc/cpuinfo').read_text().splitlines()
             if line.startswith('flags') and ':' in line]
    return set.intersection(*cores) if cores else set()


def matches_arch(name, machine=None, flags=None):
    machine = (machine or platform.machine()).lower()
    arm = machine in ('aarch64', 'arm64')
    if not arm and machine not in ('x86_64', 'amd64'):
        return False
    lower = name.lower()
    if any(token in lower for token in ('aarch64', 'arm64')) != arm:
        return False
    if re.search(r'(?:^|[-_])(?:x86|i[3-6]86)(?:[.-]|$)', lower):
        return False
    level = re.search(r'x86[_-]64[_-]v([234])', lower)
    if level:
        flags = cpu_flags() if flags is None else flags
        required = {'cx16', 'lahf_lm', 'popcnt', 'pni', 'ssse3', 'sse4_1', 'sse4_2'}
        if int(level[1]) >= 3:
            required |= {'avx', 'avx2', 'bmi1', 'bmi2', 'f16c', 'fma', 'abm', 'movbe', 'xsave'}
        if int(level[1]) >= 4:
            required |= {'avx512f', 'avx512bw', 'avx512cd', 'avx512dq', 'avx512vl'}
        if not required <= flags:
            return False
    return True


def assets(release, provider_id='ge', machine=None, flags=None):
    provider = PROVIDERS[provider_id]
    if release.get('draft'):
        return []
    result = []
    for asset in release.get('assets', []):
        name = asset['name']
        if not EXTENSION.search(name) or not re.fullmatch(provider['pattern'], name, re.I):
            continue
        if not re.fullmatch(r'[\w.+-]+', name) or '.pkg.tar.' in name:
            continue
        if not matches_arch(name, machine, flags):
            continue
        stem = EXTENSION.sub('', name)
        checksum, algorithm = '', ''
        for algo in ('sha512', 'sha256'):
            match = next((a for a in release['assets'] if a['name'] in (stem + '.' + algo + 'sum', name + '.' + algo + 'sum', stem + '.' + algo, name + '.' + algo)), None)
            if match:
                checksum, algorithm = match['browser_download_url'], algo
                break
        digest = asset.get('digest') or ''
        if not re.fullmatch(r'sha(?:256|512):[a-fA-F0-9]+', digest):
            digest = ''
        result.append(dict(tag=release['tag_name'], asset=name, name=stem,
                           provider=provider_id, kind=provider['kind'], prerelease=release.get('prerelease', False),
                           date=release.get('published_at', '')[:10], size=asset['size'],
                           url=asset['browser_download_url'], checksum=checksum, algorithm=algorithm, digest=digest,
                           verification=algorithm.upper() if checksum else digest.split(':')[0].upper() if digest else 'HTTPS only',
                           notes=release.get('body') or '', notesHtml=release.get('body_html') or '',
                           page=release.get('html_url') or provider['origin'] + 'releases'))
    return result
