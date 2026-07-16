#!/usr/bin/env python3
"""Backend for the Noctalia Niri Outputs plugin."""

from __future__ import annotations

import argparse
from contextlib import contextmanager
import fcntl
import json
import os
from pathlib import Path
import re
import selectors
import shutil
import subprocess
import sys
import tempfile
import time
import uuid


TRANSFORMS = {
    "normal",
    "90",
    "180",
    "270",
    "flipped",
    "flipped-90",
    "flipped-180",
    "flipped-270",
}
MODE_RE = re.compile(r"^[1-9][0-9]*x[1-9][0-9]*@[0-9]+(?:\.[0-9]{1,3})?$")
PREVIEW_ID_RE = re.compile(r"^[0-9a-f]{32}$")
MANAGED_DISPLAY_INCLUDE = 'include "./cfg/display.kdl"'
PREVIEW_CONFIG_NAME = ".noctalia-niri-outputs-preview.kdl"
CONFIG_EVENT_TIMEOUT_SECONDS = 12.0
STARTING_GUARD_SECONDS = 30
ROLLBACK_RETRY_SECONDS = 1.0


class BackendError(RuntimeError):
    def __init__(
        self,
        message: str,
        *,
        error_key: str = "backend_errors.unexpected",
        error_args: dict[str, object] | None = None,
        cause: BackendError | None = None,
        preview_id: str | None = None,
    ):
        super().__init__(message)
        self.error_key = error_key
        self.error_args = error_args if error_args is not None else {"detail": message}
        self.error_cause = cause
        self.preview_id = preview_id


def error_descriptor(error: BackendError) -> dict[str, object]:
    descriptor: dict[str, object] = {"key": error.error_key, "args": error.error_args}
    if error.error_cause is not None:
        descriptor["cause"] = error_descriptor(error.error_cause)
    return descriptor


def emit(payload: dict[str, object], exit_code: int = 0) -> None:
    print(json.dumps(payload, separators=(",", ":"), ensure_ascii=False))
    raise SystemExit(exit_code)


def run_command(args: list[str], *, timeout: float = 8) -> subprocess.CompletedProcess[str]:
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired) as exc:
        command = " ".join(args[:2])
        raise BackendError(
            f"could not run {command}: {exc}",
            error_key="backend_errors.run_command",
            error_args={"command": command, "detail": str(exc)},
        ) from exc


def run_niri(*args: str, timeout: float = 8) -> subprocess.CompletedProcess[str]:
    result = run_command(["niri", *args], timeout=timeout)
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or f"exit {result.returncode}"
        command = "niri " + " ".join(args)
        raise BackendError(
            f"{command} failed: {detail}",
            error_key="backend_errors.niri_command_failed",
            error_args={"command": command, "detail": detail},
        )
    return result


def absolute_path(path: Path) -> Path:
    # Keep symlinks intact: relative Niri includes resolve from the path passed to Niri.
    return Path(os.path.abspath(path.expanduser()))


def normalize_transform(value: object) -> str:
    compact = str(value or "normal").strip().lower().replace("_", "-")
    compact = {
        "flipped90": "flipped-90",
        "flipped180": "flipped-180",
        "flipped270": "flipped-270",
    }.get(compact, compact)
    return compact if compact in TRANSFORMS else "normal"


def format_mode(mode: dict[str, object]) -> str:
    width = int(mode.get("width", 0))
    height = int(mode.get("height", 0))
    refresh = int(mode.get("refresh_rate", 0)) / 1000
    return f"{width}x{height}@{refresh:.3f}"


