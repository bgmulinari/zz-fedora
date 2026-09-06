"""Shared helpers for the collect-* scripts and update-usage.

Every collector prints one display-ready record, and the parts that must
agree across collectors live here: the cache and state directories, the
local-day bucketing, the per-message accumulator behind todayPrompts,
recentDays and modelUsage, the atomic JSON writer, the day-scoped scan
cache, and the cached-limits fallback. A collector imports this module from
its own directory; update-usage discovers collectors by the collect- prefix,
so this file is never mistaken for one.
"""

from __future__ import annotations

import datetime as dt
import json
import os
import tempfile
import time
from pathlib import Path
from typing import Any

# A scan this recent is only reused to dedup concurrent collector runs (the
# update command runs one per agent while the widget refreshes on its own);
# every periodic widget refresh lands a real rescan. --limits-only promises
# only fresh limits, so it may reuse a scan for up to 15 minutes.
SCAN_REUSE_SECONDS = 20
LIMITS_ONLY_REUSE_SECONDS = 900

# A popout that is opened and shut repeatedly must not turn into a probe per
# flick: limits fetched this recently are reused unless --force asks for
# fresh numbers. The interval absorbs repeated opens, not a refresh someone
# asked for.
LIMITS_REUSE_SECONDS = 15

TOKEN_FIELDS = ("inputTokens", "outputTokens", "cacheReadInputTokens", "cacheCreationInputTokens")


def scan_reuse_seconds(force: bool, limits_only: bool) -> float:
    if force:
        return 0
    return LIMITS_ONLY_REUSE_SECONDS if limits_only else SCAN_REUSE_SECONDS


# ------------------------------------------------------------------- paths


def xdg_dir(variable: str, fallback: str) -> Path:
    return Path(os.environ.get(variable) or (Path.home() / fallback))


def cache_root() -> Path:
    root = xdg_dir("XDG_CACHE_HOME", ".cache") / "zz-fedora" / "agent-usage"
    root.mkdir(parents=True, exist_ok=True)
    return root


def usage_dir() -> Path:
    return xdg_dir("XDG_STATE_HOME", ".local/state") / "zz-fedora" / "agent-usage"


def opencode_db() -> Path:
    return xdg_dir("XDG_DATA_HOME", ".local/share") / "opencode" / "opencode.db"


def pi_session_roots() -> list[Path]:
    return [Path.home() / ".pi" / "agent" / "sessions", Path.home() / ".omp" / "agent" / "sessions"]


# ------------------------------------------------------------------- dates


def date_string(value: dt.date) -> str:
    return value.strftime("%Y-%m-%d")


def today_string() -> str:
    return date_string(dt.datetime.now().date())


def recent_date_strings() -> list[str]:
    today = dt.datetime.now().date()
    return [date_string(today - dt.timedelta(days=offset)) for offset in range(6, -1, -1)]


def local_day(value: Any) -> str:
    """The local calendar day of a timestamp: epoch seconds or milliseconds,
    or ISO-8601 text with an offset or a trailing Z. Anything unreadable
    counts as today rather than being dropped."""
    if value is None:
        return today_string()
    if isinstance(value, (int, float)):
        try:
            seconds = float(value) / 1000.0 if float(value) > 10_000_000_000 else float(value)
            return date_string(dt.datetime.fromtimestamp(seconds).date())
        except Exception:
            return today_string()
    raw = str(value).strip()
    if raw == "":
        return today_string()
    try:
        parsed = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
        if parsed.tzinfo is not None:
            parsed = parsed.astimezone()
        return date_string(parsed.date())
    except Exception:
        return today_string()


def parse_iso_utc(raw: str) -> dt.datetime | None:
    try:
        parsed = dt.datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except Exception:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=dt.timezone.utc)
    return parsed


# ------------------------------------------------------------------ numbers


def number(value: Any) -> int:
    try:
        n = float(value or 0)
        return round(n) if n == n else 0
    except Exception:
        return 0


def usage_token(usage: dict[str, Any], *keys: str) -> int:
    """The first of several spellings a usage object may use for one count."""
    for key in keys:
        if key in usage:
            return number(usage.get(key))
    return 0


