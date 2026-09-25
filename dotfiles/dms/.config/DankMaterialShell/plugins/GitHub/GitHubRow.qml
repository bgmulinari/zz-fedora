import QtQuick
import qs.Common
import qs.Widgets
import "GitHubLogic.js" as Logic

// One pull request, issue, workflow run, or notification in the popout
// list: what it is and where it stands on the left, the title with its
// repository, age, and labels (small badges in their own colors), and on
// the right the CI state, the conversation size, how long a run took, or
// the spinner of a change in flight. The edge button opens the row on
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

    DankActionButton {
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
                width: parent.width - (number.visible ? number.implicitWidth + parent.spacing : 0)
                text: row.item ? (row.isRun ? String(row.item.displayTitle || row.item.workflowName || "") : row.item.title) : ""
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeMedium
                font.weight: (row.isNotification ? row.unread : row.selected) ? Font.DemiBold : Font.Normal
                color: Theme.surfaceText
                wrapMode: Text.NoWrap
                elide: Text.ElideRight
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

    Row {
        id: trail
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.spacingS

        DankSpinner {
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

            DankActionButton {
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

        GitHubStatusIcon {
            visible: !row.isBusy && row.checks !== ""
            anchors.verticalCenter: parent.verticalCenter
            outcome: Logic.outcome("", row.checks)
            size: Theme.iconSizeSmall
        }

        Row {
            visible: !row.isBusy && row.runTime !== ""
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            DankIcon {
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

        Row {
            visible: !row.isBusy && !row.isRun && !row.isNotification && !!row.item && row.item.comments > 0
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            DankIcon {
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

        DankActionButton {
            anchors.verticalCenter: parent.verticalCenter
            visible: !row.isNotification && row.showActions
            buttonSize: 28
            iconName: "open_in_new"
            iconSize: Theme.iconSizeSmall
            iconColor: Theme.surfaceVariantText
            tooltipText: "Open on GitHub"
            onClicked: row.openedExternally()
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
