pragma Singleton
import QtQuick
import Quickshell

// The shell's theme, as far as the views under test read it.
Singleton {
    readonly property bool isLightMode: false
    readonly property real spacingXS: 4
    readonly property real spacingS: 8
    readonly property real spacingM: 12
    readonly property real spacingL: 16
    readonly property real cornerRadius: 12
    readonly property real iconSizeSmall: 16
    readonly property real fontSizeSmall: 12
    readonly property real fontSizeMedium: 14
    readonly property string monoFontFamily: "monospace"
    readonly property color primary: "#8ab4f8"
    readonly property color surfaceText: "#e6e1e5"
    readonly property color surfaceVariantText: "#cac4d0"
    readonly property color outlineVariant: "#49454f"

    function withAlpha(color, alpha) {
        return Qt.rgba(color.r, color.g, color.b, alpha);
    }
}
