import QtQuick
import qs.Common
import qs.Widgets
import "GitHubLogic.js" as Logic

// A status glyph: an item (a pull request, an issue, a run; itemState
// overrides its own state), an outcome (a job, a step, a check), or a glyph
// outright (Logic.glyph), in the color GitHub gives it (Logic.itemGlyph,
// Logic.outcomeGlyph); icon puts another icon in that color, and name and
// color can be set outright too. While it shows something running it
// becomes the shell's own spinner in the same color, since a rotated font
// glyph loses its antialiasing and the spinner is a drawn arc.
Item {
    id: statusIcon

    property var item: null
    property string itemState: ""
    property string outcome: ""
    property var glyph: null
    property string icon: ""
    readonly property var shown: glyph ? glyph : (item ? Logic.itemGlyph(item, itemState) : (outcome !== "" ? Logic.outcomeGlyph(outcome) : null))
    readonly property color toneColor: shown ? ({
            "success": Theme.success,
            "accent": Theme.primary,
            "error": Theme.error,
            "warning": Theme.warning,
            "plain": Theme.surfaceText
        })[shown.tone] || Theme.surfaceVariantText : Theme.surfaceText

    property string name: icon !== "" ? icon : (shown ? shown.icon : "")
    property color color: toneColor
    property real size: Theme.iconSize
    readonly property bool spinning: name === "progress_activity"

    implicitWidth: size
    implicitHeight: size

    DankIcon {
        visible: !statusIcon.spinning
        anchors.centerIn: parent
        name: statusIcon.name
        size: statusIcon.size
        color: statusIcon.color
    }

    DankSpinner {
        visible: statusIcon.spinning && statusIcon.visible
        anchors.centerIn: parent
        size: Math.round(statusIcon.size * 0.8)
        strokeWidth: Math.max(1.5, statusIcon.size / 9)
        color: statusIcon.color
    }
}
