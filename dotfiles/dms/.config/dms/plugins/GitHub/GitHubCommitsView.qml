import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "GitHubLogic.js" as Logic

// A branch's history as github.com's Commits page shows it: the commits by
// the day they were committed ("Commits on Nov 17, 2026"), each day a box
// of rows (GitHubCommitRow), newest first; the next 30 load as the end
// nears (GitHubBrowse.loadMore).
Column {
    id: view

    property var page: null
    readonly property var history: page ? page.detail : null
    readonly property var groups: history ? Logic.commitGroups(history.commits) : []

    width: parent ? parent.width : 0
    spacing: Theme.spacingM

    Repeater {
        model: view.groups

        Column {
            id: day
            required property var modelData
            width: view.width
            spacing: Theme.spacingS

            Row {
                spacing: Theme.spacingS

                GitHubOcticon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "git-commit"
                    size: 16
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Commits on " + day.modelData.day
                    textFormat: Text.PlainText
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.Medium
                    color: Theme.surfaceVariantText
                }
            }

            Rectangle {
                width: parent.width
                height: rows.implicitHeight
                radius: Theme.cornerRadius
                color: "transparent"
                border.width: 1
                border.color: Theme.withAlpha(Theme.outlineVariant, 0.45)
                clip: true

                Column {
                    id: rows
                    width: parent.width

                    Repeater {
                        model: day.modelData.commits

                        GitHubCommitRow {
                            required property var modelData
                            page: view.page
                            commit: modelData
                        }
                    }
                }
            }
        }
    }

    StyledText {
        visible: !!view.history && view.history.commits.length === 0
        width: parent.width
        text: "No commits here."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
    }

    GitHubPageFooter {
        page: view.page
        shown: view.history ? view.history.commits.length : 0
        total: view.history ? view.history.total : 0
        more: !!view.history && view.history.more
        noun: "commits"
    }
}
