import QtQuick
import qs.Common
import qs.DCommon.Widgets

// A file's code as github.com shows it: the line numbers down the left,
// the lines unwrapped (the box scrolls sideways for a long one; the wheel
// still scrolls the page), colored by the file's language
// (GitHubHighlighter, with KDE's syntax highlighting installed), and
// selectable for copying. A long file shows its first lines and a way to
// show the rest. The lines an anchor names (#L10-L20) are tinted; mark is
// where the page scrolls to for them, a few lines above, as github.com
// leaves some code over them.
Item {
    id: code

    property var page: null
    property string text: ""
    // The file's name, which picks its language.
    property string fileName: ""
    property int line: 0
    property int lineEnd: 0
    // How many lines show before "Show all lines": enough for the marked
    // ones.
    property int shownLines: Math.max(1000, lineEnd + 50)

    readonly property var rows: text === "" ? [] : text.replace(/\n$/, "").split("\n")
    readonly property int shown: Math.min(rows.length, shownLines)
    readonly property real lineHeight: numbers.lineCount > 0 ? numbers.contentHeight / numbers.lineCount : 16
    readonly property real pad: Theme.spacingS
    readonly property Item mark: markTop

    width: parent ? parent.width : 0
    implicitHeight: column.implicitHeight

    Column {
        id: column
        width: parent.width

        Item {
            width: parent.width
            height: numbers.contentHeight + code.pad * 2

            Item {
                id: markTop
                visible: markRect.visible
                y: Math.max(0, markRect.y - code.lineHeight * 3)
                width: 1
                height: markRect.y - y + markRect.height
            }

            // The lines an anchor named.
            Rectangle {
                id: markRect
                visible: code.line > 0 && code.line <= code.shown
                width: parent.width
                y: code.pad + (code.line - 1) * code.lineHeight
                height: (Math.min(code.lineEnd, code.shown) - code.line + 1) * code.lineHeight
                color: Theme.withAlpha(Theme.warning, 0.16)
            }

            GitHubTextView {
                id: numbers
                x: Theme.spacingS
                y: code.pad
                width: Math.max(implicitWidth, 2 * Theme.fontSizeSmall)
                renderProbe: probe
                isMonospace: true
                wrapMode: TextEdit.NoWrap
                horizontalAlignment: TextEdit.AlignRight
                selectByMouse: false
                activeFocusOnPress: false
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                text: Array.from({
                    "length": code.shown
                }, (_, i) => String(i + 1)).join("\n")
            }

            DFlickable {
                id: scroller
                anchors.left: numbers.right
                anchors.leftMargin: Theme.spacingM
                anchors.right: parent.right
                height: parent.height
                horizontal: true
                fadeEdges: false
                contentWidth: Math.max(width, lines.implicitWidth + Theme.spacingM)
                contentHeight: height
                clip: true
                // A drag selects the code rather than scrolling it. DMS's
                // wheel handling is off: its WheelHandler blocks (Qt's
                // default) a vertical wheel it then declines, so the page
                // under the code would not scroll. Qt's own Flickable takes
                // a sideways wheel (a touchpad's swipe, a tilt wheel) and
                // lets a vertical one through to the page.
                acceptedButtons: Qt.NoButton
                wheelEnabled: false

                GitHubTextView {
                    id: lines
                    y: code.pad
                    width: Math.max(scroller.width, implicitWidth)
                    renderProbe: probe
                    isMonospace: true
                    wrapMode: TextEdit.NoWrap
                    selectByMouse: true
                    font.pixelSize: Theme.fontSizeSmall
                    text: code.rows.slice(0, code.shown).join("\n")
                    Component.onCompleted: code.highlight()
                }
            }
        }

        GitHubLinkRow {
            visible: code.shown < code.rows.length
            radius: 0
            icon: "unfold_more"
            text: "Show all " + code.rows.length.toLocaleString(Qt.locale("en_US"), "f", 0) + " lines"
            note: (code.rows.length - code.shown) + " more"
            action: () => code.shownLines = code.rows.length
        }
    }

    // The language's colors, once: the highlighter follows the text.
    property bool highlighted: false

    function highlight() {
        if (highlighted || fileName === "")
            return;
        highlighted = true;
        const component = Qt.createComponent("GitHubHighlighter.qml");
        if (component.status !== Component.Ready)
            return;
        const made = component.createObject(lines);
        if (made.use({
            "name": "",
            "file": fileName
        }))
            made.textEdit = lines;
        else
            made.destroy();
    }

    // The shell's text rendering, for the text views (see GitHubTextView).
    StyledText {
        id: probe
        visible: false
    }
}
