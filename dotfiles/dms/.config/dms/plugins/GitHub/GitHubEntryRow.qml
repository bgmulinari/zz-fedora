import QtQuick
import qs.Common
import qs.DCommon.Widgets

// A row of a page's list that leads somewhere, as github.com lists a
// repository's files or a release's assets: a glyph (an Octicon), the
// name, and a note on the right. A click opens `url` through the page
// (GitHubBrowse.openLink), or runs `action`.
Rectangle {
    id: entry

    property var page: null
    property string icon: "file"
    property color iconColor: Theme.surfaceVariantText
    property string text: ""
    property string note: ""
    property string url: ""
    property var action: null
    property bool mono: false
    property bool strong: false
    readonly property bool takesClicks: true

    width: parent ? parent.width : 0
    height: 32
    radius: Theme.cornerRadius
    color: entryArea.containsMouse && (url !== "" || !!action) ? Theme.withAlpha(Theme.surfaceText, 0.06) : "transparent"

    GitHubOcticon {
        id: glyph
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        name: entry.icon
        size: 16
        color: entry.iconColor
    }

    StyledText {
        id: label
        anchors.left: glyph.right
        anchors.leftMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, parent.width - x - noteText.implicitWidth - Theme.spacingL)
        text: entry.text
        textFormat: Text.PlainText
        isMonospace: entry.mono
        font.pixelSize: Theme.fontSizeSmall
        font.weight: entry.strong ? Font.DemiBold : Font.Normal
        font.underline: entryArea.containsMouse && (entry.url !== "" || !!entry.action)
        color: Theme.surfaceText
        wrapMode: Text.NoWrap
        elide: Text.ElideMiddle
    }

    StyledText {
        id: noteText
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        visible: entry.note !== ""
        text: entry.note
        textFormat: Text.PlainText
        font.pixelSize: Theme.fontSizeSmall - 1
        color: Theme.surfaceVariantText
    }

    MouseArea {
        id: entryArea
        anchors.fill: parent
        hoverEnabled: true
        enabled: entry.url !== "" || !!entry.action
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (entry.action)
                entry.action();
            else
                entry.page.openLink(entry.url);
        }
    }
}
