import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "GitHubLogic.js" as Logic

// What the popout header shows of a repository's, a commit's, a release's,
// or a profile's page (GitHubBrowse.header), as github.com heads them: the
// owner's picture, a commit's SHA where a pull request has its number, the
// title (owner / name for a repository; wrapped to two lines, a click on a
// longer one shows it whole, otherwise goes back up the page) with its
// badges, and under it a line of what the page is about (the repository,
// a branch, a tag, stars, followers), each opening its page.
Row {
    id: browseHeader

    property var page: null
    readonly property var info: page ? page.header : null
    property bool wholeTitle: false

    onInfoChanged: wholeTitle = false

    spacing: Theme.spacingM

    GitHubAvatar {
        id: picture
        visible: !!browseHeader.info && browseHeader.info.avatar !== ""
        anchors.verticalCenter: parent.verticalCenter
        login: browseHeader.info ? browseHeader.info.avatar : ""
        square: !!browseHeader.info && browseHeader.info.square
        size: 36
        hovercard: false
    }

    // A commit's SHA, opening it on GitHub (so does Enter).
    GitHubLinkText {
        id: lead
        visible: !!browseHeader.info && browseHeader.info.lead !== ""
        anchors.verticalCenter: parent.verticalCenter
        page: browseHeader.page
        text: browseHeader.info ? browseHeader.info.lead : ""
        action: () => browseHeader.page.openOnGitHub()
        isMonospace: true
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.primary
    }

    Column {
        anchors.verticalCenter: parent.verticalCenter
        width: browseHeader.width - (picture.visible ? picture.width + browseHeader.spacing : 0) - (lead.visible ? lead.width + browseHeader.spacing : 0)
        spacing: 2

        Flow {
            width: parent.width
            spacing: Theme.spacingXS

            // The owner (its link underlined alone, as github.com's) and
            // the slash before the name.
            GitHubLinkText {
                visible: !!browseHeader.info && browseHeader.info.owner !== ""
                page: browseHeader.page
                height: titleText.lineHeightPx
                verticalAlignment: Text.AlignVCenter
                text: browseHeader.info ? browseHeader.info.owner : ""
                url: browseHeader.info ? Logic.profileUrl(browseHeader.info.owner) : ""
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceVariantText
            }

            StyledText {
                visible: !!browseHeader.info && browseHeader.info.owner !== ""
                height: titleText.lineHeightPx
                verticalAlignment: Text.AlignVCenter
                text: "/"
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceVariantText
            }

            StyledText {
                id: titleText
                readonly property real lineHeightPx: Math.ceil(fontMetrics.height)
                width: Math.min(implicitWidth, parent.width)
                text: browseHeader.info ? browseHeader.info.title : ""
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
                wrapMode: Text.Wrap
                maximumLineCount: browseHeader.wholeTitle ? 1000 : 2
                elide: Text.ElideRight

                FontMetrics {
                    id: fontMetrics
                    font: titleText.font
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (titleText.truncated)
                            browseHeader.wholeTitle = true;
                        else
                            browseHeader.page.scrollToTop();
                    }
                }
            }

            Repeater {
                model: browseHeader.info ? browseHeader.info.badges : []

                GitHubBadge {
                    required property var modelData
                    y: Math.round((titleText.lineHeightPx - height) / 2)
                    text: modelData.text
                    tone: modelData.tone
                }
            }
        }

        // One line, cut at the header's edge.
        Item {
            visible: !!browseHeader.info && browseHeader.info.line.length > 0
            width: parent.width
            height: 20
            clip: true

            Row {
                height: parent.height
                spacing: Theme.spacingM

                Repeater {
                    model: browseHeader.info ? browseHeader.info.line : []

                    Item {
                        id: part
                        required property var modelData
                        readonly property string url: modelData.url || ""
                        implicitWidth: partRow.implicitWidth
                        height: parent.height

                        Row {
                            id: partRow
                            height: parent.height
                            spacing: 4

                            GitHubOcticon {
                                visible: !!part.modelData.icon
                                anchors.verticalCenter: parent.verticalCenter
                                name: part.modelData.icon || ""
                                size: 12
                                color: part.modelData.icon === "star-fill" ? Theme.warning : Theme.surfaceVariantText
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: part.modelData.text
                                textFormat: Text.PlainText
                                isMonospace: !!part.modelData.mono
                                font.pixelSize: Theme.fontSizeSmall
                                font.underline: partArea.containsMouse && part.url !== ""
                                color: part.url !== "" ? Theme.surfaceText : Theme.surfaceVariantText
                            }
                        }

                        MouseArea {
                            id: partArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: part.url !== ""
                            cursorShape: Qt.PointingHandCursor
                            onClicked: browseHeader.page.openLink(part.url)
                        }
                    }
                }
            }
        }
    }
}
