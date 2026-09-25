import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Widgets
import "GitHubLogic.js" as Logic

// A person's GitHub picture, round, from GitHub's public avatar host (no
// credential involved); the initial stands in while it loads or when there
// is none (an app or a bot). With a page (GitHubDetail), it opens the
// profile.
ClippingRectangle {
    id: avatar

    property var page: null
    property string login: ""
    property int size: 20
    readonly property bool loaded: picture.status === Image.Ready

    width: size
    height: size
    radius: size / 2
    color: Theme.withAlpha(Theme.surfaceText, 0.12)

    StyledText {
        visible: !avatar.loaded
        anchors.centerIn: parent
        text: avatar.login.charAt(0).toUpperCase()
        font.pixelSize: Math.round(avatar.size * 0.55)
        font.weight: Font.DemiBold
        color: Theme.surfaceVariantText
    }

    Image {
        id: picture
        anchors.fill: parent
        // One size for every place a person shows, so each picture is
        // fetched once.
        source: avatar.login !== "" && avatar.login !== "ghost" ? "https://avatars.githubusercontent.com/" + encodeURIComponent(avatar.login) + "?s=72" : ""
        sourceSize: Qt.size(72, 72)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: true
        smooth: true
        mipmap: true
    }

    MouseArea {
        anchors.fill: parent
        enabled: !!avatar.page
        cursorShape: Qt.PointingHandCursor
        onClicked: avatar.page.openLink(Logic.profileUrl(avatar.login))
    }
}
