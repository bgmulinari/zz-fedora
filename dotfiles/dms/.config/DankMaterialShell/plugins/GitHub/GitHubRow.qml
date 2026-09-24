import QtQuick
import qs.Common
import qs.Widgets
import "GitHubLogic.js" as Logic

// One pull request, issue, workflow run, or unread notification in the
// popout list: what it is and where it stands on the left, the title with
// its repository, age, and labels (small badges in their own colors), and
// on the right the CI state, the conversation size, how long a run took,
// or the spinner of a change in flight. The edge button opens the row on
// GitHub, or marks a notification read.
Rectangle {
    id: row

    property var item: null
    property var github: null
    property bool selected: false
    // The panel's clock, for a run still running (the rest say their age as
    // of when they were drawn: the list redraws them as it refreshes).
    property double now: Date.now()

    signal hovered()
    signal activated()
    signal markedRead()
    // Middle click: the row on GitHub.
    signal openedExternally()

    readonly property bool isRun: !!item && item.kind === "run"
    readonly property bool isNotification: !!item && item.kind === "notification"
    readonly property bool isBusy: !!github && !!item && !!github.busy[item.url]
    readonly property string checks: item && item.kind === "pr" ? String(item.checks || "") : ""
    // How long a run took, as GitHub's run list shows it (from its start to
    // its last update), counting while it runs.
    readonly property bool runActive: isRun && Logic.isActiveRun(item)
    readonly property string runTime: isRun ? (runActive ? Logic.duration(item.startedAt || item.createdAt, "", now) : Logic.duration(item.startedAt || item.createdAt, item.updatedAt)) : ""

    radius: Theme.cornerRadius
    color: selected ? Theme.withAlpha(Theme.primary, 0.16) : (area.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.06) : "transparent")

    function tinted(text, color) {
        return "<font color=\"" + String(color) + "\">" + Logic.escapeHtml(text) + "</font>";
    }

    // A row is one target: it opens the page, so its subtitle is plain text
    // (the page carries the links). Only the review state is colored, since
    // it is the part of a pull request row that says whether to act.
    function subtitle() {
        if (!item)
            return "";
        const parts = [item.repo.split("/")[1] || item.repo];
        if (isNotification) {
            parts.push(Logic.REASONS[item.reason] || item.reason, Logic.ago(item.updatedAt));
            return parts.map(Logic.escapeHtml).join(" · ");
        }
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

    GitHubStatusIcon {
        id: lead
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingM
        anchors.verticalCenter: parent.verticalCenter
        item: row.item
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
                font.weight: row.selected ? Font.DemiBold : Font.Normal
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
                height: 16

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
            visible: row.selected || area.containsMouse
            buttonSize: 28
            iconName: row.isNotification ? "done" : "open_in_new"
            iconSize: Theme.iconSizeSmall
            iconColor: Theme.surfaceVariantText
            tooltipText: row.isNotification ? "Mark as read (Del)" : "Open on GitHub"
            onClicked: row.isNotification ? row.markedRead() : row.openedExternally()
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        anchors.rightMargin: 36
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
