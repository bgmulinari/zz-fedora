import QtQuick
import qs.Common
import qs.Widgets

// A change button as github.com draws its secondary ones: an outlined pill
// with its icon in the change's tone, or a soft fill of that tone (tonal)
// for the change a page most likely came for; filled is the primary button
// (Comment), solid in its tone while it can run. A change on its way shows
// a spinner; one that cannot run now dims. compact is the smaller kind
// under a review thread.
Rectangle {
    id: pill

    property string icon: ""
    property string text: ""
    property color tone: Theme.primary
    property bool tonal: false
    property bool running: false
    property bool usable: true
    property bool compact: false
    property bool filled: false
    // Text and icon: on the fill, in the tone, or plain.
    readonly property color ink: filled ? (usable ? Theme.primaryText : Theme.surfaceVariantText) : (tonal ? tone : Theme.surfaceText)

    signal activated()

    height: compact ? 26 : 32
    width: pillRow.implicitWidth + Theme.spacingM * 2
    radius: height / 2
    opacity: usable || running || filled ? 1 : 0.45
    color: {
        if (filled)
            return usable ? (pillArea.containsMouse ? Qt.lighter(tone, 1.08) : tone) : Theme.withAlpha(Theme.surfaceText, 0.08);
        if (tonal)
            return Theme.withAlpha(tone, pillArea.containsMouse && usable ? 0.24 : 0.16);
        return pillArea.containsMouse && usable ? Theme.withAlpha(Theme.surfaceText, 0.06) : "transparent";
    }
    border.width: tonal || filled ? 0 : 1
    border.color: Theme.withAlpha(Theme.outlineVariant, 0.8)

    Row {
        id: pillRow
        anchors.centerIn: parent
        spacing: Theme.spacingXS

        DankSpinner {
            visible: pill.running
            anchors.verticalCenter: parent.verticalCenter
            size: 14
            color: pill.filled ? pill.ink : pill.tone
        }

        DankIcon {
            visible: !pill.running
            anchors.verticalCenter: parent.verticalCenter
            name: pill.icon
            size: pill.compact ? Theme.iconSizeSmall - 2 : Theme.iconSizeSmall
            color: pill.filled ? pill.ink : pill.tone
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: pill.text
            font.pixelSize: Theme.fontSizeSmall
            font.weight: pill.compact ? Font.Medium : Font.DemiBold
            color: pill.ink
        }
    }

    MouseArea {
        id: pillArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: pill.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: {
            if (pill.usable)
                pill.activated();
        }
    }
}
