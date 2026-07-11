"""D-Bus service for the ZZ Fedora Anaconda add-on."""

import logging

from pyanaconda.core.configuration.anaconda import conf
from pyanaconda.core.dbus import DBus
from pyanaconda.modules.common.base import KickstartService
from pyanaconda.modules.common.containers import TaskContainer

from org_zz_fedora.constants import ZZ_FEDORA
from org_zz_fedora.service.installation import ZZFedoraInstallationTask
from org_zz_fedora.service.zz_fedora_interface import (
    ZZFedoraInterface,
)

log = logging.getLogger(__name__)


class ZZFedora(KickstartService):
    """The ZZ Fedora D-Bus service."""

    def publish(self):
        """Publish the module."""

        TaskContainer.set_namespace(ZZ_FEDORA.namespace)
        DBus.publish_object(
            ZZ_FEDORA.object_path,
            ZZFedoraInterface(self),
        )
        DBus.register_service(ZZ_FEDORA.service_name)

    def install_with_tasks(self):
        """Return installation tasks for Anaconda's configuration queue."""

        log.debug("Creating ZZ Fedora installation task.")
        return [ZZFedoraInstallationTask(conf.target.system_root)]
