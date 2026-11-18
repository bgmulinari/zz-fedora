import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "GitHubLogic.js" as Logic

// A README as github.com shows it under a repository's files or atop a
// profile: a box headed by its file name (opening its file page), holding
// its Markdown (GitHubMarkdown, its relative links and pictures resolved
// from the README's folder by the page). It says so while it loads, and
// takes no room when there is none.
Rectangle {
    id: readmeBox

    property var page: null
    // The heading: the file's name, or what a profile calls it.
    property string title: ""
    readonly property var readme: page ? page.readme : null

    visible: readme !== false
    width: parent ? parent.width : 0
    implicitHeight: readmeColumn.implicitHeight
    height: implicitHeight
    radius: Theme.cornerRadius
    color: "transparent"
    border.width: 1
    border.color: Theme.withAlpha(Theme.outlineVariant, 0.45)

    Column {
        id: readmeColumn
        width: parent.width

        Item {
            width: parent.width
            height: 36

            Row {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS

                GitHubOcticon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "book"
                    size: 16
                    color: Theme.surfaceVariantText
                }

                GitHubLinkText {
                    anchors.verticalCenter: parent.verticalCenter
                    page: readmeBox.page
                    text: readmeBox.title !== "" ? readmeBox.title : (readmeBox.readme ? readmeBox.readme.path.split("/").pop() : "README")
                    url: readmeBox.readme ? readmeBox.readme.url : ""
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: Theme.surfaceText
                }
            }

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.withAlpha(Theme.outlineVariant, 0.45)
            }
        }

        Item {
            width: parent.width
            height: readmeBox.readme ? markdown.implicitHeight + Theme.spacingL * 2 : 48

            StyledText {
                visible: !readmeBox.readme
                anchors.centerIn: parent
                text: "Loading the README…"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            GitHubMarkdown {
                id: markdown
                visible: !!readmeBox.readme
                x: Theme.spacingL
                y: Theme.spacingL
                width: parent.width - Theme.spacingL * 2
                page: readmeBox.page
                repo: readmeBox.readme ? readmeBox.readme.repo : ""
                source: readmeBox.readme ? readmeBox.readme.markdown : ""
            }
        }
    }
}
