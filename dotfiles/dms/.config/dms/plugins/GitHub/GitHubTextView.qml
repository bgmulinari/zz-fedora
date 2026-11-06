import QtQuick
import qs.Common

// Read-only text in the shell's theme, which a Markdown block and a job's
// log both are: the theme's font (or its monospace one), text and
// selection colors, and the shell's own text rendering, read off a
// StyledText the page keeps (renderProbe; a TextEdit is no StyledText).
TextEdit {
    property Item renderProbe: null
    property bool isMonospace: false

    readOnly: true
    wrapMode: TextEdit.Wrap
    font.family: isMonospace ? Theme.monoFontFamily : Theme.fontFamily
    font.weight: Theme.fontWeight
    font.pixelSize: Theme.fontSizeMedium
    renderType: renderProbe ? renderProbe.renderType : TextEdit.NativeRendering
    color: Theme.surfaceText
    selectionColor: Theme.withAlpha(Theme.primary, 0.35)
    selectedTextColor: color
}
