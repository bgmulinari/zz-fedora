"""Shared constants for the ZZ Fedora Anaconda add-on."""

from dasbus.identifier import DBusServiceIdentifier

from pyanaconda.core.dbus import DBus
from pyanaconda.modules.common.constants.namespaces import ADDONS_NAMESPACE

ZZ_FEDORA_NAMESPACE = (*ADDONS_NAMESPACE, "ZZFedora")

ZZ_FEDORA = DBusServiceIdentifier(
    namespace=ZZ_FEDORA_NAMESPACE,
    message_bus=DBus,
)

SELECTION_FILE = "/run/zz-fedora/install-selected"

DEFAULT_DESKTOP_APP_PROFILE = "full"
DESKTOP_APP_PROFILES = (
    "full",
    "minimal",
)

CATEGORY_ORDER = (
    "browsers",
    "desktop",
    "ai",
    "dev",
    "dotnet",
    "office",
    "gaming",
    "media",
)
