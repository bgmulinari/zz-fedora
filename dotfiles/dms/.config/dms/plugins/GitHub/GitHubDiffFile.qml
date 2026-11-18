import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "GitHubLogic.js" as Logic

// One file of a commit as github.com's unified diff shows it: a header
// (fold, how it changed, its path, its additions and deletions with their
// blocks, a copy of the path, and the file on GitHub), then its hunks, each
// line numbered on both sides and tinted as added or deleted. A large diff
// starts folded, a long one shows its first lines with a way to the rest,
// and an empty or binary file (which GitHub's API does not tell apart) or
// a diff too large for the API says so.
Rectangle {
    id: diffFile

    property var page: null
    property var file: null
    property bool open: false
    // How many lines show before "Show more lines".
    property int shownLines: 400
    readonly property var lines: open && file ? Logic.diffLines(file.patch) : []
    readonly property var status: file ? Logic.fileStatus(file.status) : Logic.fileStatus("")
    readonly property int digits: {
        let most = 0;
        for (const line of lines)
            most = Math.max(most, line.old, line.new);
        return Math.max(2, String(most).length);
    }
    readonly property real gutter: digits * mono.averageCharacterWidth + Theme.spacingS * 2

    width: parent ? parent.width : 0
    implicitHeight: fileColumn.implicitHeight
    height: implicitHeight
    radius: Theme.cornerRadius
    color: "transparent"
    border.width: 1
    border.color: Theme.withAlpha(Theme.outlineVariant, 0.45)
    clip: true

    FontMetrics {
        id: mono
        font.family: Theme.monoFontFamily
        font.pixelSize: Theme.fontSizeSmall
    }

    Column {
        id: fileColumn
        width: parent.width

        // ---------- Header ----------
        Rectangle {
            width: parent.width
            height: 38
            color: Theme.withAlpha(Theme.surfaceText, 0.05)

            Row {
                id: lead
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                DActionButton {
                    anchors.verticalCenter: parent.verticalCenter
                    buttonSize: 24
                    iconSize: 16
                    iconName: diffFile.open ? "expand_more" : "chevron_right"
                    iconColor: Theme.surfaceVariantText
                    tooltipText: diffFile.open ? "Fold the diff" : "Show the diff"
                    onClicked: diffFile.open = !diffFile.open
                }

                GitHubStatusIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: Logic.glyph(diffFile.status.icon, diffFile.status.tone)
                    size: 16
                }
            }

            StyledText {
                id: path
                anchors.left: lead.right
                anchors.leftMargin: Theme.spacingS
                anchors.right: stats.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: diffFile.file ? (diffFile.file.previous !== "" && diffFile.file.previous !== diffFile.file.name ? diffFile.file.previous + " → " + diffFile.file.name : diffFile.file.name) : ""
                textFormat: Text.PlainText
                isMonospace: true
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
                color: Theme.surfaceText
                wrapMode: Text.NoWrap
                elide: Text.ElideLeft

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: diffFile.open = !diffFile.open
                }
            }

            Row {
                id: stats
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!diffFile.file && diffFile.file.additions > 0
                    text: diffFile.file ? "+" + diffFile.file.additions : ""
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: Theme.success
                }

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!diffFile.file && diffFile.file.deletions > 0
                    text: diffFile.file ? "−" + diffFile.file.deletions : ""
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: Theme.error
                }

                GitHubDiffstat {
                    anchors.verticalCenter: parent.verticalCenter
                    additions: diffFile.file ? diffFile.file.additions : 0
                    deletions: diffFile.file ? diffFile.file.deletions : 0
                }

                GitHubCopyButton {
                    anchors.verticalCenter: parent.verticalCenter
                    github: diffFile.page ? diffFile.page.github : null
                    copyText: diffFile.file ? diffFile.file.name : ""
                    toast: "Copied " + copyText
                    tooltipText: "Copy the path"
                }

                DActionButton {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: !!diffFile.file && diffFile.file.url !== "" && diffFile.file.status !== "removed"
                    buttonSize: 24
                    iconSize: 14
                    iconName: "description"
                    iconColor: Theme.surfaceVariantText
                    tooltipText: "View the file at this commit"
                    onClicked: diffFile.page.openLink(diffFile.file.url)
                }
            }
        }

        // ---------- Why there is no diff ----------
        Item {
            id: noDiff
            readonly property string why: {
                const f = diffFile.file;
                if (!f)
                    return "";
                if (f.binary)
                    return "No diff to show: an empty or a binary file.";
                if (f.patch === "")
                    return f.changes > 0 ? "This diff is too large to show here." : "File renamed without changes.";
                return diffFile.open ? "" : (f.changes > 400 ? "Large diffs are not rendered by default." : "This diff is folded.");
            }
            visible: why !== ""
            width: parent.width
            height: 44

            Row {
                anchors.centerIn: parent
                spacing: Theme.spacingS

                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    text: noDiff.why
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                GitHubLinkText {
                    visible: !!diffFile.file && diffFile.file.patch !== "" && !diffFile.open
                    anchors.verticalCenter: parent.verticalCenter
                    page: diffFile.page
                    text: "Load diff"
                    action: () => diffFile.open = true
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: Theme.primary
                }
            }
        }

        // ---------- Lines ----------
        Repeater {
            model: diffFile.lines.slice(0, diffFile.shownLines)

            Rectangle {
                id: line
                required property var modelData
                readonly property string type: modelData.type
                width: fileColumn.width
                height: Math.max(20, code.implicitHeight + 2)
                color: type === "add" ? Theme.withAlpha(Theme.success, 0.14) : (type === "del" ? Theme.withAlpha(Theme.error, 0.14) : (type === "hunk" ? Theme.withAlpha(Theme.primary, 0.08) : "transparent"))

                // The line numbers' gutter, a shade darker on a changed line.
                Rectangle {
                    width: diffFile.gutter * 2
                    height: parent.height
                    visible: line.type !== "hunk"
                    color: line.type === "add" ? Theme.withAlpha(Theme.success, 0.12) : (line.type === "del" ? Theme.withAlpha(Theme.error, 0.12) : "transparent")
                }

                StyledText {
                    visible: line.type !== "hunk"
                    width: diffFile.gutter - Theme.spacingS
                    y: 1
                    horizontalAlignment: Text.AlignRight
                    text: line.modelData.old > 0 ? String(line.modelData.old) : ""
                    isMonospace: true
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    visible: line.type !== "hunk"
                    x: diffFile.gutter
                    width: diffFile.gutter - Theme.spacingS
                    y: 1
                    horizontalAlignment: Text.AlignRight
                    text: line.modelData.new > 0 ? String(line.modelData.new) : ""
                    isMonospace: true
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    id: code
                    x: line.type === "hunk" ? Theme.spacingS : diffFile.gutter * 2 + Theme.spacingXS
                    y: 1
                    width: parent.width - x - Theme.spacingS
                    text: (line.type === "add" ? "+ " : (line.type === "del" ? "- " : (line.type === "context" ? "  " : ""))) + line.modelData.text
                    textFormat: Text.PlainText
                    isMonospace: true
                    font.pixelSize: Theme.fontSizeSmall
                    font.italic: line.type === "note"
                    color: line.type === "hunk" || line.type === "note" ? Theme.surfaceVariantText : Theme.surfaceText
                    wrapMode: Text.WrapAnywhere
                }
            }
        }

        GitHubLinkRow {
            visible: diffFile.lines.length > diffFile.shownLines
            text: "Show " + (diffFile.lines.length - diffFile.shownLines) + " more lines"
            icon: "unfold_more"
            action: () => diffFile.shownLines = diffFile.lines.length
        }
    }
}