def empty_bucket() -> dict[str, int]:
    return {field: 0 for field in TOKEN_FIELDS}


# ------------------------------------------------------------- accumulator


class UsageStats:
    """One assistant message at a time into the record's local-stats fields.

    recentDays.messageCount is a token total; the name is shared with synced
    snapshots. activeDates travel alongside activeDays because merging
    snapshots from several machines needs their union, which a count alone
    cannot give.
    """

    def __init__(self) -> None:
        self.today = today_string()
        self.recent_dates = recent_date_strings()
        self.recent = {day: 0 for day in self.recent_dates}
        self.sessions: set[str] = set()
        self.active_days: set[str] = set()
        self.today_sessions: set[str] = set()
        self.today_tokens: dict[str, int] = {}
        self.usage_by_model: dict[str, dict[str, int]] = {}
        self.prompts = 0
        self.today_prompts = 0
        self.today_total = 0

    def add(self, day: str, session_key: str, model: str, input_tokens: int, output_tokens: int, cache_read: int, cache_write: int) -> None:
        total = input_tokens + output_tokens + cache_read + cache_write
        if total <= 0:
            return
        self.prompts += 1
        self.sessions.add(session_key)
        self.active_days.add(day)

        bucket = self.usage_by_model.setdefault(model, empty_bucket())
        bucket["inputTokens"] += input_tokens
        bucket["outputTokens"] += output_tokens
        bucket["cacheReadInputTokens"] += cache_read
        bucket["cacheCreationInputTokens"] += cache_write

        if day in self.recent:
            self.recent[day] += total
        if day == self.today:
            self.today_prompts += 1
            self.today_sessions.add(session_key)
            self.today_total += total
            self.today_tokens[model] = self.today_tokens.get(model, 0) + total

    def to_dict(self) -> dict[str, Any]:
        return {
            "todayPrompts": self.today_prompts,
            "todaySessions": len(self.today_sessions),
            "todayTotalTokens": self.today_total,
            "todayTokensByModel": self.today_tokens,
            "recentDays": [{"date": day, "messageCount": self.recent[day]} for day in self.recent_dates],
            "modelUsage": self.usage_by_model,
            "totalPrompts": self.prompts,
            "totalSessions": len(self.sessions),
            "activeDays": len(self.active_days),
            "activeDates": sorted(self.active_days),
        }


def merge_stats(base: dict[str, Any], extra: dict[str, Any]) -> dict[str, Any]:
    """Two local-stats dicts from sources that do not overlap in messages
    (native transcripts plus pi or opencode sessions) add up, except for
    the active days, which overlap in time and are unioned."""
    merged = dict(base)
    for key in ("todayPrompts", "todaySessions", "todayTotalTokens", "totalPrompts", "totalSessions"):
        merged[key] = number(base.get(key)) + number(extra.get(key))

    combined = dict(base.get("todayTokensByModel") or {})
    for model, count in (extra.get("todayTokensByModel") or {}).items():
        combined[model] = number(combined.get(model)) + number(count)
    merged["todayTokensByModel"] = combined

    usage = {model: dict(bucket) for model, bucket in (base.get("modelUsage") or {}).items()}
    for model, bucket in (extra.get("modelUsage") or {}).items():
        target = usage.setdefault(model, empty_bucket())
        for field, count in (bucket or {}).items():
            target[field] = number(target.get(field)) + number(count)
    merged["modelUsage"] = usage

    by_date: dict[str, int] = {}
    for source in (base.get("recentDays") or [], extra.get("recentDays") or []):
        for day in source:
            date = str((day or {}).get("date") or "")
            if date:
                by_date[date] = by_date.get(date, 0) + number((day or {}).get("messageCount"))
    merged["recentDays"] = [{"date": date, "messageCount": by_date[date]} for date in sorted(by_date)]

    # A fallback that only knows a count still bounds the answer from below.
    dates = set(base.get("activeDates") or []) | set(extra.get("activeDates") or [])
    merged["activeDates"] = sorted(dates)
    merged["activeDays"] = max(len(dates), number(base.get("activeDays")), number(extra.get("activeDays")))
    return merged


