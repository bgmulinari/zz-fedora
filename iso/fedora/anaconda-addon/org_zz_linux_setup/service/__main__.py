"""Entrypoint for the ZZ Linux Setup Anaconda D-Bus service."""

from pyanaconda.modules.common import init

init()

from org_zz_linux_setup.service.zz_linux_setup import ZZLinuxSetup  # noqa: E402

service = ZZLinuxSetup()
service.run()
