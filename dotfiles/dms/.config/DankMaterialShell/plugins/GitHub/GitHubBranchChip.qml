import QtQuick
import qs.Common
import qs.Widgets

// A branch or a commit as github.com marks one: monospace on an accent tint,
// shortened in the middle past maxWidth; it opens through the page
// (GitHubDetail.openLink).
Rectangle {
    id: branchChip

    property var page: null
    property string text: ""
    property string url: ""
    property string icon: ""
    property int maxWidth: 220
    // The room before the text: the padding, and the icon when there is one.
    readonly property real lead: Theme.spacingS + (icon !== "" ? chipIcon.width + 3 : 0)

    height: 22
    // As wide as the text drawn: a name shortened in the middle is narrower
    // than the room it was given.
    width: lead + Theme.spacingS + chipText.contentWidth
    radius: 6
    color: Theme.withAlpha(Theme.primary, branchArea.containsMouse && url !== "" ? 0.22 : 0.12)

    DankIcon {
        id: chipIcon
        visible: branchChip.icon !== ""
        x: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        name: branchChip.icon
        size: Theme.iconSizeSmall - 2
        color: Theme.primary
    }

    StyledText {
        id: chipText
        x: branchChip.lead
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, branchChip.maxWidth - branchChip.lead - Theme.spacingS)
        text: branchChip.text
        textFormat: Text.PlainText
        isMonospace: true
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.primary
        wrapMode: Text.NoWrap
        elide: Text.ElideMiddle
    }

    MouseArea {
        id: branchArea
        anchors.fill: parent
        enabled: branchChip.url !== "" && !!branchChip.page
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: branchChip.page.openLink(branchChip.url)
    }
}
