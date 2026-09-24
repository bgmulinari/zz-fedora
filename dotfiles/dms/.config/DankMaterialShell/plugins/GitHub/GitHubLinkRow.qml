import QtQuick
import qs.Common
import qs.Widgets

// A row that leads somewhere: more of something here (earlier comments, a
// whole post or log) or on GitHub, whichever its action opens. A note on
// the right says what to know about it. In a Markdown body it takes its
// own clicks rather than selecting text (takesClicks).
Rectangle {
    id: linkRow

    property var action: null
    property string icon: "open_in_new"
    property string text: ""
    property string note: ""
    readonly property bool takesClicks: true

    width: parent ? parent.width : 0
    height: 30
    radius: Theme.cornerRadius
    color: linkArea.containsMouse ? Theme.withAlpha(Theme.primary, 0.08) : "transparent"

    DankIcon {
        id: linkIcon
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        name: linkRow.icon
        size: Theme.iconSizeSmall
        color: Theme.primary
    }

    StyledText {
        id: linkText
        anchors.left: linkIcon.right
        anchors.leftMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, parent.width - x - Theme.spacingS)
        text: linkRow.text
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Medium
        color: Theme.primary
        elide: Text.ElideRight
    }

    StyledText {
        anchors.left: linkText.right
        anchors.leftMargin: Theme.spacingM
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        visible: linkRow.note !== ""
        horizontalAlignment: Text.AlignRight
        text: linkRow.note
        font.pixelSize: Theme.fontSizeSmall - 1
        color: Theme.surfaceVariantText
        elide: Text.ElideRight
    }

    MouseArea {
        id: linkArea
        anchors.fill: parent
        enabled: !!linkRow.action
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: linkRow.action()
    }
}
