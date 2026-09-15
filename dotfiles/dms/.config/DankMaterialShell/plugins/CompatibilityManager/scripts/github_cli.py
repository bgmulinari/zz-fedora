"""Optional authenticated GitHub transport; credentials stay inside gh."""
import email.parser
import io
import os
import shutil
import subprocess
import time
import urllib.error

import release_cache


class Unavailable(RuntimeError):
    pass


def environment():
    return {**os.environ, 'GH_PROMPT_DISABLED': '1', 'GIT_TERMINAL_PROMPT': '0', 'GH_PAGER': 'cat'}


def authenticated():
    executable = shutil.which('gh')
    if not executable:
        return False
    path = release_cache.directory() / 'gh-auth.json'
    status = release_cache.read(path)
    # auth status may contact GitHub. Probe at most once per five minutes,
    # and only when a metadata page actually needs a network request.
    if status.get('executable') == executable and isinstance(status.get('time'), (int, float)) and 0 <= time.time() - status['time'] < 300:
        return bool(status.get('authenticated'))
    try:
        result = subprocess.run([executable, 'auth', 'status', '--active', '--hostname', 'github.com'],
                                stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                env=environment(), timeout=10)
        available = result.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        available = False
    release_cache.write(path, dict(executable=executable, time=time.time(), authenticated=available))
    return available


def request(url, headers=None):
    if not url.startswith('https://api.github.com/repos/'):
        raise ValueError('GitHub CLI transport only supports release API requests')
    executable = shutil.which('gh')
    if not executable:
        raise Unavailable('GitHub CLI is unavailable')
    command = [executable, 'api', '--hostname', 'github.com', '--method', 'GET', '--include',
               '-H', 'Accept: application/vnd.github.full+json']
    for name, value in (headers or {}).items():
        command += ['-H', name + ': ' + value]
    command += [url.removeprefix('https://api.github.com/')]
    try:
        result = subprocess.run(command, input=b'', capture_output=True, timeout=30, env=environment())
    except FileNotFoundError as error:
        raise Unavailable('GitHub CLI is unavailable') from error
    except (OSError, subprocess.TimeoutExpired) as error:
        raise urllib.error.URLError('GitHub CLI request failed or timed out') from error
    raw = result.stdout.replace(b'\r\n', b'\n')
    head, _, body = raw.partition(b'\n\n')
    first, _, fields = head.partition(b'\n')
    if not first.startswith(b'HTTP/'):
        if result.returncode == 4:
            raise Unavailable('GitHub CLI needs authentication')
        raise urllib.error.URLError('GitHub CLI could not fetch release metadata')
    try:
        code = int(first.split()[1])
    except (ValueError, IndexError) as error:
        raise urllib.error.URLError('Invalid GitHub CLI response') from error
    response_headers = email.parser.BytesParser().parsebytes(fields)
    if code == 401:
        release_cache.write(release_cache.directory() / 'gh-auth.json', {})
        raise Unavailable('GitHub CLI authentication expired')
    if code == 304 or code >= 400:
        raise urllib.error.HTTPError(url, code, 'GitHub API response', response_headers, io.BytesIO(body))
    if result.returncode or not 200 <= code < 300:
        raise urllib.error.URLError('GitHub CLI could not fetch release metadata')
    response = io.BytesIO(body)
    response.headers = response_headers
    return response
