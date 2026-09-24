import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Common
import qs.Services
import qs.Widgets

// The mark's right-click menu, built like the DMS clipboard button's: an
// overlay layer over the screen that closes on any click outside the card,
// with the card placed against the bar next to the mark. It jumps to a tab
// (with the tab's count), opens a window, refreshes, opens github.com, and
// opens the plugin's own section in the DMS settings.
PanelWindow {
    id: menu

    // [{ "icon", "label", "detail", "action" }], or { "separator": true }.
    property var entries: []

    property bool isVertical: false
    property string edge: "top"
    property point anchorPos: Qt.point(0, 0)

    function showAt(x, y, vertical, barEdge, targetScreen) {
        if (targetScreen)
            menu.screen = targetScreen;
        anchorPos = Qt.point(x, y);
        isVertical = vertical;
        edge = barEdge || "top";
        visible = true;
        if (menu.screen)
            TrayMenuManager.registerMenu(menu.screen.name, menu);
    }

    // TrayMenuManager.closeAllMenus (a modal or a popout opening, a click
    // on the bar) closes a registered menu through close().
    function close() {
        visible = false;
        if (menu.screen)
            TrayMenuManager.unregisterMenu(menu.screen.name);
    }

    WlrLayershell.namespace: "dms:plugins:github-menu"
    WlrLayershell.layer: WlrLayershell.Overlay
    WlrLayershell.exclusiveZone: -1
    WlrLayershell.keyboardFocus: visible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    screen: null
    visible: false
    color: "transparent"
    anchors {
        top: true
        left: true
        right: true
        bottom: true
    }

    Component.onDestruction: {
        if (menu.screen)
            TrayMenuManager.unregisterMenu(menu.screen.name);
    }

    Connections {
        target: PopoutManager
        function onPopoutOpening() {
            menu.close();
        }
    }

    WindowBlur {
        targetWindow: menu
        blurX: card.x
        blurY: card.y
        blurWidth: menu.visible ? card.width : 0
        blurHeight: menu.visible ? card.height : 0
        blurRadius: Theme.cornerRadius
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: menu.close()
    }

    Item {
        anchors.fill: parent
        focus: menu.visible
        Keys.onEscapePressed: menu.close()
    }

    Rectangle {
        id: card

        x: {
            if (menu.isVertical)
                return menu.edge === "left" ? Math.min(menu.width - width - 10, menu.anchorPos.x) : Math.max(10, menu.anchorPos.x - width);
            return Math.max(10, Math.min(menu.width - width - 10, menu.anchorPos.x - width / 2));
        }
        y: {
            if (menu.isVertical)
                return Math.max(10, Math.min(menu.height - height - 10, menu.anchorPos.y - height / 2));
            return menu.edge === "bottom" ? Math.max(10, menu.anchorPos.y - height) : Math.min(menu.height - height - 10, menu.anchorPos.y);
        }
        width: 240
        height: column.implicitHeight + Theme.spacingS * 2
        color: Theme.withAlpha(Theme.surfaceContainer, Theme.popupTransparency)
        radius: Theme.cornerRadius
        border.color: BlurService.borderColor
        border.width: BlurService.borderWidth

        opacity: menu.visible ? 1 : 0
        visible: opacity > 0

        Behavior on opacity {
            NumberAnimation {
                duration: Theme.shortDuration
                easing.type: Theme.emphasizedEasing
            }
        }

        // Swallows clicks between the entries, which would otherwise reach
        // the close-on-click layer behind the card.
        MouseArea {
            anchors.fill: parent
        }

        Column {
            id: column
            width: parent.width - Theme.spacingS * 2
            x: Theme.spacingS
            y: Theme.spacingS
            spacing: 1

            Repeater {
                model: menu.entries

                Item {
                    id: entry

                    required property var modelData

                    width: column.width
                    height: modelData.separator ? Theme.spacingS + 1 : 32

                    Rectangle {
                        visible: !!entry.modelData.separator
                        anchors.verticalCenter: parent.verticalCenter
                        x: Theme.spacingXS
                        width: parent.width - Theme.spacingXS * 2
                        height: 1
                        color: Theme.withAlpha(Theme.outlineVariant, 0.6)
                    }

                    Rectangle {
                        visible: !entry.modelData.separator
                        anchors.fill: parent
                        radius: Theme.cornerRadius
                        color: area.containsMouse ? BlurService.hoverColor(Theme.widgetBaseHoverColor) : "transparent"

                        DankIcon {
                            id: icon
                            anchors.left: parent.left
                            anchors.leftMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            name: entry.modelData.icon || ""
                            size: 16
                            color: Theme.surfaceText
                        }

                        StyledText {
                            anchors.left: icon.right
                            anchors.leftMargin: Theme.spacingS
                            anchors.right: detail.left
                            anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            text: entry.modelData.label || ""
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                            elide: Text.ElideRight
                        }

                        StyledText {
                            id: detail
                            anchors.right: parent.right
                            anchors.rightMargin: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            text: entry.modelData.detail || ""
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        MouseArea {
                            id: area
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                menu.close();
                                entry.modelData.action();
                            }
                        }
                    }
                }
            }
        }
    }
}
