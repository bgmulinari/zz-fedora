import QtQuick
import qs.Common
import qs.Widgets

// A GitHub label as github.com draws it: a pill tinted with the label's
// color, a dot of that color, and the name. The page's chips open the
// label's search; compact ones (in list rows, about as tall as the line
// of small text beside them) only show it.
Rectangle {
    id: chip

    property string name: ""
    // The label's color as GitHub stores it: hex without the #.
    property string hex: ""
    property bool compact: false
    // Called on a click; a chip without one takes no clicks.
    property var action: null

    readonly property color tone: /^[0-9a-fA-F]{6}$/.test(hex) ? "#" + hex : Theme.outline

    height: compact ? 18 : 22
    width: chipRow.implicitWidth + (compact ? 14 : Theme.spacingM)
    radius: height / 2
    color: Theme.withAlpha(tone, chipArea.containsMouse ? 0.26 : (compact ? 0.16 : 0.14))
    border.width: 1
    border.color: Theme.withAlpha(tone, compact ? 0.5 : 0.45)

    Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: chip.compact ? 4 : 5

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: chip.compact ? 6 : 7
            height: width
            radius: width / 2
            color: chip.tone
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: chip.name
            textFormat: Text.PlainText
            font.pixelSize: chip.compact ? Theme.fontSizeSmall - 1 : Theme.fontSizeSmall
            color: Theme.surfaceText
        }
    }

    MouseArea {
        id: chipArea
        anchors.fill: parent
        enabled: !!chip.action
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chip.action()
    }
}
