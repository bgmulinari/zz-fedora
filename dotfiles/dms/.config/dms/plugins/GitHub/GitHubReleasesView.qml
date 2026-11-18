import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "GitHubLogic.js" as Logic

// A repository's releases as github.com's Releases page lists them, newest
// first, ten at a time as the end nears; or one release (its page). Each
// is a box: its name (opening its own page) with Latest, Pre-release, or
// Draft beside it, who published it and when, its tag and commit, the
// notes (GitHubMarkdown, their pictures signed by GitHub), the assets
// (GitHub's source archives last, as there; folded but on the first
// release and on a release's own page), and its reactions.
Column {
    id: view

    property var page: null
    readonly property bool single: !!page && page.kind === "release"
    readonly property var releases: !page || !page.detail ? [] : (single ? [page.detail] : page.detail.releases)

    width: parent ? parent.width : 0
    spacing: Theme.spacingL

    Repeater {
        model: view.releases

        Rectangle {
            id: release
            required property var modelData
            required property int index
            property bool assetsOpen: view.single || index === 0
            readonly property var info: modelData

            width: view.width
            height: releaseColumn.implicitHeight + Theme.spacingM * 2
            radius: Theme.cornerRadius
            color: "transparent"
            border.width: 1
            border.color: Theme.withAlpha(Theme.outlineVariant, 0.45)

            Column {
                id: releaseColumn
                x: Theme.spacingM
                y: Theme.spacingM
                width: parent.width - Theme.spacingM * 2
                spacing: Theme.spacingM

                // Name and badges; on a release's own page the header has
                // them.
                Flow {
                    visible: !view.single
                    width: parent.width
                    spacing: Theme.spacingS

                    GitHubLinkText {
                        page: view.page
                        width: Math.min(implicitWidth, parent.width)
                        text: release.info.name
                        url: release.info.url
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                        wrapMode: Text.Wrap
                    }

                    GitHubBadge {
                        visible: release.info.latest
                        y: 3
                        text: "Latest"
                        tone: "success"
                    }

                    GitHubBadge {
                        visible: release.info.prerelease
                        y: 3
                        text: "Pre-release"
                        tone: "warning"
                    }

                    GitHubBadge {
                        visible: release.info.draft
                        y: 3
                        text: "Draft"
                        tone: "muted"
                    }
                }

                // Who published it, when, and from what.
                Flow {
                    width: parent.width
                    spacing: Theme.spacingS

                    GitHubAvatar {
                        visible: release.info.author !== ""
                        y: 1
                        page: view.page
                        login: release.info.author
                        size: 20
                    }

                    GitHubLinkText {
                        visible: release.info.author !== ""
                        page: view.page
                        height: 22
                        verticalAlignment: Text.AlignVCenter
                        text: release.info.author
                        url: Logic.profileUrl(release.info.author)
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.DemiBold
                        color: Theme.surfaceText
                    }

                    StyledText {
                        height: 22
                        verticalAlignment: Text.AlignVCenter
                        text: (release.info.draft ? "drafted this " : "released this ") + Logic.when(release.info.publishedAt)
                        textFormat: Text.PlainText
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    GitHubBranchChip {
                        page: view.page
                        icon: "sell"
                        text: release.info.tag
                        url: Logic.repoUrl(view.page.repo) + "/tree/" + Logic.encodePath(release.info.tag)
                    }

                    GitHubBranchChip {
                        visible: !!release.info.commit
                        page: view.page
                        icon: "commit"
                        text: release.info.commit ? release.info.commit.short : ""
                        url: release.info.commit ? Logic.commitUrl(view.page.repo, release.info.commit.sha) : ""
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1
                    color: Theme.withAlpha(Theme.outlineVariant, 0.35)
                }

                GitHubMarkdown {
                    width: parent.width
                    page: view.page
                    source: release.info.body !== "" ? release.info.body : "_No release notes._"
                }

                // ---------- Assets ----------
                Column {
                    width: parent.width
                    spacing: 0

                    Item {
                        width: parent.width
                        height: 30

                        Row {
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingXS

                            DIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: release.assetsOpen ? "arrow_drop_down" : "arrow_right"
                                size: 20
                                color: Theme.surfaceText
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Assets"
                                font.pixelSize: Theme.fontSizeMedium
                                font.weight: Font.DemiBold
                                color: Theme.surfaceText
                            }

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                height: 18
                                width: Math.max(18, assetCount.implicitWidth + Theme.spacingS + 2)
                                radius: height / 2
                                color: Theme.withAlpha(Theme.surfaceText, 0.12)

                                StyledText {
                                    id: assetCount
                                    anchors.centerIn: parent
                                    text: String(release.info.assetsTotal)
                                    font.pixelSize: Theme.fontSizeSmall - 1
                                    font.weight: Font.DemiBold
                                    color: Theme.surfaceText
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: release.assetsOpen = !release.assetsOpen
                        }
                    }

                    Rectangle {
                        visible: release.assetsOpen
                        width: parent.width
                        height: assetRows.implicitHeight
                        radius: Theme.cornerRadius
                        color: "transparent"
                        border.width: 1
                        border.color: Theme.withAlpha(Theme.outlineVariant, 0.45)
                        clip: true

                        Column {
                            id: assetRows
                            width: parent.width

                            Repeater {
                                model: release.assetsOpen ? release.info.assets : []

                                GitHubEntryRow {
                                    required property var modelData
                                    page: view.page
                                    radius: 0
                                    icon: modelData.source ? "file-zip" : "package"
                                    text: modelData.name
                                    strong: !modelData.source
                                    note: [modelData.size, Logic.ago(modelData.at)].filter(part => part !== "").join(" · ")
                                    action: () => view.page.openExternally(modelData.url)
                                }
                            }

                            GitHubLinkRow {
                                readonly property int rest: release.info.assetsTotal - release.info.assets.length
                                visible: rest > 0
                                text: Logic.plural(rest, "more asset") + " on GitHub"
                                action: () => view.page.openExternally(release.info.url)
                            }
                        }
                    }
                }

                GitHubReactions {
                    width: parent.width
                    info: release.info.reactions
                    page: view.page
                }
            }
        }
    }

    StyledText {
        visible: !view.single && !!view.page && !!view.page.detail && view.releases.length === 0
        width: parent.width
        text: "There aren't any releases here."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    GitHubPageFooter {
        visible: !view.single
        page: view.page
        shown: view.releases.length
        total: !view.single && view.page && view.page.detail ? view.page.detail.total : 0
        more: !view.single && !!view.page && !!view.page.detail && view.page.detail.more
        noun: "releases"
    }

    // A release's own page leads to the rest.
    GitHubLinkRow {
        visible: view.single
        icon: "sell"
        text: "All releases"
        action: () => view.page.openLink(Logic.repoUrl(view.page.repo) + "/releases")
    }
}
