import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "GitHubLogic.js" as Logic

// One pull request, issue, workflow run, or notification in the popout
// list: what it is and where it stands on the left, the title with its
// repository, age, and labels (small badges in their own colors), an
// issue's sub-issue progress beside its title, and on the right, in
// columns as github.com lines them up, the CI state, the pull requests an
// issue is linked to (or the issues a pull request closes), the
// conversation size, and who is assigned; or how long a run took, or the
// spinner of a change in flight. The edge button opens the row on
// GitHub. A notification row is github.com's: a checkbox, a dot and a bold
// title while unread, its subject's state once known, why it came and
// when on the right, and under the pointer Done, Mark as read, and
// Unsubscribe in their place.
Rectangle {
    id: row

    property var item: null
    property var github: null
    property bool selected: false
    property bool checked: false
    // The panel's clock, for a run still running (the rest say their age as
    // of when they were drawn: the list redraws them as it refreshes).
    property double now: Date.now()
    // Which columns the list's pull request and issue rows fill
    // (Logic.rowColumns): this row keeps a slot for each, empty or not.
    property var columns: ({})

    signal hovered()
    signal activated()
    signal checkToggled()
    // An inbox action's key (Logic.INBOX_ACTIONS).
    signal acted(string key)
    // Middle click: the row on GitHub.
    signal openedExternally()

    readonly property bool isRun: !!item && item.kind === "run"
    readonly property bool isNotification: !!item && item.kind === "notification"
    readonly property bool unread: isNotification && !!github && github.isUnread(item)
    // A notification's subject as it stands now, once looked up.
    readonly property var subject: isNotification && github ? github.subjectOf(item) : null
    readonly property bool showActions: selected || pointer.hovered
    readonly property bool isBusy: !!github && !!item && !!github.busy[item.url]
    readonly property string checks: item && item.kind === "pr" ? String(item.checks || "") : ""
    // How long a run took, as GitHub's run list shows it (from its start to
    // its last update), counting while it runs.
    readonly property bool isItem: !!item && (item.kind === "pr" || item.kind === "issue")
    readonly property var subIssues: isItem && item.subIssues ? item.subIssues : null
    // Who is assigned and what is linked, once asked (GitHubData.extrasFor).
    readonly property var extra: isItem && github ? github.extrasFor(item) : null
    readonly property bool runActive: isRun && Logic.isActiveRun(item)
    readonly property string runTime: isRun ? (runActive ? Logic.duration(item.startedAt || item.createdAt, "", now) : Logic.duration(item.startedAt || item.createdAt, item.updatedAt)) : ""

    radius: Theme.cornerRadius
    color: selected ? Theme.withAlpha(Theme.primary, 0.16) : (pointer.hovered ? Theme.withAlpha(Theme.surfaceText, 0.06) : "transparent")

    // Over the whole row, the buttons included, so the buttons that show
    // under the pointer do not take the hover that shows them.
    HoverHandler {
        id: pointer
    }

    function tinted(text, color) {
        return "<font color=\"" + String(color) + "\">" + Logic.escapeHtml(text) + "</font>";
    }

    // A row is one target: it opens the page, so its subtitle is plain text
    // (the page carries the links). Only the review state is colored, since
    // it is the part of a pull request row that says whether to act.
    function subtitle() {
        if (!item)
            return "";
        if (isNotification)
            return Logic.escapeHtml(item.repo + (subject && subject.author ? " · " + subject.author : ""));
        const parts = [item.repo.split("/")[1] || item.repo];
        if (isRun) {
            if (item.workflowName)
                parts.push(String(item.workflowName));
            if (item.headBranch)
                parts.push(String(item.headBranch));
            parts.push(Logic.ago(item.createdAt));
            return parts.map(Logic.escapeHtml).join(" · ");
        }
        parts.push(item.author, Logic.ago(item.updatedAt));
        const html = parts.map(Logic.escapeHtml);
        if (item.kind === "pr") {
            const decision = Logic.decisionText(item.reviewDecision);
            if (item.isDraft)
                html.push("Draft");
            else if (item.reviewDecision === "APPROVED")
                html.push(tinted(decision, Theme.success));
            else if (item.reviewDecision === "CHANGES_REQUESTED")
                html.push(tinted(decision, Theme.error));
            else if (decision !== "")
                html.push(Logic.escapeHtml(decision));
        }
        return html.join(" · ");
    }

    // The unread dot sits in the gutter, left of the checkbox.
    Rectangle {
        visible: row.unread
        anchors.left: parent.left
        anchors.leftMargin: 3
        anchors.verticalCenter: parent.verticalCenter
        width: 6
        height: 6
        radius: 3
        color: Theme.primary
    }

    DActionButton {
        id: checkbox
        visible: row.isNotification
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        buttonSize: 28
        iconName: row.checked ? "check_box" : "check_box_outline_blank"
        iconSize: Theme.iconSizeSmall + 2
        iconColor: row.checked ? Theme.primary : Theme.surfaceVariantText
        onClicked: row.checkToggled()
    }

    GitHubStatusIcon {
        id: lead
        anchors.left: row.isNotification ? checkbox.right : parent.left
        anchors.leftMargin: row.isNotification ? Theme.spacingXS : Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        item: row.subject ? Object.assign({}, row.item, row.subject) : row.item
        size: Theme.iconSize - 2
    }

    Column {
        anchors.left: lead.right
        anchors.leftMargin: Theme.spacingM
        anchors.right: trail.left
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        // The number leads the title in the accent color: it is what gets
        // said out loud, typed into a search, and matched against a branch.
        Row {
            width: parent.width
            spacing: Theme.spacingS

            StyledText {
                id: number
                visible: !row.isRun && !!row.item && row.item.number > 0
                text: row.item ? "#" + row.item.number : ""
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.primary
            }

            StyledText {
                width: Math.min(implicitWidth, parent.width - (number.visible ? number.implicitWidth + parent.spacing : 0) - (progress.visible ? progress.width + parent.spacing : 0))
                text: row.item ? (row.isRun ? String(row.item.displayTitle || row.item.workflowName || "") : row.item.title) : ""
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeMedium
                font.weight: (row.isNotification ? row.unread : row.selected) ? Font.DemiBold : Font.Normal
                color: Theme.surfaceText
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }

            // Sub-issues done of all, as github.com shows them by the title.
            Rectangle {
                id: progress
                readonly property bool done: !!row.subIssues && row.subIssues.completed >= row.subIssues.total
                visible: !!row.subIssues
                anchors.verticalCenter: parent.verticalCenter
                width: progressRow.implicitWidth + 10
                height: 18
                radius: 9
                color: Theme.withAlpha(done ? Theme.primary : Theme.surfaceText, 0.1)

                Row {
                    id: progressRow
                    anchors.centerIn: parent
                    spacing: 3

                    DIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: progress.done ? "check_circle" : "donut_large"
                        size: Theme.iconSizeSmall - 4
                        color: progress.done ? Theme.primary : Theme.surfaceVariantText
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: row.subIssues ? row.subIssues.completed + " / " + row.subIssues.total : ""
                        font.pixelSize: Theme.fontSizeSmall - 1
                        font.features: {
                            "tnum": 1
                        }
                        color: progress.done ? Theme.primary : Theme.surfaceVariantText
                    }
                }
            }
        }

        // The labels follow the subtitle as badges no taller than its
        // line, so a row keeps its height; a badge that does not fit
        // whole is left out.
        Row {
            width: parent.width
            spacing: Theme.spacingS

            StyledText {
                id: subtitleText
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - (badges.visible ? Math.min(badgeRow.implicitWidth, 60) + parent.spacing : 0))
                text: row.subtitle()
                textFormat: Text.StyledText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
            }

            Item {
                id: badges
                readonly property var labels: row.item && !row.isRun && !row.isNotification ? (row.item.labels || []) : []
                visible: labels.length > 0
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(badgeRow.implicitWidth, parent.width - subtitleText.width - parent.spacing)
                height: badgeRow.implicitHeight

                Row {
                    id: badgeRow
                    spacing: 4

                    Repeater {
                        model: badges.labels

                        GitHubLabelChip {
                            required property var modelData
                            name: modelData.name
                            hex: modelData.color
                            compact: true
                            opacity: x + width <= badges.width ? 1 : 0
                        }
                    }
                }
            }
        }
    }

    // Over the row's click area, which would otherwise take the pointer's
    // hover from the avatars (their hover cards); a click on what takes
    // none here still reaches the row under it.
    Row {
        id: trail
        z: 1
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingS

        DSpinner {
            visible: row.isBusy
            anchors.verticalCenter: parent.verticalCenter
            size: 16
        }

        // Why the notification came and when, as github.com's inbox says
        // it on the right.
        StyledText {
            visible: row.isNotification && !row.showActions
            anchors.verticalCenter: parent.verticalCenter
            text: row.item ? (Logic.REASONS[row.item.reason] || row.item.reason) + " · " + Logic.ago(row.item.updatedAt) : ""
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        Repeater {
            model: row.isNotification && row.showActions ? Logic.INBOX_ACTIONS.filter(action => !action.unreadOnly || row.unread) : []

            DActionButton {
                required property var modelData
                anchors.verticalCenter: parent.verticalCenter
                buttonSize: 28
                iconName: modelData.icon
                iconSize: Theme.iconSizeSmall
                iconColor: Theme.surfaceVariantText
                tooltipText: modelData.label + " (" + modelData.shortcut + ")"
                onClicked: row.acted(modelData.key)
            }
        }

        // A pull request's checks, in their column.
        Item {
            visible: !row.isBusy && (row.isItem ? !!row.columns.checks : row.checks !== "")
            anchors.verticalCenter: parent.verticalCenter
            width: Theme.iconSizeSmall
            height: Theme.iconSizeSmall

            GitHubStatusIcon {
                visible: row.checks !== ""
                anchors.centerIn: parent
                outcome: Logic.outcome("", row.checks)
                size: Theme.iconSizeSmall
            }
        }

        // The pull requests an issue is linked to, or the issues a pull
        // request closes.
        Item {
            visible: !row.isBusy && row.isItem && !!row.columns.linked
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            height: linkedRow.implicitHeight

            Row {
                id: linkedRow
                visible: !!row.extra && row.extra.linked > 0
                anchors.right: parent.right
                spacing: 2

                // GitHub's glyph, in the color of where the links stand.
                GitHubOcticon {
                    readonly property var shown: row.extra ? row.extra.linkGlyph : null
                    anchors.verticalCenter: parent.verticalCenter
                    name: shown ? shown.icon : ""
                    size: Theme.iconSizeSmall - 2
                    color: shown ? ({
                            "success": Theme.success,
                            "accent": Theme.primary,
                            "error": Theme.error
                        })[shown.tone] || Theme.surfaceVariantText : Theme.surfaceVariantText
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.extra ? String(row.extra.linked) : ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }
        }

        Row {
            visible: !row.isBusy && row.runTime !== ""
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            DIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "timer"
                size: Theme.iconSizeSmall - 2
                color: Theme.surfaceVariantText
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: row.runTime
                font.pixelSize: Theme.fontSizeSmall
                font.features: {
                    "tnum": 1
                }
                color: Theme.surfaceVariantText
            }
        }

        Item {
            visible: !row.isBusy && row.isItem && !!row.columns.comments
            anchors.verticalCenter: parent.verticalCenter
            // Room for four digits.
            width: 46
            height: commentRow.implicitHeight

            Row {
                id: commentRow
                visible: !!row.item && row.item.comments > 0
                anchors.right: parent.right
                spacing: 2

                DIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chat_bubble"
                    size: Theme.iconSizeSmall - 2
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: row.item ? String(row.item.comments) : ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }
        }

        // Who is assigned, their pictures overlapping as on github.com: up
        // to three, or two and a disc saying how many more, so every row's
        // column is as wide (three pictures).
        Item {
            visible: !row.isBusy && row.isItem && !!row.columns.assignees
            anchors.verticalCenter: parent.verticalCenter
            width: 20 * 3 - 4 * 2
            height: 20

            Row {
                id: avatars
                readonly property var all: row.extra ? row.extra.assignees : []
                readonly property int count: row.extra ? Math.max(all.length, row.extra.assigneeCount) : 0
                readonly property var logins: count > 3 ? all.slice(0, 2) : all
                readonly property int more: count - logins.length
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: -4

                Repeater {
                    model: avatars.logins

                    GitHubAvatar {
                        required property var modelData
                        anchors.verticalCenter: parent.verticalCenter
                        login: modelData
                        size: 20
                        subjectId: row.item ? row.item.nodeId || "" : ""
                    }
                }

                Rectangle {
                    visible: avatars.more > 0
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20
                    radius: 10
                    color: Theme.surfaceContainerHigh
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.outlineVariant, 0.8)

                    StyledText {
                        anchors.centerIn: parent
                        text: "+" + Math.min(avatars.more, 99)
                        font.pixelSize: Theme.fontSizeSmall - 3
                        font.weight: Font.DemiBold
                        color: Theme.surfaceVariantText
                    }
                }
            }
        }

        // Every row keeps the button's room, shown or not, so the columns
        // stay put as the pointer moves down the list.
        Item {
            visible: !row.isNotification
            anchors.verticalCenter: parent.verticalCenter
            width: 28
            height: 28

            DActionButton {
                visible: row.showActions
                anchors.centerIn: parent
                buttonSize: 28
                iconName: "open_in_new"
                iconSize: Theme.iconSizeSmall
                iconColor: Theme.surfaceVariantText
                tooltipText: "Open on GitHub"
                onClicked: row.openedExternally()
            }
        }
    }

    // The checkbox and the buttons on the right take their own clicks.
    MouseArea {
        id: area
        anchors.fill: parent
        anchors.leftMargin: row.isNotification ? checkbox.x + checkbox.width : 0
        anchors.rightMargin: row.isNotification ? (row.showActions ? trail.width + Theme.spacingS : 0) : 36
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton
        onPositionChanged: row.hovered()
        onClicked: mouse => {
            if (mouse.button === Qt.MiddleButton)
                row.openedExternally();
            else
                row.activated();
        }
    }
}
