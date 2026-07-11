"""Entrypoint for the ZZ Fedora Anaconda D-Bus service."""

from pyanaconda.modules.common import init

init()

from org_zz_fedora.service.zz_fedora import ZZFedora  # noqa: E402

service = ZZFedora()
service.run()
