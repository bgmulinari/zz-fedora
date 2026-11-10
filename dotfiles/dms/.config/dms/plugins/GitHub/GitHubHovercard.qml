import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "GitHubEmoji.js" as Emoji
import "GitHubLogic.js" as Logic

// A person's hover card over the panel, as github.com shows one over an
// avatar: the picture, login and name, status, bio, where they are and work,
// and GitHub's lines about them beside the pull request or issue on screen
// (opened it, committed to the repository lately, the teams and
// organizations they belong to, as links). The panel holds one, over the
// lists and the pages alike; an avatar finds it through its parents
// (hovercardLayer) and says when the pointer comes and goes. The card opens
// after the pointer rests a moment, stays while the pointer moves onto it,
// and goes a moment after the pointer leaves both.
Item {
    id: layer

    property var github: null

    // Who the card is for (login, beside subject) and what it shows: the
    // card once GitHub answers, the login alone meanwhile. avatar is the
    // picture it hangs from, null once that picture is gone (the rows
    // rebuilt under it): the card then stays while the pointer is on it,
    // and the same person's picture coming back takes it over.
    property Item avatar: null
    property string login: ""
    property string subject: ""
    property var card: null
    property point spot: Qt.point(0, 0)
    property real avatarSize: 0
    readonly property bool shown: login !== ""

    // The avatar the pointer rests on, until the card opens for it.
    property var waiting: null
    // The card goes in a moment unless the pointer comes back.
    readonly property bool closing: hideTimer.running

    // Whether the pointer is on an avatar: open its card after a moment
    // (sooner when another card shows); off, close the card a moment later
    // unless the pointer went onto it or onto another picture.
    function hovered(item, who, subjectId, on) {
        if (on) {
            hideTimer.stop();
            if (avatar === item)
                return;
            if (shown && who === login && subjectId === subject && !avatar) {
                hang(item);
                return;
            }
            waiting = {
                "avatar": item,
                "login": who,
                "subject": subjectId
            };
            showTimer.interval = shown ? 120 : 500;
            showTimer.restart();
            return;
        }
        if (waiting && waiting.avatar === item) {
            showTimer.stop();
            waiting = null;
        }
        if (shown)
            hideTimer.restart();
    }

    // An avatar going away: a card waiting for it does not open, and the
    // one it shows lets go of it.
    function gone(item) {
        if (waiting && waiting.avatar === item) {
            showTimer.stop();
            waiting = null;
        }
        if (avatar === item) {
            avatar = null;
            hideTimer.restart();
        }
    }

    // Where the card hangs: under (or over) the picture, as it is now. A
    // picture already out of the scene (a list's released row) has none.
    function hang(item) {
        let at;
        try {
            if (!item.parent || !item.visible)
                return false;
            at = item.mapToItem(layer, 0, 0);
        } catch (e) {
            return false;
        }
        avatar = item;
        avatarSize = item.height;
        spot = at;
        return true;
    }

    function open(entry) {
        if (!entry || !Qt.isQtObject(entry.avatar) || !hang(entry.avatar))
            return;
        login = entry.login;
        subject = entry.subject || "";
        card = null;
        const asked = login + "@" + subject;
        if (github)
            github.loadHovercard(entry.login, entry.subject, answer => {
                if (layer.login + "@" + layer.subject === asked)
                    layer.card = answer;
            });
    }

    function close() {
        showTimer.stop();
        hideTimer.stop();
        waiting = null;
        avatar = null;
        login = "";
        subject = "";
        card = null;
    }

    function openLink(url) {
        const safe = Logic.externalUrl(url);
        if (safe !== "")
            Qt.openUrlExternally(safe);
        close();
    }

    Timer {
        id: showTimer
        onTriggered: {
            const entry = layer.waiting;
            layer.waiting = null;
            layer.open(entry);
        }
    }

    Timer {
        id: hideTimer
        interval: 300
        onTriggered: {
            if (!cardHover.hovered)
                layer.close();
        }
    }

    // A scroll moves the picture from under the card: the card goes, as
    // github.com's does.
    Timer {
        interval: 200
        repeat: true
        running: layer.shown && !!layer.avatar
        onTriggered: {
            let at = null;
            try {
                at = layer.avatar.mapToItem(layer, 0, 0);
            } catch (e) {}
            if (!at || Math.abs(at.x - layer.spot.x) > 1 || Math.abs(at.y - layer.spot.y) > 1)
                layer.close();
        }
    }

    Rectangle {
        id: hovercard

        readonly property var c: layer.card
        readonly property bool below: layer.spot.y + layer.avatarSize + Theme.spacingXS + height <= layer.height || layer.spot.y - height - Theme.spacingXS < 0

        visible: layer.shown
        width: Math.min(320, layer.width - Theme.spacingS * 2)
        height: content.implicitHeight + Theme.spacingM * 2
        x: Math.max(Theme.spacingS, Math.min(layer.width - width - Theme.spacingS, layer.spot.x - Theme.spacingM))
        y: below ? layer.spot.y + layer.avatarSize + Theme.spacingXS : layer.spot.y - height - Theme.spacingXS
        radius: Theme.cornerRadius
        color: Theme.surfaceContainerHigh
        border.width: 1
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.8)

        HoverHandler {
            id: cardHover
            onHoveredChanged: {
                if (!hovered)
                    hideTimer.restart();
            }
        }

        // The card takes its own clicks: nothing under it is clicked
        // through it.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onWheel: wheel => wheel.accepted = true
        }

        Column {
            id: content
            x: Theme.spacingM
            y: Theme.spacingM
            width: parent.width - Theme.spacingM * 2
            spacing: Theme.spacingS

            GitHubAvatar {
                login: layer.login
                size: 48
                hovercard: false
            }

            // The login opens the profile; the name and pronouns follow.
            StyledText {
                id: who
                width: parent.width
                textFormat: Text.StyledText
                wrapMode: Text.Wrap
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceVariantText
                linkColor: Theme.surfaceText
                text: {
                    const c = hovercard.c;
                    const name = "<a href=\"" + Logic.escapeHtml(Logic.profileUrl(layer.login)) + "\"><b>" + Logic.escapeHtml(layer.login) + "</b></a>";
                    const extra = c ? [c.name, c.pronouns].filter(part => part !== "").map(Logic.escapeHtml).join(" · ") : "";
                    return name + (extra !== "" ? "&nbsp;&nbsp;" + extra : "");
                }
                onLinkActivated: link => layer.openLink(link)

                MouseArea {
                    anchors.fill: parent
                    acceptedButtons: Qt.NoButton
                    cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                }
            }

            DSpinner {
                visible: !hovercard.c && !Logic.isApp(layer.login)
                size: 14
            }

            // A status, as github.com shows it under the name.
            Rectangle {
                visible: !!hovercard.c && !!hovercard.c.status
                width: parent.width
                height: statusText.implicitHeight + Theme.spacingXS * 2
                radius: Theme.cornerRadius / 2
                color: Theme.withAlpha(Theme.surfaceText, 0.06)
                border.width: 1
                border.color: Theme.withAlpha(Theme.outlineVariant, 0.6)

                StyledText {
                    id: statusText
                    x: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Theme.spacingS * 2
                    wrapMode: Text.Wrap
                    textFormat: Text.PlainText
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    text: {
                        const status = hovercard.c ? hovercard.c.status : null;
                        if (!status)
                            return "";
                        const emoji = status.emoji.replace(/:([a-z0-9_+-]+):/g, (m, name) => Object.prototype.hasOwnProperty.call(Emoji.EMOJI, name) ? Emoji.EMOJI[name] : m);
                        return [emoji, status.message, status.busy ? "(busy)" : ""].filter(part => part !== "").join(" ");
                    }
                }
            }

            StyledText {
                visible: text !== ""
                width: parent.width
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                text: hovercard.c ? hovercard.c.bio : ""
            }

            StyledText {
                visible: !!hovercard.c && hovercard.c.app
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                text: "An app or a bot"
            }

            StyledText {
                visible: !!hovercard.c && !hovercard.c.app && !hovercard.c.found
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                text: "GitHub has no profile to show for this account"
            }

            Repeater {
                model: {
                    const c = hovercard.c;
                    if (!c)
                        return [];
                    const lines = [];
                    if (c.location)
                        lines.push({
                            "icon": "location_on",
                            "html": Logic.escapeHtml(c.location)
                        });
                    if (c.company)
                        lines.push({
                            "icon": "business",
                            "html": Logic.escapeHtml(c.company)
                        });
                    return lines.concat(c.contexts);
                }

                Row {
                    id: line
                    required property var modelData
                    width: content.width
                    spacing: Theme.spacingS

                    DIcon {
                        id: lineIcon
                        name: line.modelData.icon
                        size: Theme.iconSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        width: line.width - lineIcon.width - line.spacing
                        anchors.verticalCenter: lineIcon.verticalCenter
                        textFormat: Text.StyledText
                        wrapMode: Text.Wrap
                                font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        linkColor: Theme.surfaceText
                        text: line.modelData.html
                        onLinkActivated: link => layer.openLink(link)

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.NoButton
                            cursorShape: parent.hoveredLink !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
                        }
                    }
                }
            }
        }
    }
}
