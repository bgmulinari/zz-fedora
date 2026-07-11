"""Shared constants for the ZZ Fedora Anaconda add-on."""

from dasbus.identifier import DBusServiceIdentifier

from pyanaconda.core.dbus import DBus
from pyanaconda.modules.common.constants.namespaces import ADDONS_NAMESPACE

ZZ_FEDORA_NAMESPACE = (*ADDONS_NAMESPACE, "ZZFedora")

ZZ_FEDORA = DBusServiceIdentifier(
    namespace=ZZ_FEDORA_NAMESPACE,
    message_bus=DBus,
)

SELECTION_FILE = "/tmp/zz-fedora-install-selected"

CATEGORY_ORDER = (
    "browsers",
    "ai",
    "dev",
    "dotnet",
    "office",
    "gaming",
    "media",
)