# -------------------------------------------------------------------- files


def read_fresh_json(path: Path, max_age_seconds: float) -> Any:
    if max_age_seconds <= 0 or not path.exists():
        return None
    try:
        # A negative age means the mtime is in the future: the clock moved
        # backwards since the write, so the cache's freshness is unknown.
        age = time.time() - path.stat().st_mtime
        if 0 <= age <= max_age_seconds:
            return json.loads(path.read_text(encoding="utf-8"))
    except Exception:
        return None
    return None


def write_text(path: Path, text: str) -> None:
    """Replace path atomically. The temp name is unique to this writer, not
    derived from the target alone: several collectors can run at once, and
    a shared temp path means the second replace finds the first one's file
    already moved away."""
    handle_fd, tmp_name = tempfile.mkstemp(dir=path.parent, prefix="." + path.name + ".", suffix=".tmp")
    tmp = Path(tmp_name)
    try:
        with os.fdopen(handle_fd, "w", encoding="utf-8") as handle:
            handle.write(text)
        tmp.chmod(0o644)
        tmp.replace(path)
    except BaseException:
        tmp.unlink(missing_ok=True)
        raise


def write_json(path: Path, payload: Any) -> None:
    write_text(path, json.dumps(payload, separators=(",", ":"), sort_keys=True) + "\n")


# The scan cache is a versioned envelope around the local-stats dict, so a
# corrupted or foreign-shaped file is a cache miss instead of a crash. today*
# fields only mean "today" on the day they were scanned, so a cache from
# another local date is a miss whatever its mtime says. The stats may be None
# when a scan found nothing: that answer is cached too, so a big empty
# directory is not walked again on the next run.
def read_cached_stats(cache_file: Path, max_age_seconds: float) -> tuple[bool, dict[str, Any] | None]:
    cached = read_fresh_json(cache_file, max_age_seconds)
    if not isinstance(cached, dict) or cached.get("schemaVersion") != 1:
        return False, None
    if cached.get("scanDate") != today_string():
        return False, None
    if "stats" not in cached:
        return False, None
    stats = cached["stats"]
    if stats is None:
        return True, None
    if not isinstance(stats, dict) or not all(key in stats for key in ("todayPrompts", "recentDays", "activeDates", "modelUsage")):
        return False, None
    return True, stats


def write_cached_stats(cache_file: Path, stats: dict[str, Any] | None) -> None:
    write_json(cache_file, {"schemaVersion": 1, "scanDate": today_string(), "stats": stats})


# ------------------------------------------------------------------- limits


# A cached percentage outlives the probe that measured it, but only until its
# window rolls over: once a window has reset, the figure describes a period
# that is over. A window with no reset time, or one that will not parse, is
# kept: an unreadable timestamp is no reason to throw away a real number.
def limit_window_open(entry: dict[str, Any], now: dt.datetime) -> bool:
    raw = str(entry.get("resetsAt") or "")
    if raw == "":
        return True
    resets_at = parse_iso_utc(raw)
    return resets_at is None or resets_at > now


def cached_limits(cache_file: Path) -> tuple[list[dict[str, Any]], float, dict[str, Any]]:
    """The last probe of record: its still-open windows, when it was fetched
    (epoch seconds, 0 when never), and the whole payload for extra fields."""
    cached = read_fresh_json(cache_file, float("inf"))
    if not isinstance(cached, dict):
        return [], 0.0, {}
    entries = cached.get("limits")
    if not isinstance(entries, list):
        return [], 0.0, cached
    now = dt.datetime.now(dt.timezone.utc)
    usable = [entry for entry in entries if isinstance(entry, dict) and limit_window_open(entry, now)]
    return usable, number(cached.get("fetchedAtMs")) / 1000, cached


def store_limits(cache_file: Path, limits: list[dict[str, Any]], **extra: Any) -> None:
    payload = {"fetchedAtMs": round(time.time() * 1000), "limits": limits}
    payload.update(extra)
    write_json(cache_file, payload)
