"""Remote runtime refresh helpers for the Anaconda add-on."""

import os
import subprocess
from pathlib import Path

EMBEDDED_RUNTIME_LOADER = Path("/run/install/repo/zz-fedora/iso/lib/runtime-loader.sh")
REMOTE_RUNTIME_DIR = Path("/run/zz-fedora/repository")
THREAD_RUNTIME_REFRESH = "AnaZZFedoraRuntimeRefresh"


def runtime_is_ready():
    """Return whether the refreshed runtime has its required entrypoints."""

    return (
        (REMOTE_RUNTIME_DIR / "install.sh").is_file()
        and (REMOTE_RUNTIME_DIR / "catalog/units").is_dir()
        and (REMOTE_RUNTIME_DIR / "lib/catalog.py").is_file()
    )


def payload_proxy_url(payload):
    """Return the proxy configured for Anaconda's active URL source."""

    from pyanaconda.core.constants import SOURCE_TYPE_URL
    from pyanaconda.modules.common.structures.payload import RepoConfigurationData

    source_proxy = payload.get_source_proxy()
    if source_proxy.Type != SOURCE_TYPE_URL:
        return ""
    return RepoConfigurationData.from_structure(source_proxy.Configuration).proxy


def refresh_runtime(proxy_url="", force=False):
    """Fetch and validate the remote runtime once networking is available."""

    if runtime_is_ready() and not force:
        return

    environment = os.environ.copy()
    if proxy_url:
        environment["http_proxy"] = proxy_url
        environment["https_proxy"] = proxy_url

    try:
        result = subprocess.run(
            [str(EMBEDDED_RUNTIME_LOADER)],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            env=environment,
            text=True,
            timeout=360,
        )
    except (OSError, subprocess.SubprocessError) as error:
        detail = getattr(error, "stderr", "") or str(error)
        if isinstance(detail, bytes):
            detail = detail.decode("utf-8", errors="replace")
        detail = detail.strip().splitlines()[-1] if detail.strip() else str(error)
        raise RuntimeError("Could not refresh the latest choices: {}".format(detail))

    if not runtime_is_ready():
        detail = result.stderr.strip().splitlines()
        detail = detail[-1] if detail else "runtime validation failed"
        raise RuntimeError("Could not refresh the latest choices: {}".format(detail))
