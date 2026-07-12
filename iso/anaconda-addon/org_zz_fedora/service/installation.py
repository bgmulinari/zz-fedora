"""Installation task for the ZZ Fedora Anaconda add-on."""

import logging
import os
import re
import selectors
import shlex
import shutil
import subprocess
import time
from pathlib import Path

from pyanaconda.modules.common.task import Task

from org_zz_fedora.constants import SELECTION_FILE

log = logging.getLogger(__name__)

SOURCE_REPO_DIR = Path("/run/install/repo/zz-fedora")
TARGET_SELECTION_PATH = Path("root/zz-fedora-install-selected")
TASK_LOG_PATH = Path("root/zz-fedora-kickstart.log")
RUN_SCRIPT_PATH = Path("root/zz-fedora-run-install.sh")

SAFE_ID_RE = re.compile(r"^[A-Za-z0-9_.-]+$")
SAFE_LIST_RE = re.compile(r"^[A-Za-z0-9_.-]*(,[A-Za-z0-9_.-]+)*$")
ANSI_RE = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
DNF_TRANSACTION_RE = re.compile(
    r"^\[\s*[0-9]+/[0-9]+\]\s+"
    r"(Installing|Upgrading|Downgrading|Reinstalling|Removing|Verifying|Cleanup)"
)


