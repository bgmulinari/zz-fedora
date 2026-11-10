import QtQuick
import Quickshell.Widgets
import qs.Common
import qs.Widgets
import "GitHubLogic.js" as Logic

// A person's GitHub picture, round, from GitHub's public avatar host (no
// credential involved); the initial stands in while it loads or when there
// is none (an app or a bot). With a page (GitHubDetail), it opens the
// profile. The pointer resting on it opens the person's hover card
// (GitHubHovercard) from the panel it is in, beside subjectId (the pull
// request or issue it is shown for) when it has one; a menu's or a card's
// own picture turns that off (hovercard).
ClippingRectangle {
    id: avatar

    property var page: null
    property string login: ""
    property int size: 20
    property bool hovercard: true
    property string subjectId: ""
    readonly property bool loaded: picture.status === Image.Ready

    // The panel's card layer, the first parent that has one, found on the
    // first hover and kept: a list lets go of a row (its parent) before it
    // destroys it, so the layer cannot be looked for then.
    property Item cardHost: null

    function cardLayer() {
        if (!cardHost)
            for (let p = avatar.parent; p && !cardHost; p = p.parent)
                if (p.hovercardLayer !== undefined)
                    cardHost = p.hovercardLayer;
        return cardHost;
    }

    HoverHandler {
        enabled: avatar.hovercard && avatar.login !== ""
        onHoveredChanged: {
            const layer = avatar.cardLayer();
            if (layer)
                layer.hovered(avatar, avatar.login, avatar.subjectId, hovered);
        }
    }

    Component.onDestruction: {
        if (avatar.cardHost)
            avatar.cardHost.gone(avatar);
    }

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
