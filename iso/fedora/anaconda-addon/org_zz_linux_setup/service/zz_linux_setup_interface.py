"""D-Bus interface for the ZZ Linux Setup Anaconda add-on service."""

from dasbus.server.interface import dbus_interface

from pyanaconda.modules.common.base import KickstartModuleInterface

from org_zz_linux_setup.constants import ZZ_LINUX_SETUP


@dbus_interface(ZZ_LINUX_SETUP.interface_name)
class ZZLinuxSetupInterface(KickstartModuleInterface):
    """The service interface exposed to Anaconda."""

