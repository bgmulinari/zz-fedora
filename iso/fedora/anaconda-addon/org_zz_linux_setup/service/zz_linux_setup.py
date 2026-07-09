"""D-Bus service for the ZZ Linux Setup Anaconda add-on."""

import logging

from pyanaconda.core.configuration.anaconda import conf
from pyanaconda.core.dbus import DBus
from pyanaconda.modules.common.base import KickstartService
from pyanaconda.modules.common.containers import TaskContainer

from org_zz_linux_setup.constants import ZZ_LINUX_SETUP
from org_zz_linux_setup.service.installation import ZZLinuxSetupInstallationTask
from org_zz_linux_setup.service.zz_linux_setup_interface import (
    ZZLinuxSetupInterface,
)

log = logging.getLogger(__name__)


class ZZLinuxSetup(KickstartService):
    """The ZZ Linux Setup D-Bus service."""

    def publish(self):
        """Publish the module."""

        TaskContainer.set_namespace(ZZ_LINUX_SETUP.namespace)
        DBus.publish_object(
            ZZ_LINUX_SETUP.object_path,
            ZZLinuxSetupInterface(self),
        )
        DBus.register_service(ZZ_LINUX_SETUP.service_name)

    def install_with_tasks(self):
        """Return installation tasks for Anaconda's configuration queue."""

        log.debug("Creating ZZ Linux Setup installation task.")
        return [ZZLinuxSetupInstallationTask(conf.target.system_root)]
