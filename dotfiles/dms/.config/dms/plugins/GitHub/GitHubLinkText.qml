import QtQuick
import qs.Widgets

// Text that is a link: underlined under the pointer, and opened through
// its page (GitHubDetail.openLink), which keeps pull requests, issues, runs,
// and searches in the popout. external sends it to the browser instead,
// for pages the popout would otherwise open in place (a comment's anchor);
// action, when set, runs instead of opening anything.
StyledText {
    id: linkText

    property var page: null
    property string url: ""
    property bool external: false
    property var action: null

    textFormat: Text.PlainText
    font.underline: (url !== "" || !!action) && linkArea.containsMouse

    MouseArea {
        id: linkArea
        anchors.fill: parent
        enabled: linkText.url !== "" || !!linkText.action
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: {
            if (linkText.action)
                linkText.action();
            else if (linkText.external)
                linkText.page.openExternally(linkText.url);
            else
                linkText.page.openLink(linkText.url);
        }
    }
}
