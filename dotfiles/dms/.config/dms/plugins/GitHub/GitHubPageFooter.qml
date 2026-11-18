import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "GitHubLogic.js" as Logic

// The end of a page that loads in parts (a history, a list of releases):
// "30 of 48,236 commits" while the next part loads as the end nears, a way
// to ask for it when it failed or the page is too short to scroll, and the
// count alone once everything is there.
Item {
    id: footer

    property var page: null
    property int shown: 0
    property int total: 0
    property bool more: false
    property string noun: ""

    width: parent ? parent.width : 0
    height: 36

    Row {
        anchors.centerIn: parent
        spacing: Theme.spacingS

        DSpinner {
            visible: !!footer.page && footer.page.loadingMore
            anchors.verticalCenter: parent.verticalCenter
            size: 16
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: footer.total > 0 ? Logic.grouped(footer.shown) + " of " + Logic.grouped(footer.total) + " " + footer.noun : ""
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        GitHubLinkText {
            visible: footer.more && !!footer.page && !footer.page.loadingMore
            anchors.verticalCenter: parent.verticalCenter
            page: footer.page
            text: footer.page && footer.page.moreError !== "" ? "Try again" : "Load more"
            action: () => footer.page.loadMore()
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.DemiBold
            color: Theme.primary
        }
    }
}