def normalize_outputs(raw: object) -> list[dict[str, object]]:
    if not isinstance(raw, dict):
        raise BackendError(
            "niri returned an unexpected output document",
            error_key="backend_errors.unexpected_output_document",
        )

    outputs: list[dict[str, object]] = []
    for connector, value in sorted(raw.items()):
        if not isinstance(value, dict):
            continue

        modes = [mode for mode in value.get("modes", []) if isinstance(mode, dict)]
        mode_values = [format_mode(mode) for mode in modes]
        mode_preferred = [mode.get("is_preferred") is True for mode in modes]
        current_index = value.get("current_mode")
        current_mode = None
        if isinstance(current_index, int) and 0 <= current_index < len(mode_values):
            current_mode = mode_values[current_index]
        if current_mode is None and mode_values:
            preferred_index = next(
                (index for index, mode in enumerate(modes) if mode.get("is_preferred") is True),
                0,
            )
            current_mode = mode_values[preferred_index]

        logical = value.get("logical")
        enabled = isinstance(logical, dict) and isinstance(current_index, int)
        logical_data = logical if isinstance(logical, dict) else {}
        description = " ".join(
            part
            for part in (
                str(value.get("make") or "").strip(),
                str(value.get("model") or "").strip(),
                str(value.get("serial") or "").strip(),
            )
            if part
        )
        outputs.append(
            {
                "name": str(value.get("name") or connector),
                "description": description or str(connector),
                "enabled": enabled,
                "mode": current_mode or "",
                "custom_mode": value.get("is_custom_mode") is True,
                "mode_values": mode_values,
                "mode_preferred": mode_preferred,
                "scale": float(logical_data.get("scale", 1.0)),
                "transform": normalize_transform(logical_data.get("transform")),
                "x": int(logical_data.get("x", 0)),
                "y": int(logical_data.get("y", 0)),
                "logical_width": int(logical_data.get("width", 0)),
                "logical_height": int(logical_data.get("height", 0)),
                "vrr_supported": value.get("vrr_supported") is True,
                "vrr_enabled": value.get("vrr_enabled") is True,
            }
        )
    return outputs


def query_outputs() -> list[dict[str, object]]:
    result = run_niri("msg", "-j", "outputs")
    try:
        raw = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        raise BackendError(
            f"niri returned invalid JSON: {exc}",
            error_key="backend_errors.invalid_json",
            error_args={"detail": str(exc)},
        ) from exc
    return normalize_outputs(raw)


def load_draft(path: Path) -> dict[str, object]:
    try:
        draft = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise BackendError(
            f"could not read output draft: {exc}",
            error_key="backend_errors.read_draft",
            error_args={"detail": str(exc)},
        ) from exc
    if not isinstance(draft, dict) or not isinstance(draft.get("outputs"), list):
        raise BackendError(
            "output draft must contain an outputs array",
            error_key="backend_errors.draft_outputs_array",
        )
    return draft


def validated_outputs(draft: dict[str, object]) -> list[dict[str, object]]:
    raw_outputs = draft.get("outputs")
    assert isinstance(raw_outputs, list)
    outputs: list[dict[str, object]] = []
    names: set[str] = set()
    enabled_count = 0

    for index, raw in enumerate(raw_outputs):
        if not isinstance(raw, dict):
            raise BackendError(
                f"output {index + 1} is not an object",
                error_key="backend_errors.output_not_object",
                error_args={"index": index + 1},
            )
        name = str(raw.get("name") or "")
        if not name or any(char in name for char in "\x00\r\n"):
            raise BackendError(
                f"output {index + 1} has an invalid connector name",
                error_key="backend_errors.invalid_connector_name",
                error_args={"index": index + 1},
            )
        if name in names:
            raise BackendError(
                f"duplicate output connector: {name}",
                error_key="backend_errors.duplicate_connector",
                error_args={"name": name},
            )
        names.add(name)

        enabled = raw.get("enabled") is True
        enabled_count += int(enabled)
        mode = str(raw.get("mode") or "")
        if enabled and not MODE_RE.fullmatch(mode):
            raise BackendError(
                f"{name}: invalid mode {mode!r}",
                error_key="backend_errors.invalid_mode",
                error_args={"name": name, "mode": mode},
            )
        try:
            scale = float(raw.get("scale", 1.0))
            x = int(raw.get("x", 0))
            y = int(raw.get("y", 0))
        except (TypeError, ValueError) as exc:
            raise BackendError(
                f"{name}: scale and position must be numeric",
                error_key="backend_errors.numeric_scale_position",
                error_args={"name": name},
            ) from exc
        if not 0.1 <= scale <= 10:
            raise BackendError(
                f"{name}: scale must be between 0.1 and 10",
                error_key="backend_errors.scale_range",
                error_args={"name": name},
            )

        normalized = dict(raw)
        normalized.update(
            {
                "name": name,
                "enabled": enabled,
                "mode": mode,
                "custom_mode": raw.get("custom_mode") is True,
                "scale": scale,
                "transform": normalize_transform(raw.get("transform")),
                "x": x,
                "y": y,
                "vrr_enabled": raw.get("vrr_enabled") is True,
                "vrr_supported": raw.get("vrr_supported") is True,
            }
        )
        outputs.append(normalized)

    if not outputs:
        raise BackendError("no outputs were found", error_key="backend_errors.no_outputs")
    if enabled_count == 0:
        raise BackendError(
            "at least one output must remain enabled",
            error_key="backend_errors.one_output_required",
        )
    return outputs


