import QtQuick
import qs.Common
import qs.Widgets

// Floating buttons over a page that jump to its top or its end, each shown
// only while it is more than half a view away from there.
Column {
    id: jumps

    // The Flickable the buttons move.
    property var target: null

    readonly property real firstY: target ? target.originY : 0
    readonly property real lastY: target ? target.originY + target.contentHeight - target.height : 0
    readonly property bool canUp: !!target && target.contentY - firstY > target.height / 2
    readonly property bool canDown: !!target && lastY - target.contentY > target.height / 2

    visible: canUp || canDown
    spacing: Theme.spacingXS

    function jump(toEnd) {
        glide.stop();
        glide.to = toEnd ? lastY : firstY;
        glide.start();
    }

    NumberAnimation {
        id: glide
        target: jumps.target
        property: "contentY"
        duration: Theme.mediumDuration
        easing.type: Easing.OutCubic
    }

    Repeater {
        model: [
            {
                "end": false,
                "icon": "vertical_align_top",
                "tip": "Scroll to the top"
            },
            {
                "end": true,
                "icon": "vertical_align_bottom",
                "tip": "Scroll to the end"
            }
        ]

        DankActionButton {
            required property var modelData
            visible: modelData.end ? jumps.canDown : jumps.canUp
            buttonSize: 32
            radius: buttonSize / 2
            iconName: modelData.icon
            iconSize: Theme.iconSizeSmall
            iconColor: Theme.surfaceText
            backgroundColor: Theme.surfaceContainerHighest
            border.width: 1
            border.color: Theme.withAlpha(Theme.outlineVariant, 0.8)
            tooltipText: modelData.tip
            tooltipSide: "left"
            onClicked: jumps.jump(modelData.end)
        }
    }
}
