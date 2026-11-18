import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "GitHubLogic.js" as Logic

// A repository's home as github.com shows it, its sidebar laid out above
// and below the files for a narrow popout: the About box (description,
// website, topics, license), the repository's tabs with their counts (its
// Issues, Pull requests, and Actions open as the panel's lists in that
// repository, its Releases and Commits as pages here), the default
// branch's latest commit over its files, the README, then the latest
// release and the languages. A file opens its page here, a folder on
// GitHub.
Column {
    id: view

    property var page: null
    readonly property var home: page ? page.detail : null
    readonly property string repo: home ? home.repo : ""
    // How many of the root's entries show before "Show more files".
    readonly property int filesShown: 12
    property bool allFiles: false

    width: parent ? parent.width : 0
    spacing: Theme.spacingL

    // ---------- About ----------
    Column {
        width: parent.width
        spacing: Theme.spacingS

        StyledText {
            visible: text !== ""
            width: parent.width
            text: view.home ? view.home.description : ""
            textFormat: Text.PlainText
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceText
            wrapMode: Text.Wrap
        }

        Flow {
            width: parent.width
            spacing: Theme.spacingM

            Fact {
                visible: !!view.home && view.home.homepage !== ""
                icon: "link"
                text: view.home ? view.home.homepage.replace(/^https?:\/\//, "").replace(/\/$/, "") : ""
                url: view.home ? view.home.homepage : ""
                strong: true
                accent: true
            }

            Fact {
                visible: !!view.home && view.home.license !== ""
                icon: "law"
                text: view.home ? view.home.license : ""
                url: view.home ? view.home.licenseUrl : ""
                external: true
            }

            Fact {
                visible: !!view.home && view.home.template !== ""
                icon: "repo-template"
                text: view.home ? "generated from " + view.home.template : ""
                url: view.home && view.home.template ? Logic.repoUrl(view.home.template) : ""
            }
        }

        // Topics, as github.com's tags: each opens its topic page on GitHub.
        Flow {
            visible: !!view.home && view.home.topics.length > 0
            width: parent.width
            spacing: Theme.spacingXS

            Repeater {
                model: view.home ? view.home.topics : []

                Rectangle {
                    id: topic
                    required property string modelData
                    height: 22
                    width: topicText.implicitWidth + Theme.spacingM
                    radius: height / 2
                    color: Theme.withAlpha(Theme.primary, topicArea.containsMouse ? 0.24 : 0.12)

                    StyledText {
                        id: topicText
                        anchors.centerIn: parent
                        text: topic.modelData
                        textFormat: Text.PlainText
                        font.pixelSize: Theme.fontSizeSmall - 1
                        font.weight: Font.Medium
                        color: Theme.primary
                    }

                    MouseArea {
                        id: topicArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: view.page.openExternally("https://github.com/topics/" + encodeURIComponent(topic.modelData))
                    }
                }
            }
        }
    }

    // ---------- Tabs ----------
    // The repository's tabs, as github.com heads its pages with them.
    Flow {
        width: parent.width
        spacing: Theme.spacingXS

        Repeater {
            model: {
                const h = view.home;
                if (!h)
                    return [];
                const tabs = [];
                if (h.issues >= 0)
                    tabs.push({
                        "icon": "issue-opened",
                        "text": "Issues",
                        "count": h.issues,
                        "list": "issues"
                    });
                tabs.push({
                    "icon": "git-pull-request",
                    "text": "Pull requests",
                    "count": h.pulls,
                    "list": "prs"
                }, {
                    "icon": "play",
                    "text": "Actions",
                    "count": -1,
                    "list": "actions"
                });
                if (h.discussions >= 0)
                    tabs.push({
                        "icon": "comment-discussion",
                        "text": "Discussions",
                        "count": h.discussions,
                        "url": Logic.repoUrl(h.repo) + "/discussions"
                    });
                tabs.push({
                    "icon": "tag",
                    "text": "Releases",
                    "count": h.releases,
                    "url": Logic.repoUrl(h.repo) + "/releases"
                }, {
                    "icon": "history",
                    "text": "Commits",
                    "count": h.commits,
                    "url": Logic.repoUrl(h.repo) + "/commits"
                });
                return tabs;
            }

            Rectangle {
                id: tabChip
                required property var modelData
                height: 30
                width: tabRow.implicitWidth + Theme.spacingM * 2
                radius: Theme.cornerRadius
                color: tabArea.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.1) : Theme.withAlpha(Theme.surfaceText, 0.04)
                border.width: 1
                border.color: Theme.withAlpha(Theme.outlineVariant, 0.4)

                Row {
                    id: tabRow
                    anchors.centerIn: parent
                    spacing: Theme.spacingXS + 2

                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 16
                        height: 16

                        GitHubOcticon {
                            visible: tabChip.modelData.icon !== "play"
                            name: tabChip.modelData.icon
                            size: 16
                            color: Theme.surfaceVariantText
                        }

                        DIcon {
                            visible: tabChip.modelData.icon === "play"
                            anchors.centerIn: parent
                            name: "play_circle"
                            size: 17
                            color: Theme.surfaceVariantText
                        }
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: tabChip.modelData.text
                        textFormat: Text.PlainText
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        color: Theme.surfaceText
                    }

                    // The count in a bubble, as github.com's tab counters.
                    Rectangle {
                        visible: tabChip.modelData.count >= 0
                        anchors.verticalCenter: parent.verticalCenter
                        height: 18
                        width: Math.max(18, countText.implicitWidth + Theme.spacingS + 2)
                        radius: height / 2
                        color: Theme.withAlpha(Theme.surfaceText, 0.12)

                        StyledText {
                            id: countText
                            anchors.centerIn: parent
                            text: Logic.shortCount(tabChip.modelData.count)
                            font.pixelSize: Theme.fontSizeSmall - 1
                            font.weight: Font.DemiBold
                            color: Theme.surfaceText
                        }
                    }
                }

                MouseArea {
                    id: tabArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (tabChip.modelData.list)
                            view.page.openList(tabChip.modelData.list);
                        else
                            view.page.openLink(tabChip.modelData.url);
                    }
                }
            }
        }
    }

    // ---------- Code ----------
    // The default branch, its latest commit, and its files, as the box at
    // the top of github.com's Code tab.
    Column {
        width: parent.width
        spacing: Theme.spacingS

        Row {
            width: parent.width
            spacing: Theme.spacingM

            GitHubBranchChip {
                anchors.verticalCenter: parent.verticalCenter
                page: view.page
                icon: "account_tree"
                text: view.home ? view.home.branch : ""
                url: view.home ? Logic.branchUrl(view.repo, view.home.branch) : ""
                visible: text !== ""
            }

            Fact {
                anchors.verticalCenter: parent.verticalCenter
                icon: "git-branch"
                text: view.home ? Logic.plural(view.home.branches, "branch", "branches") : ""
                url: view.repo ? Logic.repoUrl(view.repo) + "/branches" : ""
            }

            Fact {
                anchors.verticalCenter: parent.verticalCenter
                icon: "tag"
                text: view.home ? Logic.plural(view.home.tags, "tag") : ""
                url: view.repo ? Logic.repoUrl(view.repo) + "/tags" : ""
            }
        }

        Rectangle {
            width: parent.width
            height: files.implicitHeight
            radius: Theme.cornerRadius
            color: "transparent"
            border.width: 1
            border.color: Theme.withAlpha(Theme.outlineVariant, 0.45)
            clip: true

            Column {
                id: files
                width: parent.width

                // The latest commit heads the files, on a tint, with the
                // history's length beside it.
                Rectangle {
                    visible: !!view.home && !!view.home.head
                    width: parent.width
                    height: 40
                    color: Theme.withAlpha(Theme.surfaceText, 0.05)

                    GitHubCommitRow {
                        anchors.left: parent.left
                        anchors.right: history.left
                        anchors.verticalCenter: parent.verticalCenter
                        page: view.page
                        commit: view.home ? view.home.head : null
                        compact: true
                    }

                    Fact {
                        id: history
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        icon: "history"
                        text: view.home ? Logic.shortCount(view.home.commits) + (view.home.commits === 1 ? " commit" : " commits") : ""
                        url: view.repo ? Logic.repoUrl(view.repo) + "/commits" : ""
                        strong: true
                    }
                }

                Repeater {
                    model: view.home ? (view.allFiles ? view.home.entries : view.home.entries.slice(0, view.filesShown)) : []

                    GitHubEntryRow {
                        required property var modelData
                        page: view.page
                        radius: 0
                        icon: modelData.submodule ? "file-submodule" : (modelData.folder ? "file-directory-fill" : "file")
                        iconColor: modelData.folder ? Theme.primary : Theme.surfaceVariantText
                        text: modelData.name
                        url: modelData.url
                    }
                }

                // A long root folds after its first entries, so the README
                // is near.
                GitHubLinkRow {
                    visible: !!view.home && !view.allFiles && view.home.entries.length > view.filesShown
                    radius: 0
                    icon: "unfold_more"
                    text: view.home ? "Show " + (view.home.entries.length - view.filesShown) + " more files" : ""
                    action: () => view.allFiles = true
                }

                StyledText {
                    visible: !!view.home && view.home.entries.length === 0
                    width: parent.width
                    padding: Theme.spacingM
                    text: "This repository is empty."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }
        }
    }

    // ---------- README ----------
    GitHubReadme {
        page: view.page
    }

    // ---------- Releases ----------
    Column {
        width: parent.width
        spacing: Theme.spacingS
        visible: !!view.home && view.home.releases > 0

        SectionTitle {
            text: "Releases"
            count: view.home ? view.home.releases : 0
            url: view.repo ? Logic.repoUrl(view.repo) + "/releases" : ""
        }

        Row {
            visible: !!view.home && !!view.home.latestRelease
            width: parent.width
            spacing: Theme.spacingS

            GitHubOcticon {
                anchors.verticalCenter: parent.verticalCenter
                name: "tag"
                size: 16
                color: Theme.success
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 16 - parent.spacing

                Row {
                    spacing: Theme.spacingS

                    GitHubLinkText {
                        anchors.verticalCenter: parent.verticalCenter
                        page: view.page
                        text: view.home && view.home.latestRelease ? view.home.latestRelease.name : ""
                        url: view.home && view.home.latestRelease ? view.home.latestRelease.url : ""
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.DemiBold
                        color: Theme.surfaceText
                    }

                    GitHubBadge {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Latest"
                        tone: "success"
                    }
                }

                StyledText {
                    text: view.home && view.home.latestRelease ? Logic.when(view.home.latestRelease.publishedAt) : ""
                    textFormat: Text.PlainText
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }
        }
    }

    // ---------- Languages ----------
    // A bar of each language's share in its GitHub color, and the legend.
    Column {
        width: parent.width
        spacing: Theme.spacingS
        visible: !!view.home && view.home.languages.length > 0

        SectionTitle {
            text: "Languages"
        }

        Row {
            id: languageBar
            width: parent.width
            height: 8
            spacing: 2
            clip: true

            Repeater {
                model: view.home ? view.home.languages : []

                Rectangle {
                    required property var modelData
                    required property int index
                    width: Math.max(2, (languageBar.width - languageBar.spacing * (view.home.languages.length - 1)) * modelData.share)
                    height: languageBar.height
                    radius: 3
                    color: modelData.color !== "" ? modelData.color : Theme.withAlpha(Theme.surfaceText, 0.3)
                }
            }
        }

        Flow {
            width: parent.width
            spacing: Theme.spacingM

            Repeater {
                model: view.home ? view.home.languages : []

                Row {
                    required property var modelData
                    spacing: Theme.spacingXS

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 8
                        height: 8
                        radius: 4
                        color: parent.modelData.color !== "" ? parent.modelData.color : Theme.withAlpha(Theme.surfaceText, 0.3)
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.modelData.name
                        textFormat: Text.PlainText
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.DemiBold
                        color: Theme.surfaceText
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: parent.modelData.percent
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- components

    // A fact with its glyph, opening its page when it has one (here, or in
    // the browser when `external`).
    component Fact: Item {
        id: fact
        property string icon: ""
        property string text: ""
        property string url: ""
        property bool strong: false
        property bool accent: false
        property bool external: false
        implicitWidth: factRow.implicitWidth
        implicitHeight: 20

        Row {
            id: factRow
            height: parent.height
            spacing: Theme.spacingXS

            GitHubOcticon {
                anchors.verticalCenter: parent.verticalCenter
                name: fact.icon
                size: 14
                color: fact.accent ? Theme.primary : Theme.surfaceVariantText
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: fact.text
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeSmall
                font.weight: fact.strong ? Font.DemiBold : Font.Normal
                font.underline: factArea.containsMouse && fact.url !== ""
                color: fact.accent ? Theme.primary : (fact.strong ? Theme.surfaceText : Theme.surfaceVariantText)
            }
        }

        MouseArea {
            id: factArea
            anchors.fill: parent
            enabled: fact.url !== ""
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: fact.external ? view.page.openExternally(fact.url) : view.page.openLink(fact.url)
        }
    }

    // A sidebar section's heading, as github.com's: its name, and a count
    // in a bubble that, with the name, opens the section.
    component SectionTitle: Item {
        id: section
        property string text: ""
        property int count: -1
        property string url: ""
        implicitWidth: sectionRow.implicitWidth
        implicitHeight: 22

        Row {
            id: sectionRow
            height: parent.height
            spacing: Theme.spacingS

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: section.text
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.DemiBold
                font.underline: sectionArea.containsMouse && section.url !== ""
                color: Theme.surfaceText
            }

            Rectangle {
                visible: section.count >= 0
                anchors.verticalCenter: parent.verticalCenter
                height: 18
                width: Math.max(18, sectionCount.implicitWidth + Theme.spacingS + 2)
                radius: height / 2
                color: Theme.withAlpha(Theme.surfaceText, 0.12)

                StyledText {
                    id: sectionCount
                    anchors.centerIn: parent
                    text: Logic.shortCount(section.count)
                    font.pixelSize: Theme.fontSizeSmall - 1
                    font.weight: Font.DemiBold
                    color: Theme.surfaceText
                }
            }
        }

        MouseArea {
            id: sectionArea
            anchors.fill: parent
            enabled: section.url !== ""
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: view.page.openLink(section.url)
        }
    }
}