def render_kdl(outputs: list[dict[str, object]]) -> str:
    lines = [
        "// Managed by the Noctalia Niri Outputs plugin.",
        "// Hardware-specific; do not copy this file between machines.",
        "",
    ]
    for output in outputs:
        lines.append(f"output {json.dumps(str(output['name']), ensure_ascii=False)} {{")
        if output["enabled"] is not True:
            lines.append("    off")
        else:
            custom = " custom=true" if output.get("custom_mode") is True else ""
            lines.append(f"    mode{custom} {json.dumps(str(output['mode']))}")
            lines.append(f"    scale {float(output['scale']):g}")
            if output["transform"] != "normal":
                lines.append(f"    transform {json.dumps(str(output['transform']))}")
            lines.append(f"    position x={int(output['x'])} y={int(output['y'])}")
            if output.get("vrr_enabled") is True:
                lines.append("    variable-refresh-rate")
        lines.extend(("}", ""))
    return "\n".join(lines)


def runtime_dir() -> Path:
    base = Path(os.environ.get("XDG_RUNTIME_DIR") or tempfile.gettempdir())
    directory = base / f"noctalia-niri-outputs-{os.getuid()}"
    directory.mkdir(parents=True, exist_ok=True, mode=0o700)
    return directory


def token_path() -> Path:
    return runtime_dir() / "preview.json"


def lock_path() -> Path:
    return runtime_dir() / "preview.lock"


def preview_paths(preview_id: str, main_config: Path) -> tuple[Path, Path]:
    if not PREVIEW_ID_RE.fullmatch(preview_id):
        raise BackendError(
            "output preview state has an invalid identifier",
            error_key="backend_errors.invalid_preview_state",
        )
    if not main_config.is_absolute():
        raise BackendError(
            "output preview state does not contain an absolute Niri configuration path",
            error_key="backend_errors.invalid_preview_state",
        )
    return runtime_dir() / "preview-output.kdl", main_config.parent / PREVIEW_CONFIG_NAME


@contextmanager
def preview_lock():
    with lock_path().open("a", encoding="utf-8") as handle:
        fcntl.flock(handle.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(handle.fileno(), fcntl.LOCK_UN)


def atomic_write(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix=f".{path.name}.", dir=path.parent)
    temporary_path = Path(temporary)
    try:
        with os.fdopen(descriptor, "w", encoding="utf-8") as handle:
            handle.write(content)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary_path, path)
    finally:
        temporary_path.unlink(missing_ok=True)


def read_preview() -> dict[str, object] | None:
    try:
        data = json.loads(token_path().read_text(encoding="utf-8"))
    except FileNotFoundError:
        return None
    except (OSError, json.JSONDecodeError) as exc:
        raise BackendError(
            f"could not read output preview state: {exc}",
            error_key="backend_errors.read_preview_state",
            error_args={"detail": str(exc)},
        ) from exc
    if not isinstance(data, dict) or not PREVIEW_ID_RE.fullmatch(str(data.get("id") or "")):
        raise BackendError(
            "output preview state is invalid",
            error_key="backend_errors.invalid_preview_state",
        )
    return data


