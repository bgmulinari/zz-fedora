import QtQuick
import qs.Common
import qs.DCommon.Widgets

// A label as github.com outlines one beside a title: a repository's
// Public or Private, a release's Latest or Pre-release, Verified on a
// commit, in the tone's color (success, warning, error, accent, muted).
Rectangle {
    id: badge

    property string text: ""
    property string tone: "muted"
    readonly property color toneColor: ({
            "success": Theme.success,
            "warning": Theme.warning,
            "error": Theme.error,
            "accent": Theme.primary
        })[tone] || Theme.surfaceVariantText

    height: 20
    width: label.implicitWidth + Theme.spacingM
    radius: height / 2
    color: "transparent"
    border.width: 1
    border.color: Theme.withAlpha(toneColor, tone === "muted" ? 0.6 : 0.8)

    StyledText {
        id: label
        anchors.centerIn: parent
        text: badge.text
        textFormat: Text.PlainText
        font.pixelSize: Theme.fontSizeSmall - 1
        font.weight: Font.Medium
        color: badge.toneColor
    }
}
