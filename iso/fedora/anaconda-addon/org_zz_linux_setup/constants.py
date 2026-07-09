"""Shared constants for the ZZ Linux Setup Anaconda add-on."""

from dasbus.identifier import DBusServiceIdentifier

from pyanaconda.core.dbus import DBus
from pyanaconda.modules.common.constants.namespaces import ADDONS_NAMESPACE

ZZ_LINUX_SETUP_NAMESPACE = (*ADDONS_NAMESPACE, "ZZLinuxSetup")

ZZ_LINUX_SETUP = DBusServiceIdentifier(
    namespace=ZZ_LINUX_SETUP_NAMESPACE,
    message_bus=DBus,
)

SELECTION_FILE = "/tmp/zz-linux-setup-install-selected"

CATEGORY_ORDER = (
    "browsers",
    "ai",
    "dev",
    "dotnet",
    "office",
    "gaming",
    "media",
)
