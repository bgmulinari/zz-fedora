import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "GitHubLogic.js" as Logic

// A repository as a profile's pinned or popular box shows it
// (Logic.repoCardOf): its name (opening its home here) with Public,
// Private, or archived beside it, where it was forked from, its
// description, and its language, stars, and forks.
Rectangle {
    id: card

    property var page: null
    property var repo: null
    // Owner/name rather than the name alone: a pinned repository can be
    // someone else's.
    property bool fullName: false

    implicitHeight: cardColumn.implicitHeight + Theme.spacingM * 2
    radius: Theme.cornerRadius
    color: cardHover.hovered ? Theme.withAlpha(Theme.surfaceText, 0.04) : "transparent"
    border.width: 1
    border.color: Theme.withAlpha(Theme.outlineVariant, 0.45)

    // Lit while the pointer is anywhere on it, its links too.
    HoverHandler {
        id: cardHover
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: card.page.openLink(Logic.repoUrl(card.repo.repo))
    }

    Column {
        id: cardColumn
        x: Theme.spacingM
        y: Theme.spacingM
        width: parent.width - Theme.spacingM * 2
        spacing: Theme.spacingS

        Row {
            width: parent.width
            spacing: Theme.spacingS

            GitHubOcticon {
                anchors.verticalCenter: parent.verticalCenter
                name: card.repo && card.repo.isFork ? "repo-forked" : "repo"
                size: 16
                color: Theme.surfaceVariantText
            }

            GitHubLinkText {
                id: name
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - x - badge.width - parent.spacing)
                page: card.page
                text: card.repo ? (card.fullName && card.repo.owner !== "" ? card.repo.repo : card.repo.name) : ""
                url: card.repo ? Logic.repoUrl(card.repo.repo) : ""
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
                color: Theme.primary
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }

            GitHubBadge {
                id: badge
                anchors.verticalCenter: parent.verticalCenter
                text: !card.repo ? "" : (card.repo.isPrivate ? "Private" : "Public") + (card.repo.isArchived ? " archive" : "")
                tone: card.repo && card.repo.isArchived ? "warning" : "muted"
            }
        }

        GitHubLinkText {
            visible: !!card.repo && card.repo.parent !== ""
            page: card.page
            width: Math.min(implicitWidth, parent.width)
            text: card.repo ? "Forked from " + card.repo.parent : ""
            url: card.repo && card.repo.parent ? Logic.repoUrl(card.repo.parent) : ""
            font.pixelSize: Theme.fontSizeSmall - 1
            color: Theme.surfaceVariantText
            wrapMode: Text.NoWrap
            elide: Text.ElideRight
        }

        StyledText {
            visible: text !== ""
            width: parent.width
            text: card.repo ? card.repo.description : ""
            textFormat: Text.PlainText
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            wrapMode: Text.Wrap
            maximumLineCount: 3
            elide: Text.ElideRight
        }

        Row {
            spacing: Theme.spacingM
            height: 18

            Row {
                visible: !!card.repo && card.repo.language !== ""
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10
                    height: 10
                    radius: 5
                    color: card.repo && card.repo.languageColor !== "" ? card.repo.languageColor : Theme.withAlpha(Theme.surfaceText, 0.3)
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: card.repo ? card.repo.language : ""
                    textFormat: Text.PlainText
                    font.pixelSize: Theme.fontSizeSmall - 1
                    color: Theme.surfaceVariantText
                }
            }

            Count {
                visible: !!card.repo && card.repo.stars > 0
                icon: "star"
                count: card.repo ? card.repo.stars : 0
                url: card.repo ? Logic.repoUrl(card.repo.repo) + "/stargazers" : ""
            }

            Count {
                visible: !!card.repo && card.repo.forks > 0
                icon: "repo-forked"
                count: card.repo ? card.repo.forks : 0
                url: card.repo ? Logic.repoUrl(card.repo.repo) + "/forks" : ""
            }
        }
    }

    component Count: Item {
        id: count
        property string icon: ""
        property int count: 0
        property string url: ""
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: countRow.implicitWidth
        implicitHeight: 18

        Row {
            id: countRow
            height: parent.height
            spacing: 3

            GitHubOcticon {
                anchors.verticalCenter: parent.verticalCenter
                name: count.icon
                size: 13
                color: Theme.surfaceVariantText
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: Logic.shortCount(count.count)
                font.pixelSize: Theme.fontSizeSmall - 1
                font.underline: countArea.containsMouse
                color: Theme.surfaceVariantText
            }
        }

        MouseArea {
            id: countArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: card.page.openExternally(count.url)
        }
    }
}
