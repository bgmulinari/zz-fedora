import QtQuick
import qs.Common
import qs.Widgets
import "GitHubLogic.js" as Logic

// A post's reactions as github.com draws them under it: a smiley that opens
// the eight reactions, and a chip per reaction given with its count, outlined
// in the accent where one is the viewer's. A click on a chip or in the picker
// adds or takes back the viewer's reaction at once, and puts it back if
// GitHub refuses (unless the post shown is another by then); resting the
// pointer on a chip shows who gave it (the page's card,
// GitHubDetail.showReactors). Without reactions and without the right to
// react (a locked conversation) it takes no room.
Flow {
    id: reactions

    // Logic.reactionsOf: { id, canReact, groups }, or null.
    property var info: null
    // The GitHubDetail the post is on, which closes the picker on a click
    // elsewhere.
    property var page: null
    readonly property var github: page ? page.github : null

    // What shows: GitHub's groups with the viewer's changes on top, until
    // the page brings the groups again.
    property var groups: info ? info.groups : ({})
    // content -> true while its change is on its way.
    property var pending: ({})
    property bool picking: false
    readonly property var chips: Logic.reactionChips(groups)
    readonly property bool canReact: !!info && info.canReact && !!github

    // Another post's reactions, or the same post's again from GitHub: what
    // was on its way no longer shows.
    onInfoChanged: {
        groups = info ? info.groups : {};
        pending = {};
        picking = false;
    }

    onPickingChanged: {
        if (!page)
            return;
        if (picking) {
            if (page.openPicker && page.openPicker !== reactions)
                page.openPicker.picking = false;
            page.openPicker = reactions;
        } else if (page.openPicker === reactions) {
            page.openPicker = null;
        }
    }

    // Whether a press at (x, y) of `item` lands on the picker or its
    // smiley, which handle it themselves.
    function holds(item, x, y) {
        return [smiley, pickerBox].some(part => part.visible && part.contains(item.mapToItem(part, x, y)));
    }

    Component.onDestruction: {
        if (page && page.openPicker === reactions)
            page.openPicker = null;
    }

    visible: !!info && (chips.length > 0 || canReact)
    spacing: Theme.spacingXS

    function toggle(content) {
        if (!canReact || pending[content])
            return;
        const subject = info;
        const on = !(groups[content] && groups[content].mine);
        groups = Logic.withReaction(groups, content, on);
        pending = Logic.withKey(pending, content, true);
        picking = false;
        github.react(subject.id, content, on, ok => {
            if (info !== subject)
                return;
            pending = Logic.withKey(pending, content, undefined);
            if (!ok)
                groups = Logic.withReaction(groups, content, !on);
        }, reactions);
    }

    function hideReactors(chip) {
        if (page)
            page.hideReactors(chip);
    }

    DankActionButton {
        id: smiley
        visible: reactions.canReact
        buttonSize: 26
        iconName: "add_reaction"
        iconSize: Theme.iconSizeSmall
        iconColor: reactions.picking ? Theme.primary : Theme.surfaceVariantText
        tooltipText: "Add a reaction"
        onClicked: reactions.picking = !reactions.picking
    }

    // The picker opens in place, before the chips, so it never needs room
    // above or below the post.
    Rectangle {
        id: pickerBox
        visible: reactions.picking
        width: pickerRow.implicitWidth + 4
        height: 26
        radius: 13
        color: Theme.withAlpha(Theme.surfaceText, 0.05)
        border.width: 1
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.8)

        Row {
            id: pickerRow
            anchors.centerIn: parent

            // Built as it opens.
            Repeater {
                model: reactions.picking ? Logic.REACTIONS : []

                Rectangle {
                    id: choice
                    required property var modelData
                    readonly property bool mine: !!reactions.groups[modelData.content] && reactions.groups[modelData.content].mine
                    width: 28
                    height: 22
                    radius: 11
                    color: mine ? Theme.withAlpha(Theme.primary, 0.18) : (choiceArea.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.1) : "transparent")

                    StyledText {
                        anchors.centerIn: parent
                        text: choice.modelData.emoji
                        font.pixelSize: Theme.fontSizeMedium
                    }

                    MouseArea {
                        id: choiceArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: reactions.toggle(choice.modelData.content)
                    }
                }
            }
        }
    }

    Repeater {
        model: reactions.chips

        Rectangle {
            id: chip
            required property var modelData
            width: chipRow.implicitWidth + Theme.spacingS * 2
            height: 26
            radius: 13
            color: modelData.mine ? Theme.withAlpha(Theme.primary, chipArea.containsMouse ? 0.24 : 0.14) : (chipArea.containsMouse && reactions.canReact ? Theme.withAlpha(Theme.surfaceText, 0.08) : "transparent")
            border.width: 1
            border.color: modelData.mine ? Theme.withAlpha(Theme.primary, 0.7) : Theme.withAlpha(Theme.outlineVariant, 0.8)
            opacity: reactions.pending[modelData.content] ? 0.6 : 1

            Row {
                id: chipRow
                anchors.centerIn: parent
                spacing: Theme.spacingXS

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: chip.modelData.emoji
                    font.pixelSize: Theme.fontSizeSmall + 1
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(chip.modelData.count)
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: chip.modelData.mine ? Font.DemiBold : Font.Normal
                    color: chip.modelData.mine ? Theme.primary : Theme.surfaceVariantText
                }
            }

            // Resting on a chip for a moment shows who gave it.
            Timer {
                id: rest
                interval: 400
                onTriggered: reactions.page.showReactors(chip, reactions.info.id, chip.modelData)
            }

            Component.onDestruction: reactions.hideReactors(chip)

            MouseArea {
                id: chipArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: reactions.canReact ? Qt.PointingHandCursor : Qt.ArrowCursor
                onEntered: {
                    if (reactions.page)
                        rest.restart();
                }
                onExited: {
                    rest.stop();
                    reactions.hideReactors(chip);
                }
                // The list changes with the click; the next rest asks again.
                onClicked: {
                    rest.stop();
                    reactions.hideReactors(chip);
                    reactions.toggle(chip.modelData.content);
                }
            }
        }
    }
}
