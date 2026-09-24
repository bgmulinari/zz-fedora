import QtQuick
import qs.Common
import qs.Widgets

// Copies a text (a body's Markdown, a branch name) through the shell's
// clipboard; the icon turns into a check for a moment.
DankActionButton {
    id: copyButton

    property var github: null
    property string copyText: ""
    property string toast: ""
    property bool copied: false

    buttonSize: 24
    iconSize: 14
    iconName: copied ? "check" : "content_copy"
    iconColor: copied ? Theme.success : Theme.surfaceVariantText
    tooltipText: "Copy Markdown"
    onClicked: {
        if (!github)
            return;
        github.copy(copyText, toast);
        copied = true;
        copiedReset.restart();
    }

    Timer {
        id: copiedReset
        interval: 1500
        onTriggered: copyButton.copied = false
    }
}
