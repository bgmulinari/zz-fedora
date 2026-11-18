import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "GitHubLogic.js" as Logic

// A commit as github.com lists one in a history: its title (its references
// link, the rest opens the commit here), a "…" that unfolds the rest of
// its message, who wrote it and when, its checks, and on the right whether
// its signature is verified, its short SHA (opening it), a copy of the
// whole SHA, and a way to browse the files at it on GitHub. `compact` is
// the latest commit over a repository's files: one line, the SHA and how
// long ago on the right.
Rectangle {
    id: row

    property var page: null
    property var commit: null
    property bool compact: false
    property bool unfolded: false
    readonly property var author: commit && commit.authors.length > 0 ? commit.authors[0] : null
    readonly property string authorLogin: author ? author.login : ""
    readonly property var checks: commit ? Logic.checksGlyph(commit.checks) : null

    onCommitChanged: unfolded = false

    width: parent ? parent.width : 0
    implicitHeight: compact ? 40 : Math.max(52, main.implicitHeight + Theme.spacingS * 2)
    height: implicitHeight
    color: rowHover.hovered ? Theme.withAlpha(Theme.surfaceText, 0.04) : "transparent"

    // Lit while the pointer is anywhere on it, its links too.
    HoverHandler {
        id: rowHover
    }

    // The row's own click opens the commit; its links and buttons take
    // theirs.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: row.page.openLink(row.commit.url)
    }

    Column {
        id: main
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingM
        anchors.right: side.left
        anchors.rightMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        spacing: 4

        Row {
            width: parent.width
            spacing: Theme.spacingS

            GitHubAvatar {
                visible: row.compact
                anchors.verticalCenter: parent.verticalCenter
                page: row.page
                login: row.authorLogin
                size: 20
            }

            GitHubLinkText {
                visible: row.compact
                anchors.verticalCenter: parent.verticalCenter
                page: row.page
                text: row.author ? (row.author.login || row.author.name) : ""
                url: Logic.profileUrl(row.authorLogin)
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
                color: Theme.surfaceText
            }

            GitHubRichText {
                id: title
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - x - (more.visible ? more.width + parent.spacing : 0))
                html: row.commit ? row.page.messageHtml(row.commit.headline, row.commit.repo) : ""
                font.pixelSize: row.compact ? Theme.fontSizeSmall : Theme.fontSizeMedium
                font.weight: row.compact ? Font.Normal : Font.DemiBold
                color: row.compact ? Theme.surfaceVariantText : Theme.surfaceText
                wrapMode: row.compact ? Text.NoWrap : Text.Wrap
                elide: Text.ElideRight
                maximumLineCount: row.compact ? 1 : 3
                clip: row.compact

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: mouse => {
                        const link = title.linkAt(mouse.x, mouse.y);
                        row.page.openLink(link !== "" ? link : row.commit.url);
                    }
                }
            }

            // The rest of the message, folded as github.com folds it.
            Rectangle {
                id: more
                visible: !!row.commit && row.commit.body !== "" && !row.compact
                anchors.verticalCenter: parent.verticalCenter
                width: 26
                height: 16
                radius: 4
                color: moreArea.containsMouse || row.unfolded ? Theme.withAlpha(Theme.primary, 0.2) : Theme.withAlpha(Theme.surfaceText, 0.1)

                StyledText {
                    anchors.centerIn: parent
                    text: "…"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Bold
                    color: row.unfolded ? Theme.primary : Theme.surfaceVariantText
                }

                MouseArea {
                    id: moreArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: row.unfolded = !row.unfolded
                }
            }
        }

        GitHubRichText {
            id: messageBody
            visible: row.unfolded
            width: parent.width
            html: visible ? row.page.messageHtml(row.commit.body, row.commit.repo) : ""
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.Wrap
            onLinkActivated: link => row.page.openLink(link)
        }

        // Who wrote it (the co-authors too) and when; who committed it, when
        // someone else did.
        Row {
            visible: !row.compact
            width: parent.width
            height: 20
            spacing: Theme.spacingXS

            Row {
                anchors.verticalCenter: parent.verticalCenter
                spacing: -6

                Repeater {
                    model: row.commit ? row.commit.authors.slice(0, 3) : []

                    GitHubAvatar {
                        required property var modelData
                        page: row.page
                        login: modelData.login
                        size: 18
                        z: -index
                        required property int index
                    }
                }
            }

            Item {
                width: 2
                height: 1
            }

            GitHubLinkText {
                anchors.verticalCenter: parent.verticalCenter
                page: row.page
                text: row.author ? (row.author.login || row.author.name) : ""
                url: Logic.profileUrl(row.authorLogin)
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
                color: Theme.surfaceText
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - x)
                text: {
                    if (!row.commit)
                        return "";
                    const others = row.commit.authorsTotal - 1;
                    const co = others === 1 && row.commit.authors.length > 1 ? "and " + (row.commit.authors[1].login || row.commit.authors[1].name) + " " : (others > 1 ? "and " + others + " others " : "");
                    const verb = row.commit.committer ? "authored and " + row.commit.committer.login + " committed " : "committed ";
                    return co + verb + Logic.when(row.commit.committedAt);
                }
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }

            GitHubStatusIcon {
                visible: !!row.checks
                anchors.verticalCenter: parent.verticalCenter
                glyph: row.checks
                size: 14
            }
        }
    }

    Row {
        id: side
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingXS

        GitHubBadge {
            visible: !row.compact && !!row.commit && row.commit.verified
            anchors.verticalCenter: parent.verticalCenter
            text: "Verified"
            tone: "success"
        }

        GitHubBranchChip {
            anchors.verticalCenter: parent.verticalCenter
            page: row.page
            text: row.commit ? row.commit.short : ""
            url: row.commit ? row.commit.url : ""
        }

        StyledText {
            visible: row.compact
            anchors.verticalCenter: parent.verticalCenter
            text: row.commit ? "· " + Logic.when(row.commit.committedAt) : ""
            textFormat: Text.PlainText
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        GitHubCopyButton {
            visible: !row.compact
            anchors.verticalCenter: parent.verticalCenter
            github: row.page ? row.page.github : null
            copyText: row.commit ? row.commit.sha : ""
            toast: "Copied " + copyText
            tooltipText: "Copy the full SHA"
        }

        DActionButton {
            visible: !row.compact
            anchors.verticalCenter: parent.verticalCenter
            buttonSize: 24
            iconSize: 14
            iconName: "code"
            iconColor: Theme.surfaceVariantText
            tooltipText: "Browse the repository at this point"
            onClicked: row.page.openExternally(Logic.repoUrl(row.commit.repo) + "/tree/" + row.commit.sha)
        }
    }

    Rectangle {
        anchors.bottom: parent.bottom
        width: parent.width
        height: 1
        visible: !row.compact
        color: Theme.withAlpha(Theme.outlineVariant, 0.35)
    }
}
