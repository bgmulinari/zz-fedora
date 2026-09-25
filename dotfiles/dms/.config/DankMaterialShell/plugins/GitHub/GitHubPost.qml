import QtQuick
import qs.Common
import qs.Widgets
import "GitHubLogic.js" as Logic

// One post of a page's conversation, as github.com draws it: a header bar
// (who, a review's verdict, when, and a copy of the Markdown), the body,
// its reactions, and, for a review, the inline threads it started. page is the
// GitHubDetail it sits on, which opens links and answers threads.
Rectangle {
    id: post

    property var page: null
    property string login: ""
    property string verb: ""
    property string verdict: ""
    property string stamp: ""
    property string stampUrl: ""
    property bool isAuthor: false
    property string source: ""
    property string placeholder: ""
    property var threads: []
    // Logic.reactionsOf, or null.
    property var reactions: null

    readonly property color verdictColor: verdict === "APPROVED" ? Theme.success : (verdict === "CHANGES_REQUESTED" ? Theme.error : Theme.surfaceVariantText)

    width: parent ? parent.width : 0
    implicitHeight: header.height + 1 + (body.visible ? body.implicitHeight + Theme.spacingM * 2 : 0)
    radius: Theme.cornerRadius
    color: Theme.withAlpha(Theme.surfaceText, 0.03)
    border.width: 1
    border.color: Theme.withAlpha(Theme.outlineVariant, 0.45)

    Item {
        id: header
        width: parent.width
        height: Math.max(36, headerFlow.implicitHeight + Theme.spacingS * 2)

        // Round at the top only: the rounded fill runs past the header's
        // bottom edge, which clips it square.
        Item {
            x: 1
            y: 1
            width: parent.width - 2
            height: parent.height - 1
            clip: true

            Rectangle {
                width: parent.width
                height: parent.height + radius
                radius: post.radius - 1
                color: Theme.withAlpha(Theme.surfaceText, 0.06)
            }
        }

        GitHubCopyButton {
            id: postCopy
            visible: post.source !== ""
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            github: post.page ? post.page.github : null
            copyText: post.source
            toast: "Copied the Markdown"
        }

        Flow {
            id: headerFlow
            x: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - Theme.spacingM - (postCopy.visible ? postCopy.width + Theme.spacingS * 2 : Theme.spacingM)
            spacing: Theme.spacingS

            GitHubAvatar {
                page: post.page
                login: post.login
                size: 20
            }

            GitHubLinkText {
                page: post.page
                height: 20
                verticalAlignment: Text.AlignVCenter
                text: post.login
                url: Logic.profileUrl(post.login)
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
                color: Theme.surfaceText
            }

            Rectangle {
                visible: post.isAuthor
                width: authorText.implicitWidth + Theme.spacingS * 2
                height: 20
                radius: 9
                color: "transparent"
                border.width: 1
                border.color: Theme.withAlpha(Theme.outlineVariant, 0.8)

                StyledText {
                    id: authorText
                    anchors.centerIn: parent
                    text: "Author"
                    font.pixelSize: Theme.fontSizeSmall - 1
                    color: Theme.surfaceVariantText
                }
            }

            StyledText {
                visible: post.verb !== ""
                height: 20
                verticalAlignment: Text.AlignVCenter
                text: post.verb
                font.pixelSize: Theme.fontSizeSmall
                color: post.verdictColor
            }

            GitHubLinkText {
                page: post.page
                height: 20
                verticalAlignment: Text.AlignVCenter
                text: post.stamp
                url: post.stampUrl
                external: true
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }
    }

    Rectangle {
        y: header.height
        x: 1
        width: parent.width - 2
        height: 1
        color: Theme.withAlpha(Theme.outlineVariant, 0.45)
    }

    Column {
        id: body
        // From the post's own content: a child's visible is false while
        // this column is hidden, so it cannot decide this column's.
        visible: post.source !== "" || post.placeholder !== "" || post.threads.length > 0 || !!post.reactions
        x: Theme.spacingM
        y: header.height + 1 + Theme.spacingM
        width: parent.width - Theme.spacingM * 2
        spacing: Theme.spacingS

        GitHubMarkdown {
            visible: post.source !== "" || post.placeholder !== ""
            width: parent.width
            page: post.page
            source: post.source !== "" ? post.source : post.placeholder
        }

        GitHubReactions {
            width: parent.width
            info: post.reactions
            page: post.page
        }

        Repeater {
            model: post.threads

            ReviewThread {
                required property var modelData
                width: body.width
                thread: modelData
            }
        }
    }

    // An inline review thread: the file and line, the code it is about, the
    // first comment and every reply, then Reply and Resolve. Resolved
    // threads start folded, as on GitHub; the header folds any thread.
    component ReviewThread: Rectangle {
        id: threadBox

        required property var thread
        // Logic.normalizeDetail gives every thread both.
        readonly property var comments: thread.comments.nodes
        readonly property int commentCount: thread.comments.totalCount
        readonly property var hunk: comments.length > 0 ? Logic.hunkLines(comments[0].diffHunk) : []
        readonly property int lineNumber: Number(thread.line || thread.originalLine || 0)
        property bool expanded: !thread.isResolved

        implicitHeight: threadColumn.implicitHeight
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceText, 0.03)
        border.width: 1
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.45)
        clip: true

        Column {
            id: threadColumn
            width: parent.width
            spacing: 0

            // File, line, state; a click folds or unfolds.
            Rectangle {
                width: parent.width
                height: 34
                color: threadHeaderArea.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.05) : "transparent"
                radius: Theme.cornerRadius

                MouseArea {
                    id: threadHeaderArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: threadBox.expanded = !threadBox.expanded
                }

                DankIcon {
                    id: foldIcon
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    name: threadBox.expanded ? "expand_more" : "chevron_right"
                    size: Theme.iconSizeSmall
                    color: Theme.surfaceVariantText
                }

                GitHubLinkText {
                    page: post.page
                    anchors.left: foldIcon.right
                    anchors.leftMargin: Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width - foldIcon.width - threadChips.width - Theme.spacingS * 4)
                    text: String(threadBox.thread.path || "") + (threadBox.lineNumber > 0 ? ":" + threadBox.lineNumber : "")
                    url: threadBox.comments.length > 0 ? String(threadBox.comments[0].url || "") : ""
                    external: true
                    isMonospace: true
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    wrapMode: Text.NoWrap
                    elide: Text.ElideLeft
                }

                Row {
                    id: threadChips
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS

                    StateTag {
                        visible: !!threadBox.thread.isOutdated
                        text: "Outdated"
                        tone: Theme.warning
                    }

                    StateTag {
                        visible: !!threadBox.thread.isResolved
                        text: "Resolved"
                        tone: Theme.success
                    }

                    StyledText {
                        visible: !threadBox.expanded
                        anchors.verticalCenter: parent.verticalCenter
                        text: threadBox.commentCount + (threadBox.commentCount === 1 ? " comment" : " comments")
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }
            }

            // The code under discussion.
            Rectangle {
                visible: threadBox.expanded && threadBox.hunk.length > 0
                width: parent.width
                height: hunkColumn.implicitHeight + Theme.spacingXS * 2
                color: Theme.withAlpha(Theme.surfaceText, 0.04)

                Column {
                    id: hunkColumn
                    y: Theme.spacingXS
                    width: parent.width

                    Repeater {
                        model: threadBox.expanded ? threadBox.hunk : []

                        Rectangle {
                            required property var modelData
                            readonly property string sign: String(modelData).charAt(0)
                            width: hunkColumn.width
                            height: hunkText.implicitHeight + 2
                            color: sign === "+" ? Theme.withAlpha(Theme.success, 0.13) : (sign === "-" ? Theme.withAlpha(Theme.error, 0.13) : "transparent")

                            StyledText {
                                id: hunkText
                                x: Theme.spacingS
                                y: 1
                                width: parent.width - Theme.spacingS * 2
                                text: String(parent.modelData)
                                textFormat: Text.PlainText
                                isMonospace: true
                                font.pixelSize: Theme.fontSizeSmall - 1
                                color: Theme.surfaceText
                                wrapMode: Text.NoWrap
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }

            // The comments, first to last.
            Repeater {
                model: threadBox.expanded ? threadBox.comments : []

                Column {
                    id: threadComment
                    required property var modelData
                    required property int index
                    x: Theme.spacingM
                    width: threadColumn.width - Theme.spacingM * 2
                    topPadding: Theme.spacingS
                    bottomPadding: Theme.spacingXS
                    spacing: Theme.spacingXS

                    Rectangle {
                        visible: threadComment.index > 0
                        width: parent.width
                        height: 1
                        color: Theme.withAlpha(Theme.outlineVariant, 0.3)
                    }

                    Item {
                        width: parent.width
                        height: commentHeader.height

                        Row {
                            id: commentHeader
                            spacing: Theme.spacingS

                            GitHubAvatar {
                                page: post.page
                                anchors.verticalCenter: parent.verticalCenter
                                login: Logic.loginOf(threadComment.modelData)
                                size: 16
                            }

                            GitHubLinkText {
                                page: post.page
                                anchors.verticalCenter: parent.verticalCenter
                                text: Logic.loginOf(threadComment.modelData)
                                url: Logic.profileUrl(text)
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.DemiBold
                                color: Theme.surfaceText
                            }

                            GitHubLinkText {
                                page: post.page
                                anchors.verticalCenter: parent.verticalCenter
                                text: Logic.when(threadComment.modelData.createdAt)
                                url: String(threadComment.modelData.url || "")
                                external: true
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                            }
                        }

                        GitHubCopyButton {
                            visible: copyText !== ""
                            anchors.right: parent.right
                            anchors.verticalCenter: commentHeader.verticalCenter
                            github: post.page ? post.page.github : null
                            copyText: String(threadComment.modelData.body || "")
                            toast: "Copied the Markdown"
                        }
                    }

                    GitHubMarkdown {
                        width: parent.width
                        page: post.page
                        source: String(threadComment.modelData.body || "")
                    }

                    GitHubReactions {
                        width: parent.width
                        info: Logic.reactionsOf(threadComment.modelData)
                        page: post.page
                    }
                }
            }

            // A thread longer than what was fetched says so.
            GitHubLinkRow {
                visible: threadBox.expanded && threadBox.commentCount > threadBox.comments.length
                x: Theme.spacingS
                width: threadColumn.width - Theme.spacingS * 2
                text: (threadBox.commentCount - threadBox.comments.length) + " more replies on GitHub"
                action: () => post.page.openExternally(threadBox.comments.length > 0 ? String(threadBox.comments[0].url || "") : post.page.itemUrl)
            }

            // Reply and Resolve, as far as GitHub allows the viewer.
            Flow {
                visible: threadBox.expanded && (!!threadBox.thread.viewerCanReply || !!threadBox.thread.viewerCanResolve || !!threadBox.thread.viewerCanUnresolve)
                x: Theme.spacingM
                width: threadColumn.width - Theme.spacingM * 2
                topPadding: Theme.spacingXS
                bottomPadding: Theme.spacingS
                spacing: Theme.spacingS

                GitHubPillButton {
                    visible: !!threadBox.thread.viewerCanReply
                    compact: true
                    usable: !post.page.isBusy
                    icon: "reply"
                    text: "Reply"
                    onActivated: post.page.startReply(threadBox.thread)
                }

                GitHubPillButton {
                    visible: !!threadBox.thread.viewerCanResolve && !threadBox.thread.isResolved
                    compact: true
                    usable: !post.page.isBusy
                    icon: "check"
                    text: "Resolve conversation"
                    onActivated: post.page.changeThread(threadBox.thread, "resolve")
                }

                GitHubPillButton {
                    visible: !!threadBox.thread.viewerCanUnresolve && !!threadBox.thread.isResolved
                    compact: true
                    usable: !post.page.isBusy
                    icon: "undo"
                    text: "Unresolve conversation"
                    onActivated: post.page.changeThread(threadBox.thread, "unresolve")
                }
            }
        }
    }

    component StateTag: Rectangle {
        property string text: ""
        property color tone: Theme.surfaceVariantText
        anchors.verticalCenter: parent ? parent.verticalCenter : undefined
        width: tagText.implicitWidth + Theme.spacingS * 2
        height: 18
        radius: 9
        color: Theme.withAlpha(tone, 0.14)

        StyledText {
            id: tagText
            anchors.centerIn: parent
            text: parent.text
            font.pixelSize: Theme.fontSizeSmall - 1
            font.weight: Font.Medium
            color: parent.tone
        }
    }
}