def write_preview(data: dict[str, object]) -> None:
    try:
        atomic_write(token_path(), json.dumps(data, separators=(",", ":")))
    except OSError as exc:
        raise BackendError(
            f"could not update output preview state: {exc}",
            error_key="backend_errors.update_preview_state",
            error_args={"detail": str(exc)},
            preview_id=str(data.get("id") or "") or None,
        ) from exc


def preview_status(data: dict[str, object] | None = None) -> dict[str, object]:
    if data is None:
        data = read_preview()
    if data is None:
        return {"active": False, "status": "inactive"}
    payload: dict[str, object] = {
        "active": True,
        "id": str(data["id"]),
        "status": str(data.get("status") or "unknown"),
    }
    expires = data.get("expires")
    if isinstance(expires, (int, float)):
        payload["expires"] = expires
    return payload


def query_state() -> dict[str, object]:
    with preview_lock():
        return {"ok": True, "outputs": query_outputs(), "preview": preview_status()}


def cleanup_preview(data: dict[str, object]) -> None:
    main_value = data.get("main_config")
    if not isinstance(main_value, str):
        raise BackendError(
            "output preview state does not contain the normal Niri configuration path",
            error_key="backend_errors.invalid_preview_state",
            preview_id=str(data["id"]),
        )
    preview_display, preview_config = preview_paths(str(data["id"]), Path(main_value))
    try:
        preview_display.unlink(missing_ok=True)
        preview_config.unlink(missing_ok=True)
        current = read_preview()
        if current is not None and current.get("id") == data.get("id"):
            token_path().unlink(missing_ok=True)
    except OSError as exc:
        raise BackendError(
            f"could not remove output preview files: {exc}",
            error_key="backend_errors.remove_preview_state",
            error_args={"detail": str(exc)},
            preview_id=str(data["id"]),
        ) from exc


def validate_config(path: Path) -> None:
    if not path.is_file():
        raise BackendError(
            f"Niri configuration does not exist: {path}",
            error_key="backend_errors.config_missing",
            error_args={"path": str(path)},
        )
    result = run_command(["niri", "validate", "-c", str(path)], timeout=10)
    if result.returncode != 0:
        detail = result.stderr.strip() or result.stdout.strip() or "validation failed"
        raise BackendError(
            f"Niri configuration is invalid: {detail}",
            error_key="backend_errors.config_invalid",
            error_args={"detail": detail},
        )


def wait_for_config_loaded(process: subprocess.Popen[bytes], buffer: bytearray) -> bool:
    assert process.stdout is not None
    deadline = time.monotonic() + CONFIG_EVENT_TIMEOUT_SECONDS
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    try:
        while True:
            while b"\n" in buffer:
                raw_line, _, remainder = buffer.partition(b"\n")
                buffer[:] = remainder
                try:
                    event = json.loads(raw_line)
                except (UnicodeDecodeError, json.JSONDecodeError):
                    continue
                loaded = event.get("ConfigLoaded") if isinstance(event, dict) else None
                if isinstance(loaded, dict) and isinstance(loaded.get("failed"), bool):
                    return loaded["failed"]

            remaining = deadline - time.monotonic()
            if remaining <= 0 or not selector.select(remaining):
                raise BackendError(
                    "timed out waiting for Niri to finish loading its configuration",
                    error_key="backend_errors.config_load_timeout",
                )
            try:
                chunk = os.read(process.stdout.fileno(), 65536)
            except BlockingIOError:
                continue
            if not chunk:
                raise BackendError(
                    "Niri event stream ended before configuration loading completed",
                    error_key="backend_errors.config_event_stream_ended",
                )
            buffer.extend(chunk)
    finally:
        selector.close()


def stop_process(process: subprocess.Popen[bytes]) -> None:
    if process.poll() is not None:
        return
    process.terminate()
    try:
        process.wait(timeout=1)
    except subprocess.TimeoutExpired:
        process.kill()
        process.wait(timeout=1)


