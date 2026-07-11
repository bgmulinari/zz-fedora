"""D-Bus interface for the ZZ Fedora Anaconda add-on service."""

from dasbus.server.interface import dbus_interface

from pyanaconda.modules.common.base import KickstartModuleInterface

from org_zz_fedora.constants import ZZ_FEDORA


@dbus_interface(ZZ_FEDORA.interface_name)
class ZZFedoraInterface(KickstartModuleInterface):
    """The service interface exposed to Anaconda."""
