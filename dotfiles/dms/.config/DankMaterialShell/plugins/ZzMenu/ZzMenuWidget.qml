import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modals.Common
import qs.Modules.Plugins

// The bar surface of the ZZ menu: a "ZZ" pill whose popout is the menu
// itself (ZzMenuPanel), navigated group by group. Right click opens a
// terminal, the other place zz commands live. Like the shell's launcher
// the menu has two homes: a click drops it under the pill, while the
// keybind opens the same panel centered on the screen over a dimmed
// background, through the widget IPC (`dms ipc call widget toggleWith
// zzMenu root`, or `openWith zzMenu niri` for a group). `widget toggle`
// is the click.
PluginComponent {
    id: root

    layerNamespacePlugin: "zz-menu"

    // The group the next open starts at, "" for the root. A group asked for
    // through the IPC applies to that open only; the next open, from the
    // pill or the keybind, starts at the root again.
    property string initialMenu: ""
    // The popout host keeps its panel loaded between opens, so "open" means
    // the popout is showing, not that the panel exists.
    property var panelItem: null
    property var modalPanel: null
    readonly property bool popoutShowing: panelItem !== null && !!panelItem.parentPopout && panelItem.parentPopout.shouldBeVisible

    ZzMenuInventory {
        id: menuInventory
        pluginService: root.pluginService
    }

    // The keybind path: the centered modal.
    function openWithMode(mode) {
        const menu = !mode || mode === "all" || mode === "root" ? "" : String(mode);
        initialMenu = menu;
        if (menuModal.shouldBeVisible) {
            if (modalPanel)
                modalPanel.openAt(menu);
            return;
        }
        if (popoutShowing)
            closePopout();
        menuModal.open();
    }

    function toggleWithMode(mode) {
        if (menuModal.shouldBeVisible)
            menuModal.close();
        else
            openWithMode(mode);
    }

    DankModal {
        id: menuModal
        layerNamespace: "dms:plugins:zz-menu-modal"
        modalWidth: 560
        modalHeight: 640
        targetScreen: root.parentScreen
        onDialogClosed: root.modalPanel = null

        content: Component {
            ZzMenuPanel {
                inventory: menuInventory
                initialMenu: root.initialMenu
                fillMode: true
                padding: Theme.spacingL
                maxVisibleRows: 100
                parentPopout: menuModal
                onOpened: root.initialMenu = ""
                Component.onCompleted: root.modalPanel = this
                Component.onDestruction: {
                    if (root.modalPanel === this)
                        root.modalPanel = null;
                }
            }
        }
    }

    pillRightClickAction: () => Quickshell.execDetached(["xdg-terminal-exec"])

    popoutWidth: 440

    popoutContent: Component {
        ZzMenuPanel {
            inventory: menuInventory
            initialMenu: root.initialMenu
            onOpened: root.initialMenu = ""
            Component.onCompleted: root.panelItem = this
            Component.onDestruction: {
                if (root.panelItem === this)
                    root.panelItem = null;
            }
        }
    }

    // Bare text, not a boxed pill: BasePill already draws the background and
    // padding the bar settings ask for.
    horizontalBarPill: Component {
        StyledText {
            text: "ZZ"
            font.weight: Font.Bold
            font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
            color: Theme.widgetIconColor
        }
    }

    verticalBarPill: Component {
        StyledText {
            text: "ZZ"
            font.weight: Font.Bold
            font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
            color: Theme.widgetIconColor
        }
    }
}