def load_config(path: Path, *, validate: bool = True) -> None:
    path = absolute_path(path)
    if validate:
        validate_config(path)
    try:
        stream = subprocess.Popen(
            ["niri", "msg", "-j", "event-stream"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            close_fds=True,
        )
    except OSError as exc:
        raise BackendError(
            f"could not start the Niri configuration event stream: {exc}",
            error_key="backend_errors.config_event_stream_start",
            error_args={"detail": str(exc)},
        ) from exc

    assert stream.stdout is not None
    os.set_blocking(stream.stdout.fileno(), False)
    buffer = bytearray()
    try:
        wait_for_config_loaded(stream, buffer)
        run_niri("msg", "action", "load-config-file", "--path", str(path))
        if wait_for_config_loaded(stream, buffer):
            raise BackendError(
                "Niri rejected the configuration",
                error_key="backend_errors.config_load_rejected",
            )
    finally:
        stop_process(stream)


def preview_main_content(preview_display: Path, main_config: Path) -> str:
    try:
        content = main_config.read_text(encoding="utf-8")
    except OSError as exc:
        raise BackendError(
            f"could not read the normal Niri configuration: {exc}",
            error_key="backend_errors.read_main_config",
            error_args={"detail": str(exc)},
        ) from exc

    lines = content.splitlines(keepends=True)
    matches = [index for index, line in enumerate(lines) if line.strip() == MANAGED_DISPLAY_INCLUDE]
    if len(matches) != 1:
        raise BackendError(
            f"normal Niri configuration must contain exactly one {MANAGED_DISPLAY_INCLUDE!r} line",
            error_key="backend_errors.managed_display_include",
        )

    index = matches[0]
    newline = "\n" if lines[index].endswith("\n") else ""
    lines[index] = f"include {json.dumps(str(preview_display), ensure_ascii=False)}{newline}"
    return "".join(lines)


def spawn_watchdog(preview_id: str) -> None:
    try:
        subprocess.Popen(
            [sys.executable, str(Path(__file__).resolve()), "watchdog", preview_id],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
            close_fds=True,
        )
    except OSError as exc:
        raise BackendError(
            f"could not start the output rollback watchdog: {exc}",
            error_key="backend_errors.watchdog_start",
            error_args={"detail": str(exc)},
            preview_id=preview_id,
        ) from exc


def require_preview(preview_id: str) -> dict[str, object]:
    data = read_preview()
    if data is None:
        raise BackendError(
            "output preview is no longer active",
            error_key="backend_errors.preview_inactive",
            preview_id=preview_id,
        )
    if data.get("id") != preview_id:
        raise BackendError(
            "a different output preview is active",
            error_key="backend_errors.different_preview_active",
            preview_id=preview_id,
        )
    return data


def restore_preview(data: dict[str, object]) -> None:
    main_value = data.get("main_config")
    if not isinstance(main_value, str) or not Path(main_value).is_absolute():
        raise BackendError(
            "output preview state does not contain the normal Niri configuration path",
            error_key="backend_errors.invalid_preview_state",
            preview_id=str(data["id"]),
        )
    load_config(Path(main_value))
    cleanup_preview(data)


def preview(
    draft_path: Path,
    display_config: Path,
    main_config: Path,
    timeout: int,
) -> dict[str, object]:
    outputs = validated_outputs(load_draft(draft_path))
    display_config = absolute_path(display_config)
    main_config = absolute_path(main_config)
    timeout = max(5, min(timeout, 60))

    with preview_lock():
        existing = read_preview()
        if existing is not None:
            restore_preview(existing)

        preview_id = uuid.uuid4().hex
        preview_display, preview_config = preview_paths(preview_id, main_config)
        preview_content = preview_main_content(preview_display, main_config)
        try:
            atomic_write(preview_display, render_kdl(outputs))
            atomic_write(preview_config, preview_content)
        except OSError as exc:
            preview_display.unlink(missing_ok=True)
            preview_config.unlink(missing_ok=True)
            raise BackendError(
                f"could not create the temporary output preview: {exc}",
                error_key="backend_errors.create_preview_files",
                error_args={"detail": str(exc)},
            ) from exc

        try:
            validate_config(preview_config)
        except BackendError:
            preview_display.unlink(missing_ok=True)
            preview_config.unlink(missing_ok=True)
            raise
        data: dict[str, object] = {
            "id": preview_id,
            "status": "starting",
            "started": int(time.time()),
            "expires": int(time.time()) + STARTING_GUARD_SECONDS,
            "main_config": str(main_config),
            "display_config": str(display_config),
        }
        try:
            write_preview(data)
        except BackendError:
            preview_display.unlink(missing_ok=True)
            preview_config.unlink(missing_ok=True)
            raise
        try:
            spawn_watchdog(preview_id)
            load_config(preview_config, validate=False)
        except BackendError as apply_error:
            data["status"] = "restoring"
            try:
                write_preview(data)
                restore_preview(data)
            except BackendError as restore_error:
                raise BackendError(
                    f"{apply_error}; {restore_error}",
                    error_key="backend_errors.preview_restore_pending",
                    cause=restore_error,
                    preview_id=preview_id,
                ) from apply_error
            raise apply_error

        data["status"] = "active"
        data["expires"] = int(time.time()) + timeout
        try:
            write_preview(data)
        except BackendError as state_error:
            try:
                restore_preview(data)
            except BackendError as restore_error:
                raise BackendError(
                    f"{state_error}; {restore_error}",
                    error_key="backend_errors.preview_restore_pending",
                    cause=restore_error,
                    preview_id=preview_id,
                ) from state_error
            raise state_error

    return {
        "ok": True,
        "preview_id": preview_id,
        "timeout": timeout,
        "expires": data["expires"],
        "preview": preview_status(data),
    }


def watchdog(preview_id: str) -> None:
    while True:
        delay = ROLLBACK_RETRY_SECONDS
        with preview_lock():
            data = read_preview()
            if data is None or data.get("id") != preview_id:
                return
            expires = data.get("expires")
            if data.get("status") in {"starting", "active"} and isinstance(expires, (int, float)):
                remaining = expires - time.time()
                if remaining > 0:
                    delay = min(remaining, 0.25)
                else:
                    data["status"] = "restoring"
                    try:
                        write_preview(data)
                    except BackendError:
                        pass
            if data.get("status") == "restoring":
                try:
                    restore_preview(data)
                except BackendError:
                    delay = ROLLBACK_RETRY_SECONDS
                else:
                    return
        time.sleep(max(delay, 0.05))


def restore_display_file(display_config: Path, backup: Path, had_existing: bool) -> None:
    try:
        if had_existing:
            atomic_write(display_config, backup.read_text(encoding="utf-8"))
        else:
            display_config.unlink(missing_ok=True)
    except OSError as exc:
        raise BackendError(
            f"could not restore the prior Niri output configuration: {exc}",
            error_key="backend_errors.restore_config_file",
            error_args={"detail": str(exc)},
        ) from exc


def keep(preview_id: str) -> dict[str, object]:
    with preview_lock():
        data = require_preview(preview_id)
        expires = data.get("expires")
        if data.get("status") != "active" or not isinstance(expires, (int, float)):
            raise BackendError(
                "output preview is not ready to keep",
                error_key="backend_errors.preview_not_active",
                preview_id=preview_id,
            )
        if expires <= time.time():
            try:
                restore_preview(data)
            except BackendError as restore_error:
                raise BackendError(
                    f"output preview expired; {restore_error}",
                    error_key="backend_errors.preview_restore_pending",
                    cause=restore_error,
                    preview_id=preview_id,
                ) from restore_error
            raise BackendError(
                "output preview expired",
                error_key="backend_errors.preview_expired",
                preview_id=preview_id,
            )

        display_value = data.get("display_config")
        main_value = data.get("main_config")
        if not isinstance(display_value, str) or not isinstance(main_value, str):
            raise BackendError(
                "output preview state is invalid",
                error_key="backend_errors.invalid_preview_state",
                preview_id=preview_id,
            )
        display_config = Path(display_value)
        main_config = Path(main_value)
        preview_display, _ = preview_paths(preview_id, main_config)
        try:
            content = preview_display.read_text(encoding="utf-8")
        except OSError as exc:
            raise BackendError(
                f"could not read the temporary output preview: {exc}",
                error_key="backend_errors.read_preview_file",
                error_args={"detail": str(exc)},
                preview_id=preview_id,
            ) from exc

        display_config.parent.mkdir(parents=True, exist_ok=True)
        backup = display_config.with_suffix(display_config.suffix + ".previous")
        had_existing = display_config.exists()
        try:
            if had_existing:
                shutil.copy2(display_config, backup)
            atomic_write(display_config, content)
        except OSError as exc:
            raise BackendError(
                f"could not install the Niri output configuration: {exc}",
                error_key="backend_errors.install_config_file",
                error_args={"detail": str(exc)},
                preview_id=preview_id,
            ) from exc

        try:
            load_config(main_config)
        except BackendError as load_error:
            restore_display_file(display_config, backup, had_existing)
            try:
                load_config(main_config)
                cleanup_preview(data)
            except BackendError as restore_error:
                raise BackendError(
                    f"{load_error}; {restore_error}",
                    error_key="backend_errors.preview_restore_pending",
                    cause=restore_error,
                    preview_id=preview_id,
                ) from load_error
            raise load_error

        cleanup_preview(data)
        return {
            "ok": True,
            "config_path": str(display_config),
            "backup_path": str(backup) if had_existing else "",
        }


def revert(preview_id: str) -> dict[str, object]:
    with preview_lock():
        data = read_preview()
        if data is None:
            return {"ok": True, "already_reverted": True}
        if data.get("id") != preview_id:
            raise BackendError(
                "a different output preview is active",
                error_key="backend_errors.different_preview_active",
                preview_id=preview_id,
            )
        data["status"] = "restoring"
        try:
            write_preview(data)
        except BackendError:
            pass
        try:
            restore_preview(data)
        except BackendError as restore_error:
            raise BackendError(
                str(restore_error),
                error_key="backend_errors.preview_restore_pending",
                cause=restore_error,
                preview_id=preview_id,
            ) from restore_error
        return {"ok": True}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    subparsers = parser.add_subparsers(dest="command", required=True)
    subparsers.add_parser("query")

    preview_parser = subparsers.add_parser("preview")
    preview_parser.add_argument("--draft", type=Path, required=True)
    preview_parser.add_argument("--display-config", type=Path, required=True)
    preview_parser.add_argument("--main-config", type=Path, required=True)
    preview_parser.add_argument("--timeout", type=int, default=15)

    keep_parser = subparsers.add_parser("keep")
    keep_parser.add_argument("--preview-id", required=True)

    revert_parser = subparsers.add_parser("revert")
    revert_parser.add_argument("--preview-id", required=True)

    watchdog_parser = subparsers.add_parser("watchdog")
    watchdog_parser.add_argument("preview_id")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    try:
        if args.command == "query":
            emit(query_state())
        if args.command == "preview":
            emit(preview(args.draft, args.display_config, args.main_config, args.timeout))
        if args.command == "keep":
            emit(keep(args.preview_id))
        if args.command == "revert":
            emit(revert(args.preview_id))
        if args.command == "watchdog":
            watchdog(args.preview_id)
            raise SystemExit(0)
    except BackendError as exc:
        payload: dict[str, object] = {
            "ok": False,
            "error": str(exc),
            "error_localization": error_descriptor(exc),
        }
        expected_preview_id = exc.preview_id
        if expected_preview_id is None and hasattr(args, "preview_id"):
            expected_preview_id = args.preview_id
        if expected_preview_id:
            try:
                payload["preview"] = preview_status()
            except BackendError:
                pass
        emit(payload, 1)


if __name__ == "__main__":
    main()