class ZZFedoraInstallationTask(Task):
    """Run the bundled desktop setup as a first-class Anaconda task."""

    def __init__(self, sysroot):
        super().__init__()
        self._sysroot = Path(sysroot)
        self._last_progress_message = ""
        self._last_output_detail = ""
        self._last_output_reported_at = 0
        self._progress_position = 0
        self._current_step_label = ""
        self._current_step_current = ""
        self._current_step_total = ""

    @property
    def name(self):
        return "Install ZZ Fedora"

    def run(self):
        """Copy the repo into the target system and run the installer."""

        self._report("Preparing ZZ Fedora")
        if not SOURCE_REPO_DIR.is_dir():
            raise RuntimeError(
                "Bundled repository not found at {}".format(SOURCE_REPO_DIR)
            )

        user = self._find_target_user()
        target_home = Path(user["home"])
        target_home_path = self._target_path(target_home)
        target_repo_dir = target_home / "zz-fedora"
        target_repo_path = self._target_path(target_repo_dir)
        state_dir = target_home / ".local/state/zz-fedora"
        cache_dir = target_home / ".cache/zz-fedora"
        config_dir = target_home / ".config/zz-fedora"
        log_dir = state_dir / "logs"
        progress_file = log_dir / "install-progress.tsv"
        progress_path = self._target_path(progress_file)

        self._copy_repo(target_repo_path, user["uid"], user["gid"])
        self._prepare_state_dirs(target_home_path, user["uid"], user["gid"])
        selection_lines = self._read_selection_lines()
        self._write_target_selection(selection_lines)
        self._write_selection_config(
            selection_lines,
            self._target_path(config_dir / "selections.conf"),
            user,
        )
        self._write_runner_script(
            target_repo_dir=target_repo_dir,
            state_dir=state_dir,
            cache_dir=cache_dir,
            config_dir=config_dir,
            log_dir=log_dir,
            progress_file=progress_file,
            target_user=user["name"],
        )

        self._report("Starting ZZ Fedora for {}".format(user["name"]))
        self._run_installer(progress_path)
        self._cleanup_runtime_files()
        self._report("ZZ Fedora complete")

    def _report(self, message):
        if message == self._last_progress_message:
            return
        self._last_progress_message = message
        log.info(message)
        self.report_progress(message)

    def _target_path(self, path):
        path = Path(path)
        if path.is_absolute():
            return self._sysroot / str(path).lstrip("/")
        return self._sysroot / path

    def _find_target_user(self):
        passwd_path = self._target_path("etc/passwd")
        group_path = self._target_path("etc/group")
        groups = {}

        with open(group_path, "r", encoding="utf-8") as group_file:
            for line in group_file:
                fields = line.rstrip("\n").split(":")
                if len(fields) >= 3:
                    try:
                        groups[int(fields[2])] = fields[0]
                    except ValueError:
                        continue

        with open(passwd_path, "r", encoding="utf-8") as passwd_file:
            for line in passwd_file:
                fields = line.rstrip("\n").split(":")
                if len(fields) < 7:
                    continue

                name, _password, uid, gid, _gecos, home, shell = fields[:7]
                try:
                    uid_value = int(uid)
                    gid_value = int(gid)
                except ValueError:
                    continue

                if (
                    1000 <= uid_value < 60000
                    and home.startswith("/home/")
                    and not shell.endswith(("nologin", "false"))
                ):
                    return {
                        "name": name,
                        "uid": uid_value,
                        "gid": gid_value,
                        "group": groups.get(gid_value, name),
                        "home": home,
                    }

        raise RuntimeError(
            "No installer-created regular user was found. Create a regular "
            "user in Anaconda before starting installation."
        )

    def _copy_repo(self, target_repo_path, uid, gid):
        self._report("Copying ZZ Fedora into the target system")
        target_repo_path.parent.mkdir(parents=True, exist_ok=True)
        if target_repo_path.exists() or target_repo_path.is_symlink():
            if target_repo_path.is_dir() and not target_repo_path.is_symlink():
                shutil.rmtree(target_repo_path)
            else:
                target_repo_path.unlink()
        shutil.copytree(SOURCE_REPO_DIR, target_repo_path, symlinks=True)
        self._chown_tree(target_repo_path, uid, gid)

    def _prepare_state_dirs(self, target_home_path, uid, gid):
        for rel_path in (
            ".local",
            ".local/state",
            ".local/share",
            ".cache",
            ".config",
        ):
            (target_home_path / rel_path).mkdir(parents=True, exist_ok=True)

        for rel_path in (".local", ".cache", ".config"):
            self._chown_tree(target_home_path / rel_path, uid, gid)

    def _read_selection_lines(self):
        selection_path = Path(SELECTION_FILE)
        if not selection_path.exists():
            self._report("Using base desktop defaults")
            return ["selected=1\n"]

        with open(selection_path, "r", encoding="utf-8") as selection_file:
            lines = selection_file.readlines()
        return lines or ["selected=1\n"]

    def _write_target_selection(self, selection_lines):
        target_selection = self._target_path(TARGET_SELECTION_PATH)
        target_selection.parent.mkdir(parents=True, exist_ok=True)
        with open(target_selection, "w", encoding="utf-8") as state_file:
            state_file.writelines(selection_lines)
            if selection_lines and not selection_lines[-1].endswith("\n"):
                state_file.write("\n")

    def _write_selection_config(self, selection_lines, destination, user):
        preferred_browser_seen = False
        destination.parent.mkdir(parents=True, exist_ok=True)

        with open(destination, "w", encoding="utf-8") as state_file:
            state_file.write("target_user={}\n".format(user["name"]))
            state_file.write("desktop_app_profile=full\n")

            for raw_line in selection_lines:
                line = raw_line.strip()
                if not line or "=" not in line:
                    continue

                key, value = line.split("=", 1)
                if key == "preferred_browser":
                    preferred_browser_seen = True
                    if SAFE_ID_RE.match(value):
                        state_file.write("preferred_browser={}\n".format(value))
                elif key.startswith("select."):
                    category = key[len("select.") :]
                    if SAFE_ID_RE.match(category) and SAFE_LIST_RE.match(value):
                        state_file.write("select.{}={}\n".format(category, value))

            if not preferred_browser_seen:
                state_file.write("preferred_browser=\n")

        os.chown(destination, user["uid"], user["gid"])

    def _write_runner_script(
        self,
        target_repo_dir,
        state_dir,
        cache_dir,
        config_dir,
        log_dir,
        progress_file,
        target_user,
    ):
        script_path = self._target_path(RUN_SCRIPT_PATH)
        script_path.parent.mkdir(parents=True, exist_ok=True)

        script = """#!/usr/bin/env bash
set -Eeuo pipefail

export STATE_DIR={state_dir}
export CACHE_DIR={cache_dir}
export CONFIG_DIR={config_dir}
export LOG_DIR={log_dir}
export STATE_OWNER_USER={target_user}
export TARGET_USER={target_user}
export DESKTOP_APP_PROFILE=full
export ZZ_INSTALLER_DEFER_START_SERVICES=1
export ZZ_INSTALLER_POST_TIMEOUT_SECONDS="${{ZZ_INSTALLER_POST_TIMEOUT_SECONDS:-14400}}"
export ZZ_COMMAND_TIMEOUT_SECONDS="${{ZZ_COMMAND_TIMEOUT_SECONDS:-3600}}"
export ZZ_COMMAND_TIMEOUT_KILL_AFTER="${{ZZ_COMMAND_TIMEOUT_KILL_AFTER:-60s}}"
export ZZ_INSTALL_PROGRESS_FILE={progress_file}
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY XDG_RUNTIME_DIR DBUS_SESSION_BUS_ADDRESS XDG_CURRENT_DESKTOP DESKTOP_SESSION
if [[ -r /etc/locale.conf ]]; then
  source /etc/locale.conf
fi
case "${{LANG:-}}" in
  *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) ;;
  *) LANG=C.UTF-8 ;;
esac
case "${{LC_ALL:-}}" in
  *[Uu][Tt][Ff]-8*|*[Uu][Tt][Ff]8*) ;;
  *) LC_ALL="$LANG" ;;
esac
export LANG LC_ALL

cd {target_repo_dir}
exec timeout --foreground --kill-after=60s "$ZZ_INSTALLER_POST_TIMEOUT_SECONDS" \\
  ./install.sh install --yes --use-saved --desktop-app-profile full --no-tui --target-user "$TARGET_USER"
""".format(
            state_dir=shlex.quote(str(state_dir)),
            cache_dir=shlex.quote(str(cache_dir)),
            config_dir=shlex.quote(str(config_dir)),
            log_dir=shlex.quote(str(log_dir)),
            target_user=shlex.quote(target_user),
            progress_file=shlex.quote(str(progress_file)),
            target_repo_dir=shlex.quote(str(target_repo_dir)),
        )

        with open(script_path, "w", encoding="utf-8") as runner:
            runner.write(script)
        os.chmod(script_path, 0o755)

    def _run_installer(self, progress_path):
        task_log_path = self._target_path(TASK_LOG_PATH)
        task_log_path.parent.mkdir(parents=True, exist_ok=True)
        command = [
            "chroot",
            str(self._sysroot),
            "/usr/bin/bash",
            "/" + str(RUN_SCRIPT_PATH),
        ]

        with open(task_log_path, "w", encoding="utf-8") as task_log:
            task_log.write("[zz-fedora] Starting Anaconda task\n")
            task_log.flush()
            process = subprocess.Popen(
                command,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                bufsize=1,
            )

            selector = selectors.DefaultSelector()
            if process.stdout is not None:
                selector.register(process.stdout, selectors.EVENT_READ)

            try:
                while process.poll() is None:
                    for key, _event in selector.select(timeout=1):
                        line = key.fileobj.readline()
                        if line:
                            task_log.write(line)
                            task_log.flush()
                            self._report_process_line(line)
                        else:
                            selector.unregister(key.fileobj)
                    self._consume_progress(progress_path, task_log)

                if process.stdout is not None:
                    for line in process.stdout:
                        task_log.write(line)
                        task_log.flush()
                        self._report_process_line(line)

                self._consume_progress(progress_path, task_log)
            finally:
                selector.close()

            if process.returncode != 0:
                self._report("ZZ Fedora failed")
                raise RuntimeError(
                    "ZZ Fedora failed with exit code {}. Check {} and "
                    "the target user's zz-fedora logs.".format(
                        process.returncode,
                        "/" + str(TASK_LOG_PATH),
                    )
                )

    def _consume_progress(self, progress_path, task_log):
        if not progress_path.exists():
            return

        with open(progress_path, "r", encoding="utf-8") as progress_file:
            progress_file.seek(self._progress_position)
            lines = progress_file.readlines()
            self._progress_position = progress_file.tell()

        for raw_line in lines:
            parts = raw_line.rstrip("\n").split("\t", 5)
            if len(parts) != 6:
                continue

            _timestamp, status, current, total, label, detail = parts
            if label and label != "ZZ Fedora":
                self._current_step_label = label
                self._current_step_current = current
                self._current_step_total = total
            message = self._format_progress(status, current, total, label, detail)
            task_log.write("[zz-fedora-progress] {}\n".format(message))
            task_log.flush()
            self._report(message)

    def _report_process_line(self, line):
        detail = self._progress_detail_from_output(line)
        if not detail:
            return

        now = time.monotonic()
        if detail == self._last_output_detail and now - self._last_output_reported_at < 2:
            return
        if now - self._last_output_reported_at < 1:
            return

        self._last_output_detail = detail
        self._last_output_reported_at = now
        self._report("{} - {}".format(self._current_step_prefix(), detail))

    def _current_step_prefix(self):
        if self._current_step_label:
            if self._current_step_current and self._current_step_total:
                return "ZZ Fedora ({}/{}): {}".format(
                    self._current_step_current,
                    self._current_step_total,
                    self._current_step_label,
                )
            return "ZZ Fedora: {}".format(self._current_step_label)
        return "ZZ Fedora"

    def _progress_detail_from_output(self, line):
        line = ANSI_RE.sub("", line.replace("\r", "\n")).strip()
        if not line:
            return ""
        if len(line) > 140:
            line = line[:137] + "..."

        if DNF_TRANSACTION_RE.match(line):
            return line

        known_messages = {
            "Dependencies resolved.": "Resolved package dependencies",
            "Downloading Packages:": "Downloading packages",
            "Downloading Packages": "Downloading packages",
            "Running transaction check": "Checking package transaction",
            "Transaction check succeeded.": "Package transaction check succeeded",
            "Running transaction test": "Testing package transaction",
            "Transaction test succeeded.": "Package transaction test succeeded",
            "Running transaction": "Running package transaction",
            "Complete!": "Package transaction complete",
        }
        if line in known_messages:
            return known_messages[line]

        prefixes = (
            ("Package ", "Checking package state"),
            ("Installing:", "Preparing package install list"),
            ("Installing dependencies:", "Preparing package dependencies"),
            ("Installing weak dependencies:", "Preparing weak package dependencies"),
            ("Upgrading:", "Preparing package upgrade list"),
            ("Removing:", "Preparing package removal list"),
            ("Transaction Summary", "Reviewing package transaction"),
            ("Looking for matches", "Looking for Flatpak matches"),
            ("Required runtime", "Resolving Flatpak runtime"),
            ("Installing ", line),
            ("Updating ", line),
        )
        for prefix, detail in prefixes:
            if line.startswith(prefix):
                return detail

        return ""

    def _format_progress(self, status, current, total, label, detail):
        if label == "ZZ Fedora" and status == "done":
            return "ZZ Fedora complete"
        if label == "ZZ Fedora" and status == "failed":
            return "ZZ Fedora failed"

        step_suffix = ""
        if current and total and current != "0":
            step_suffix = " ({}/{})".format(current, total)

        verb = {
            "running": "Running",
            "done": "Completed",
            "skipped": "Skipped",
            "failed": "Failed",
        }.get(status, status.title())

        if status == "running" and detail:
            return "ZZ Fedora{}: {} - {}".format(step_suffix, label, detail)

        return "ZZ Fedora{}: {} {}".format(step_suffix, verb, label)

    def _cleanup_runtime_files(self):
        for path in (
            self._target_path(RUN_SCRIPT_PATH),
            self._target_path(TARGET_SELECTION_PATH),
        ):
            try:
                path.unlink()
            except FileNotFoundError:
                pass

    def _chown_tree(self, path, uid, gid):
        try:
            os.lchown(path, uid, gid)
        except FileNotFoundError:
            return

        if not path.is_dir() or path.is_symlink():
            return

        for root, dirs, files in os.walk(path):
            for name in dirs + files:
                child = Path(root) / name
                try:
                    os.lchown(child, uid, gid)
                except FileNotFoundError:
                    continue
