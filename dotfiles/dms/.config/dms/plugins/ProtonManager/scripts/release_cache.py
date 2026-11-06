"""Persistent public release metadata and host-wide API cooldowns."""
import email.utils
import hashlib
import json
import os
from pathlib import Path
import tempfile
import time
import urllib.error
import urllib.parse

TTL = 3600
MAX_RESPONSE = 16 * 1024**2


class RateLimited(RuntimeError):
    def __init__(self, host, retry_at):
        self.retry_at = retry_at
        name = 'GitHub' if host == 'api.github.com' else host
        when = time.strftime('%H:%M %Z', time.localtime(retry_at))
        super().__init__(f'{name} API rate limit reached. Try again after {when}. Previously cached releases remain available.')


def directory():
    return Path(os.environ.get('XDG_CACHE_HOME', Path.home() / '.cache')) / 'proton-manager/releases'


def read(path):
    try:
        if path.stat().st_size > MAX_RESPONSE * 2:
            return {}
        data = json.loads(path.read_text())
        return data if isinstance(data, dict) else {}
    except (OSError, ValueError):
        return {}


def write(path, data):
    # Cache failure must never prevent normal use on a read-only/full filesystem.
    temporary = None
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        fd, temporary = tempfile.mkstemp(prefix='.cache-', dir=path.parent)
        with os.fdopen(fd, 'w') as stream:
            json.dump(data, stream)
        os.replace(temporary, path)
        files = sorted(path.parent.glob('page-*.json'), key=lambda p: p.stat().st_mtime, reverse=True)
        for old in files[64:]:
            old.unlink(missing_ok=True)
    except OSError:
        pass
    finally:
        if temporary:
            try:
                Path(temporary).unlink(missing_ok=True)
            except OSError:
                pass


def cooldown_path(host):
    return directory() / ('cooldown-' + hashlib.sha256(host.encode()).hexdigest() + '.json')


def deadline(headers, previous=None):
    now = time.time()
    try:
        reset = float(headers.get('X-RateLimit-Reset', 0)) if headers.get('X-RateLimit-Remaining') == '0' else 0
        retry = headers.get('Retry-After', '')
        if retry:
            try:
                retry = now + float(retry)
            except ValueError:
                retry = email.utils.parsedate_to_datetime(retry).timestamp()
        attempts = int((previous or {}).get('attempts', 0))
        return max(reset, float(retry or 0), now + min(3600, 60 * 2 ** min(attempts, 6))) + 1
    except (ValueError, TypeError, OverflowError):
        return now + 60


def fetch(url, opener, transport=None):
    host = urllib.parse.urlsplit(url).netloc
    path = directory() / ('page-' + hashlib.sha256(url.encode()).hexdigest() + '.json')
    record = read(path)
    if record.get('url') != url or not isinstance(record.get('time'), (int, float)):
        record = {}
    # A browsed page already contains the full metadata needed by Install.
    # Reuse its release entry instead of spending another request on /tags/.
    if '/tags/' in url:
        prefix, tag = url.split('/tags/', 1)
        tag = urllib.parse.unquote(tag)
        for page in directory().glob('page-*.json'):
            candidate = read(page)
            if not isinstance(candidate.get('url'), str) or not candidate['url'].startswith(prefix + '?') or not isinstance(candidate.get('data'), list):
                continue
            if not isinstance(candidate.get('time'), (int, float)):
                continue
            if candidate['time'] <= record.get('time', 0):
                continue
            release = next((r for r in candidate['data'] if isinstance(r, dict) and r.get('tag_name') == tag), None)
            if release:
                record = dict(url=url, time=candidate['time'], data=release)
    cached = record.get('url') == url and isinstance(record.get('data'), (dict, list)) and isinstance(record.get('time'), (int, float))
    now = time.time()
    if cached and 0 <= now - record['time'] < TTL:
        return record['data'], dict(cached=True, stale=False)
    scope = host
    if transport and host == 'api.github.com':
        alternative = transport()
        if alternative:
            opener = alternative
            scope += ':gh'
    cooldown_file = cooldown_path(scope)
    cooldown = read(cooldown_file)
    try:
        until = float(cooldown.get('until', 0))
    except (ValueError, TypeError):
        until = 0
    if until > now:
        error = RateLimited(host, until)
        if cached:
            return record['data'], dict(cached=True, stale=True, notice=str(error), retryAt=until)
        raise error
    headers = {}
    if cached:
        if record.get('etag'):
            headers['If-None-Match'] = record['etag']
        elif record.get('modified'):
            headers['If-Modified-Since'] = record['modified']
    try:
        with (opener(url, headers=headers) if headers else opener(url)) as response:
            raw = response.read(MAX_RESPONSE + 1)
            if len(raw) > MAX_RESPONSE:
                raise ValueError('Release catalog exceeds the response limit')
            data = json.loads(raw)
            if not isinstance(data, (dict, list)):
                raise ValueError('Invalid release catalog')
            response_headers = getattr(response, 'headers', {})
            write(path, dict(url=url, time=now, data=data, etag=response_headers.get('ETag', ''), modified=response_headers.get('Last-Modified', '')))
            if response_headers.get('X-RateLimit-Remaining') == '0':
                write(cooldown_file, dict(until=deadline(response_headers), attempts=0))
            else:
                write(cooldown_file, dict(until=0, attempts=0))
            return data, dict(cached=False, stale=False)
    except urllib.error.HTTPError as error:
        try:
            if error.code == 304 and cached:
                record['time'] = now
                write(path, record)
                return record['data'], dict(cached=True, stale=False)
            body = error.read(4096).decode(errors='replace')
            limited = error.code == 429 or (error.code == 403 and (error.headers.get('X-RateLimit-Remaining') == '0' or error.headers.get('Retry-After') or 'rate limit' in body.lower()))
            if limited:
                until = deadline(error.headers, cooldown)
                write(cooldown_file, dict(until=until, attempts=int(cooldown.get('attempts', 0)) + 1))
                rate_error = RateLimited(host, until)
                if cached:
                    return record['data'], dict(cached=True, stale=True, notice=str(rate_error), retryAt=until)
                raise rate_error from error
            if not cached or error.code < 500:
                raise
        finally:
            error.close()
    except (urllib.error.URLError, OSError):
        if not cached:
            raise
    return record['data'], dict(cached=True, stale=True, notice='Source unavailable. Showing previously cached releases.')
