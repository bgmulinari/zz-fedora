import QtQuick
import qs.Common
import qs.Widgets
import "GitHubLogic.js" as Logic

// What the popout header shows of a page (GitHubDetail), beside its number
// and state (GitHubPanel): the title, wrapped (the header grows with it, up
// to three lines; a click on a longer one shows it whole, and on one shown
// whole goes back up the page), and under it who opened a pull request and
// its branches (base ← head), who opened an issue, or how a run started.
// That line keeps to one line: the head branch shortens to the room left,
// and past that the line is cut at the header's edge.
Column {
    id: compact

    property var page: null
    // A title longer than three lines, shown whole.
    property bool wholeTitle: false
    readonly property string title: page ? page.titleText : ""

    onTitleChanged: wholeTitle = false

    // Room between a wrapped title and the branch chips under it.
    spacing: Theme.spacingXS

    StyledText {
        id: titleText
        width: parent.width
        text: compact.title
        textFormat: Text.PlainText
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.Bold
        color: Theme.surfaceText
        wrapMode: Text.Wrap
        maximumLineCount: compact.wholeTitle ? 1000 : 3
        elide: Text.ElideRight

        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
                if (titleText.truncated)
                    compact.wholeTitle = true;
                else
                    compact.page.scrollToTop();
            }
        }
    }

    Item {
        id: line
        width: parent.width
        height: 22
        clip: true

        Row {
            readonly property bool isPr: !!compact.page && compact.page.kind === "pr"
            height: parent.height
            spacing: Theme.spacingXS

            GitHubLinkText {
                page: compact.page
                visible: !!compact.page && compact.page.kind !== "run" && !!compact.page.detail
                anchors.verticalCenter: parent.verticalCenter
                text: compact.page && compact.page.detail ? Logic.loginOf(compact.page.detail) : ""
                url: Logic.profileUrl(text)
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
                color: Theme.surfaceText
            }

            StyledText {
                visible: text !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: compact.page ? compact.page.compactText() : ""
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            StyledText {
                visible: parent.isPr && !!compact.page.detail
                anchors.verticalCenter: parent.verticalCenter
                text: "·"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            GitHubBranchChip {
                page: compact.page
                visible: parent.isPr && text !== ""
                anchors.verticalCenter: parent.verticalCenter
                maxWidth: 160
                text: parent.isPr && compact.page.detail ? compact.page.detail.baseRefName : ""
                url: parent.isPr && compact.page.item ? Logic.branchUrl(compact.page.item.repo, text) : ""
            }

            DankIcon {
                visible: parent.isPr && compact.page.headLabel !== ""
                anchors.verticalCenter: parent.verticalCenter
                name: "arrow_back"
                size: Theme.iconSizeSmall - 2
                color: Theme.surfaceVariantText
            }

            // What is left of the line after it, less the copy button.
            GitHubBranchChip {
                page: compact.page
                visible: parent.isPr && text !== ""
                anchors.verticalCenter: parent.verticalCenter
                maxWidth: Math.max(60, Math.min(220, line.width - x - headCopy.buttonSize - parent.spacing))
                text: parent.isPr ? compact.page.headLabel : ""
                url: parent.isPr ? compact.page.headUrl : ""
            }

            GitHubCopyButton {
                id: headCopy
                visible: parent.isPr && compact.page.headLabel !== ""
                anchors.verticalCenter: parent.verticalCenter
                buttonSize: 22
                github: compact.page ? compact.page.github : null
                copyText: compact.page ? compact.page.headLabel : ""
                toast: "Copied " + copyText
                tooltipText: "Copy the branch name"
            }
        }
    }
}
