import QtQuick
import qs.Widgets
import "GitHubLogic.js" as Logic

// Text that is a link: underlined under the pointer, and opened through
// its page (GitHubDetail.openLink), which keeps pull requests, issues, runs,
// and searches in the popout. external sends it to the browser instead,
// for pages the popout would otherwise open in place (a comment's anchor);
// action, when set, runs instead of opening anything. A link to a person's
// or an organization's profile opens their hover card when the pointer
// rests on it, as their avatar does; a card's own links turn that off
// (hovercard).
StyledText {
    id: linkText

    property var page: null
    property string url: ""
    property bool external: false
    property var action: null
    property bool hovercard: true

    textFormat: Text.PlainText
    font.underline: (url !== "" || !!action) && linkArea.containsMouse

    GitHubCardSpot {
        anchors.fill: parent
        login: linkText.hovercard && linkArea.containsMouse && !linkText.action ? Logic.profileLoginOf(linkText.url) : ""
        subjectId: linkText.page && linkText.page.subjectId !== undefined ? linkText.page.subjectId : ""
    }

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
