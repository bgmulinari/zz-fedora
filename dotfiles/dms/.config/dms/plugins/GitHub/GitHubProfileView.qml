import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "GitHubLogic.js" as Logic
import "GitHubEmoji.js" as Emoji

// A person's or an organization's profile as github.com's overview shows
// it, its sidebar above for a narrow popout: the picture, the name and
// login, the status, the bio, followers and following, the company,
// place, and links, and the organizations; then the profile's README, the
// pinned repositories (the most starred when none are pinned), a person's
// contributions over the last year, and an organization's latest
// repositories. A repository or an organization opens here.
Column {
    id: view

    property var page: null
    readonly property var profile: page ? page.detail : null
    readonly property bool wide: width >= 520

    width: parent ? parent.width : 0
    spacing: Theme.spacingL

    // ---------- Who ----------
    Row {
        width: parent.width
        spacing: Theme.spacingL

        GitHubAvatar {
            id: picture
            login: view.profile ? view.profile.login : ""
            square: !!view.profile && view.profile.isOrg
            size: 88
            pixels: 176
            hovercard: false
        }

        Column {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - picture.width - parent.spacing
            spacing: Theme.spacingXS

            StyledText {
                visible: text !== ""
                width: parent.width
                text: view.profile ? view.profile.name : ""
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeXLarge
                font.weight: Font.Bold
                color: Theme.surfaceText
                wrapMode: Text.Wrap
            }

            StyledText {
                width: parent.width
                text: view.profile ? view.profile.login + (view.profile.pronouns ? " · " + view.profile.pronouns : "") : ""
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeLarge
                color: Theme.surfaceVariantText
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }

            // The status, as github.com's pill under the picture.
            Rectangle {
                readonly property var status: view.profile ? view.profile.status : null
                visible: !!status
                width: Math.min(parent.width, statusText.implicitWidth + Theme.spacingM * 2)
                height: 26
                radius: height / 2
                color: Theme.withAlpha(Theme.surfaceText, 0.05)
                border.width: 1
                border.color: Theme.withAlpha(Theme.outlineVariant, 0.45)

                StyledText {
                    id: statusText
                    anchors.verticalCenter: parent.verticalCenter
                    x: Theme.spacingM
                    width: parent.width - Theme.spacingM * 2
                    text: parent.status ? [parent.status.emoji.replace(/:([a-z0-9_+-]+):/g, (m, name) => Object.prototype.hasOwnProperty.call(Emoji.EMOJI, name) ? Emoji.EMOJI[name] : m), parent.status.message].filter(part => part !== "").join(" ") : ""
                    textFormat: Text.PlainText
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    wrapMode: Text.NoWrap
                    elide: Text.ElideRight
                }
            }
        }
    }

    Column {
        width: parent.width
        spacing: Theme.spacingM

        GitHubRichText {
            visible: !!view.profile && view.profile.bio !== ""
            width: parent.width
            html: visible ? view.page.messageHtml(view.profile.bio, "") : ""
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceText
            wrapMode: Text.Wrap
            onLinkActivated: link => view.page.openLink(link)
        }

        // Followers and following, or an organization's people.
        Row {
            visible: !!view.profile
            spacing: Theme.spacingXS

            GitHubOcticon {
                anchors.verticalCenter: parent.verticalCenter
                name: "people"
                size: 14
                color: Theme.surfaceVariantText
            }

            Repeater {
                model: !view.profile ? [] : (view.profile.isOrg ? [[view.profile.members, view.profile.members === 1 ? "member" : "members", "https://github.com/orgs/" + view.profile.login + "/people"]] : [[view.profile.followers, view.profile.followers === 1 ? "follower" : "followers", view.profile.url + "?tab=followers"], [view.profile.following, "following", view.profile.url + "?tab=following"]])

                Row {
                    id: count
                    required property var modelData
                    required property int index
                    spacing: 3

                    StyledText {
                        visible: count.index > 0
                        anchors.verticalCenter: parent.verticalCenter
                        text: "·"
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Logic.shortCount(count.modelData[0])
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.DemiBold
                        font.underline: countArea.containsMouse
                        color: Theme.surfaceText

                        MouseArea {
                            id: countArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.page.openExternally(count.modelData[2])
                        }
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: count.modelData[1]
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }
            }
        }

        // What github.com lists under the bio.
        Column {
            width: parent.width
            spacing: Theme.spacingXS

            Repeater {
                model: {
                    const p = view.profile;
                    if (!p)
                        return [];
                    const facts = [];
                    if (p.company)
                        facts.push({
                            "icon": "organization",
                            "html": view.page.messageHtml(p.company, "")
                        });
                    if (p.location)
                        facts.push({
                            "icon": "location",
                            "text": p.location
                        });
                    if (p.email)
                        facts.push({
                            "icon": "mail",
                            "text": p.email,
                            "url": "mailto:" + p.email
                        });
                    if (p.website)
                        facts.push({
                            "icon": "link",
                            "text": p.websiteText,
                            "url": p.website
                        });
                    if (p.twitter)
                        facts.push({
                            "icon": "mention",
                            "text": "@" + p.twitter,
                            "url": "https://x.com/" + p.twitter
                        });
                    // The X account is the one above when GitHub lists it twice.
                    for (const account of p.social.filter(a => !(p.twitter && a.provider === "TWITTER")))
                        facts.push({
                            "icon": "link",
                            "text": account.text,
                            "url": account.url
                        });
                    return facts;
                }

                Row {
                    id: fact
                    required property var modelData
                    width: parent.width
                    height: 22
                    spacing: Theme.spacingS

                    GitHubOcticon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: fact.modelData.icon
                        size: 14
                        color: Theme.surfaceVariantText
                    }

                    // The company, whose @organizations link.
                    GitHubRichText {
                        visible: fact.modelData.html !== undefined
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width - 14 - parent.spacing)
                        html: visible ? fact.modelData.html : ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceText
                        wrapMode: Text.NoWrap
                        clip: true
                        onLinkActivated: link => view.page.openLink(link)
                    }

                    StyledText {
                        visible: fact.modelData.html === undefined
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, parent.width - 14 - parent.spacing)
                        text: visible ? fact.modelData.text : ""
                        textFormat: Text.PlainText
                        font.pixelSize: Theme.fontSizeSmall
                        font.underline: !!fact.modelData.url && factArea.containsMouse
                        color: Theme.surfaceText
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight

                        MouseArea {
                            id: factArea
                            anchors.fill: parent
                            enabled: !!fact.modelData.url
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: view.page.openLink(fact.modelData.url)
                        }
                    }
                }
            }
        }

        // The organizations a person shows, each opening here.
        Column {
            visible: !!view.profile && view.profile.orgs.length > 0
            width: parent.width
            spacing: Theme.spacingS

            StyledText {
                text: "Organizations"
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.DemiBold
                color: Theme.surfaceText
            }

            Flow {
                width: parent.width
                spacing: Theme.spacingXS

                Repeater {
                    model: view.profile ? view.profile.orgs : []

                    GitHubAvatar {
                        required property var modelData
                        page: view.page
                        login: modelData.login
                        square: true
                        size: 32
                        hovercard: false
                    }
                }
            }
        }
    }

    // ---------- README ----------
    GitHubReadme {
        page: view.page
        title: view.profile ? (view.profile.isOrg ? view.profile.login + "/.github" : view.profile.login + "/" + view.profile.login) + " · README.md" : ""
    }

    // ---------- Repositories ----------
    Column {
        visible: !!view.profile && view.profile.repos.length > 0
        width: parent.width
        spacing: Theme.spacingS

        StyledText {
            text: view.profile && view.profile.pinned ? "Pinned" : "Popular repositories"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.DemiBold
            color: Theme.surfaceText
        }

        Grid {
            id: cards
            width: parent.width
            columns: view.wide ? 2 : 1
            spacing: Theme.spacingS

            Repeater {
                model: view.profile ? view.profile.repos : []

                GitHubRepoCard {
                    required property var modelData
                    width: (cards.width - cards.spacing * (cards.columns - 1)) / cards.columns
                    height: Math.max(implicitHeight, cardHeights.most)
                    page: view.page
                    repo: modelData
                    fullName: modelData.owner !== (view.profile ? view.profile.login : "")
                    onImplicitHeightChanged: cardHeights.note(implicitHeight)
                    Component.onCompleted: cardHeights.note(implicitHeight)
                }
            }
        }
    }

    // ---------- Contributions ----------
    GitHubContributions {
        visible: !!view.profile && !!view.profile.contributions
        contributions: view.profile ? view.profile.contributions : null
    }

    // ---------- An organization's repositories ----------
    Column {
        visible: !!view.profile && view.profile.isOrg && view.profile.recent.length > 0
        width: parent.width
        spacing: Theme.spacingS

        StyledText {
            text: "Repositories"
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.DemiBold
            color: Theme.surfaceText
        }

        Repeater {
            model: view.profile && view.profile.isOrg ? view.profile.recent : []

            GitHubRepoCard {
                required property var modelData
                width: parent.width
                height: implicitHeight
                page: view.page
                repo: modelData
            }
        }
    }

    GitHubLinkRow {
        visible: !!view.profile && view.profile.reposTotal > 0
        icon: "book"
        text: view.profile ? "All " + Logic.plural(view.profile.reposTotal, "repository", "repositories") + " on GitHub" : ""
        action: () => view.page.openExternally(view.profile.url + "?tab=repositories")
    }

    // The cards of a row share its height: the tallest one's.
    QtObject {
        id: cardHeights
        property real most: 0
        function note(height) {
            if (height > most)
                most = height;
        }
    }
}
