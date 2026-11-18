import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "GitHubLogic.js" as Logic

// One commit as github.com's commit page shows it (its title is in the
// popout header): the rest of its message, who wrote and committed it and
// when, its checks, the pull requests it belongs to (opening here), its
// parents and its SHA, then "Showing 3 changed files with 48 additions and
// 2 deletions" over each file's diff (GitHubDiffFile). Past a budget of
// lines the diffs start folded; GitHub's API gives the first 100 files, and
// the rest are a link away.
Column {
    id: view

    property var page: null
    readonly property var info: page ? page.detail : null
    readonly property var commit: info ? info.commit : null
    readonly property var files: info && info.files ? info.files.files : []
    readonly property var shown: Logic.diffsShown(files, 3000, 400)
    readonly property var author: commit && commit.authors.length > 0 ? commit.authors[0] : null

    width: parent ? parent.width : 0
    spacing: Theme.spacingL

    // ---------- Message and authorship ----------
    Rectangle {
        width: parent.width
        height: about.implicitHeight + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceText, 0.03)
        border.width: 1
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.45)

        Column {
            id: about
            x: Theme.spacingM
            y: Theme.spacingM
            width: parent.width - Theme.spacingM * 2
            spacing: Theme.spacingM

            GitHubRichText {
                visible: !!view.commit && view.commit.body !== ""
                width: parent.width
                html: visible ? view.page.messageHtml(view.commit.body) : ""
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                wrapMode: Text.Wrap
                onLinkActivated: link => view.page.openLink(link)
            }

            Flow {
                width: parent.width
                spacing: Theme.spacingXS

                Row {
                    height: 22
                    spacing: -6

                    Repeater {
                        model: view.commit ? view.commit.authors.slice(0, 3) : []

                        GitHubAvatar {
                            required property var modelData
                            required property int index
                            anchors.verticalCenter: parent.verticalCenter
                            page: view.page
                            login: modelData.login
                            size: 20
                            z: -index
                        }
                    }
                }

                Item {
                    width: 2
                    height: 22
                }

                GitHubLinkText {
                    page: view.page
                    height: 22
                    verticalAlignment: Text.AlignVCenter
                    text: view.author ? (view.author.login || view.author.name) : ""
                    url: Logic.profileUrl(view.author ? view.author.login : "")
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: Theme.surfaceText
                }

                // Co-authors, as github.com counts them.
                StyledText {
                    readonly property int others: view.commit ? view.commit.authorsTotal - 1 : 0
                    visible: others > 0
                    height: 22
                    verticalAlignment: Text.AlignVCenter
                    text: others === 1 && view.commit.authors.length > 1 ? "and " + (view.commit.authors[1].login || view.commit.authors[1].name) : "and " + others + " others"
                    textFormat: Text.PlainText
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    height: 22
                    verticalAlignment: Text.AlignVCenter
                    text: view.commit ? (view.commit.committer ? "authored " + Logic.when(view.commit.authoredAt) + " and" : "committed " + Logic.when(view.commit.committedAt)) : ""
                    textFormat: Text.PlainText
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                GitHubLinkText {
                    visible: !!view.commit && !!view.commit.committer
                    page: view.page
                    height: 22
                    verticalAlignment: Text.AlignVCenter
                    text: view.commit && view.commit.committer ? view.commit.committer.login : ""
                    url: Logic.profileUrl(text)
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: Theme.surfaceText
                }

                StyledText {
                    visible: !!view.commit && !!view.commit.committer
                    height: 22
                    verticalAlignment: Text.AlignVCenter
                    text: view.commit ? "committed " + Logic.when(view.commit.committedAt) : ""
                    textFormat: Text.PlainText
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                Item {
                    width: Theme.spacingXS
                    height: 22
                }

                GitHubBadge {
                    visible: !!view.commit && view.commit.verified
                    y: 1
                    text: "Verified"
                    tone: "success"
                }

                Row {
                    readonly property var glyph: view.commit ? Logic.checksGlyph(view.commit.checks) : null
                    visible: !!glyph
                    height: 22
                    spacing: 4

                    GitHubStatusIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: parent.glyph
                        size: 14
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: view.commit ? Logic.checksText(view.commit.checks) : ""
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }
            }

            // The pull requests it belongs to, each in its own state.
            Flow {
                visible: !!view.info && view.info.pulls.length > 0
                width: parent.width
                spacing: Theme.spacingXS

                Repeater {
                    model: view.info ? view.info.pulls : []

                    PullChip {
                        required property var modelData
                        target: modelData
                    }
                }
            }

            // Its parents and its SHA, as the page's lower edge.
            Flow {
                width: parent.width
                spacing: Theme.spacingS

                StyledText {
                    height: 22
                    verticalAlignment: Text.AlignVCenter
                    text: view.commit ? (view.commit.parents.length === 1 ? "1 parent" : view.commit.parents.length + " parents") : ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                Repeater {
                    model: view.commit ? view.commit.parents : []

                    GitHubBranchChip {
                        required property var modelData
                        page: view.page
                        text: modelData.short
                        url: Logic.commitUrl(view.commit.repo, modelData.sha)
                    }
                }

                StyledText {
                    height: 22
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: Theme.spacingS
                    text: "commit"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    height: 22
                    verticalAlignment: Text.AlignVCenter
                    text: view.commit ? view.commit.sha : ""
                    textFormat: Text.PlainText
                    isMonospace: true
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                }

                GitHubCopyButton {
                    github: view.page ? view.page.github : null
                    buttonSize: 22
                    copyText: view.commit ? view.commit.sha : ""
                    toast: "Copied " + copyText
                    tooltipText: "Copy the full SHA"
                }

                GitHubLinkText {
                    page: view.page
                    height: 22
                    verticalAlignment: Text.AlignVCenter
                    leftPadding: Theme.spacingS
                    text: "Browse files"
                    url: view.commit ? Logic.repoUrl(view.commit.repo) + "/tree/" + view.commit.sha : ""
                    external: true
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: Theme.primary
                }
            }
        }
    }

    // ---------- Files ----------
    Column {
        width: parent.width
        spacing: Theme.spacingS

        Row {
            width: parent.width
            spacing: Theme.spacingS

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - (summaryStat.visible ? summaryStat.width + parent.spacing : 0))
                text: {
                    if (!view.commit)
                        return "";
                    const count = view.commit.changedFiles >= 0 ? view.commit.changedFiles : view.files.length;
                    return "Showing " + Logic.plural(count, "changed file") + " with " + Logic.plural(view.commit.additions, "addition") + " and " + Logic.plural(view.commit.deletions, "deletion") + ".";
                }
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                wrapMode: Text.Wrap
            }

            GitHubDiffstat {
                id: summaryStat
                anchors.verticalCenter: parent.verticalCenter
                visible: !!view.commit
                additions: view.commit ? view.commit.additions : 0
                deletions: view.commit ? view.commit.deletions : 0
            }
        }

        StyledText {
            visible: !view.info || !view.info.files
            text: "Loading the changes…"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        StyledText {
            visible: text !== ""
            width: parent.width
            text: view.info && view.info.files ? view.info.files.error : ""
            textFormat: Text.PlainText
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.error
            wrapMode: Text.Wrap
        }

        Repeater {
            model: view.files

            GitHubDiffFile {
                required property var modelData
                required property int index
                page: view.page
                file: modelData
                open: !!view.shown[index]
            }
        }

        GitHubLinkRow {
            readonly property int rest: view.commit && view.commit.changedFiles > view.files.length ? view.commit.changedFiles - view.files.length : 0
            visible: rest > 0
            text: Logic.plural(rest, "more file") + " on GitHub"
            action: () => view.page.openExternally(view.commit.url)
        }

        GitHubLinkRow {
            visible: !!view.info && view.info.comments > 0
            icon: "chat_bubble"
            text: view.info ? Logic.plural(view.info.comments, "comment") + " on GitHub" : ""
            action: () => view.page.openExternally(view.commit.url + "#comments")
        }
    }

    // ---------------------------------------------------------- components

    // A pull request the commit belongs to, in its state's color; it opens
    // here.
    component PullChip: Rectangle {
        id: pullChip
        property var target: null
        height: 24
        width: Math.min(view.width, pullRow.implicitWidth + Theme.spacingM * 2)
        radius: 12
        color: pullArea.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.1) : Theme.withAlpha(Theme.surfaceText, 0.05)

        Row {
            id: pullRow
            anchors.verticalCenter: parent.verticalCenter
            x: Theme.spacingM
            spacing: Theme.spacingXS

            GitHubStatusIcon {
                anchors.verticalCenter: parent.verticalCenter
                item: pullChip.target
                size: 14
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, view.width - Theme.spacingM * 2 - 14 - Theme.spacingXS)
                text: pullChip.target ? "#" + pullChip.target.number + " " + pullChip.target.title : ""
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: pullArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: view.page.openItem(pullChip.target)
        }
    }
}
