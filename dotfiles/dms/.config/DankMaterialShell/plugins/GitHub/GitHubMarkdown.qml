import QtQuick
import qs.Common
import qs.Widgets
import "GitHubLogic.js" as Logic

// GitHub-flavored Markdown the way a popout can carry it. Qt's own
// Markdown mode packs blocks together, sizes inline code above the body
// text, and ignores the theme for links, so bodies are parsed
// (Logic.parseMarkdown, which lists the subset it reads) into blocks that
// each render as their own item, and inline markup becomes rich text styled
// from the shell theme. `#123` and `@user` link to GitHub like they do
// there. A long body shows its first blocks and a long code block its first
// lines, each with a way to show the rest. The text selects with the mouse
// across every block of the body (a drag from one paragraph into the next,
// or into a list or a code block) and copies with Ctrl+C, so the page it
// sits on scrolls by wheel, touchpad, or touch, not by a mouse drag. page
// is the GitHubDetail it sits on: it opens every link (images included),
// knows the repository a bare #123 belongs to and the signed URLs of the
// images, and takes the keys the body does not use.
Item {
    id: md

    property var page: null
    property string source: ""
    // owner/name, so a bare #123 can link to its issue or pull request.
    readonly property string repo: page && page.item ? page.item.repo : ""
    // Original image URL -> the signed URL GitHub rendered it from. Only
    // those URLs load; an image without one stays a link.
    readonly property var images: page ? page.images : ({})
    // How much of the source shows before "Show the whole post".
    readonly property int maxChars: 6000
    readonly property int codeLines: 40
    property bool expanded: false

    readonly property var style: ({
            "link": Theme.primary,
            "codeFont": Theme.monoFontFamily,
            "codeSize": Theme.fontSizeMedium - 1,
            "codeBackground": Theme.surfaceContainerHighest,
            "codeText": Theme.surfaceText,
            "border": Theme.outlineVariant
        })
    readonly property var blocks: Logic.parseMarkdown(source, repo, style)
    readonly property int fitting: Logic.blocksWithin(blocks, maxChars)
    readonly property var shownBlocks: expanded ? blocks : blocks.slice(0, fitting)

    onSourceChanged: expanded = false

    implicitHeight: column.implicitHeight

    function openLink(url) {
        if (page)
            page.openLink(url);
    }

    // Whether a point of the body is on something that takes its own
    // clicks (a picture, a "show more" row) rather than on text.
    function takesClick(x, y) {
        let item = column;
        let point = Qt.point(x, y);
        while (item) {
            if (item.takesClicks === true)
                return true;
            const child = item.childAt(point.x, point.y);
            if (!child)
                return false;
            point = item.mapToItem(child, point.x, point.y);
            item = child;
        }
        return false;
    }

    // ----------------------------------------------------------- selection
    //
    // Every block renders into its own read-only TextEdit, and a TextEdit
    // selects only within itself, so the body selects as a whole: each
    // text registers here, a mouse area over the body finds the text and
    // the character under the pointer, and the drag selects the tail of the
    // first text, every text between, and the head of the last.

    property var texts: []
    // The texts in reading order, worked out again only when they or their
    // places change (Qt.callLater collects a layout pass into one).
    property var orderedTexts: []
    property bool orderStale: true
    // Where the drag began and where it is: { index, pos } in reading order.
    property var anchorPoint: null
    property var focusPoint: null
    readonly property bool hasSelection: anchorPoint !== null && focusPoint !== null && (anchorPoint.index !== focusPoint.index || anchorPoint.pos !== focusPoint.pos)

    function register(text) {
        texts = texts.concat([text]);
        orderStale = true;
    }

    function unregister(text) {
        texts = texts.filter(other => other !== text);
        orderStale = true;
    }

    onHeightChanged: orderStale = true
    onWidthChanged: orderStale = true

    // The texts on screen, top to bottom, with where each begins.
    function ordered() {
        if (orderStale) {
            orderedTexts = texts.filter(text => text.visible && text.width > 0).map(text => ({
                        text: text,
                        top: text.mapToItem(md, 0, 0).y
                    })).sort((a, b) => a.top - b.top);
            orderStale = false;
        }
        return orderedTexts.map(entry => entry.text);
    }

    // The text and character at a point of the body; between two texts, the
    // end of the one above.
    function hit(x, y) {
        const list = ordered();
        if (list.length === 0)
            return null;
        let index = 0;
        for (let i = 0; i < orderedTexts.length; i++) {
            if (orderedTexts[i].top <= y)
                index = i;
        }
        const text = list[index];
        const local = md.mapToItem(text, x, y);
        let pos;
        if (local.y < 0)
            pos = 0;
        else if (local.y > text.height)
            pos = text.length;
        else
            pos = text.positionAt(Math.max(0, Math.min(text.width, local.x)), local.y);
        return {
            index: index,
            pos: pos,
            text: text,
            local: local
        };
    }

    function applySelection() {
        const list = ordered();
        if (!anchorPoint || !focusPoint) {
            for (const text of list)
                text.deselect();
            return;
        }
        const forward = anchorPoint.index < focusPoint.index || (anchorPoint.index === focusPoint.index && anchorPoint.pos <= focusPoint.pos);
        const from = forward ? anchorPoint : focusPoint;
        const to = forward ? focusPoint : anchorPoint;
        for (let i = 0; i < list.length; i++) {
            const text = list[i];
            if (i < from.index || i > to.index)
                text.deselect();
            else
                text.select(i === from.index ? from.pos : 0, i === to.index ? to.pos : text.length);
        }
    }

    function clearSelection() {
        anchorPoint = null;
        focusPoint = null;
        applySelection();
    }

    function selectAll() {
        const list = ordered();
        if (list.length === 0)
            return;
        anchorPoint = {
            index: 0,
            pos: 0
        };
        focusPoint = {
            index: list.length - 1,
            pos: list[list.length - 1].length
        };
        applySelection();
    }

    // What is selected, as plain text: a blank line between blocks, one
    // line per list item, and the text's own paragraph breaks as newlines.
    function selectedText() {
        let out = "";
        let previous = null;
        for (const text of ordered()) {
            const part = String(text.selectedText || "").replace(/[\u2028\u2029]/g, "\n");
            if (part === "")
                continue;
            if (previous)
                out += previous.inList && text.inList ? "\n" : "\n\n";
            out += part;
            previous = text;
        }
        return out;
    }

    function copySelection() {
        const text = selectedText();
        if (text !== "" && page && page.github)
            page.github.copy(text);
    }

    Keys.onPressed: event => {
        const control = event.modifiers & Qt.ControlModifier;
        if (control && event.key === Qt.Key_C && hasSelection) {
            copySelection();
            event.accepted = true;
        } else if (control && event.key === Qt.Key_A) {
            selectAll();
            event.accepted = true;
        } else if (page) {
            // Keys the body did not use (it takes focus on a click), so
            // the page's own keys keep working after text was selected.
            page.bodyKey(event);
        }
    }

    // A click elsewhere on the page drops the selection.
    onActiveFocusChanged: {
        if (!activeFocus)
            clearSelection();
    }

    // --------------------------------------------------------------- views

    Column {
        id: column
        width: parent.width
        spacing: Theme.spacingM

        Repeater {
            model: md.shownBlocks

            Loader {
                id: blockLoader
                required property var modelData
                required property int index
                readonly property var block: modelData
                readonly property bool first: index === 0

                width: md.width
                sourceComponent: ({
                        "heading": headingView,
                        "paragraph": paragraphView,
                        "quote": quoteView,
                        "code": codeView,
                        "list": listView,
                        "table": tableView,
                        "image": imageView,
                        "rule": ruleView
                    })[modelData.type] || paragraphView
            }
        }

        GitHubLinkRow {
            visible: md.shownBlocks.length < md.blocks.length
            icon: "unfold_more"
            text: "Show the whole post"
            action: () => md.expanded = true
        }
    }

    // The body's mouse: the pointer's shape, a drag that selects across
    // blocks, a double click on a word, and a click on a link. Presses on
    // anything else interactive (an image) pass through to it.
    MouseArea {
        id: pointer
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.IBeamCursor

        property point pressedAt
        property bool dragged: false

        function linkAt(at) {
            if (!at || at.local.y < 0 || at.local.y > at.text.height)
                return "";
            return at.text.linkAt(at.local.x, at.local.y);
        }

        function overText(at) {
            return !!at && at.local.x >= 0 && at.local.x <= at.text.width && at.local.y >= 0 && at.local.y <= at.text.height;
        }

        onPositionChanged: mouse => {
            if (!pressed) {
                const at = md.hit(mouse.x, mouse.y);
                cursorShape = linkAt(at) !== "" ? Qt.PointingHandCursor : (overText(at) ? Qt.IBeamCursor : Qt.ArrowCursor);
                return;
            }
            if (!dragged && Math.abs(mouse.x - pressedAt.x) + Math.abs(mouse.y - pressedAt.y) < 4)
                return;
            dragged = true;
            const at = md.hit(mouse.x, mouse.y);
            if (at) {
                md.focusPoint = {
                    index: at.index,
                    pos: at.pos
                };
                md.applySelection();
            }
        }

        onPressed: mouse => {
            // A picture or a "show more" row takes its own click.
            if (md.takesClick(mouse.x, mouse.y)) {
                mouse.accepted = false;
                return;
            }
            md.forceActiveFocus();
            pressedAt = Qt.point(mouse.x, mouse.y);
            dragged = false;
            const at = md.hit(mouse.x, mouse.y);
            md.anchorPoint = at ? {
                index: at.index,
                pos: at.pos
            } : null;
            md.focusPoint = md.anchorPoint;
            md.applySelection();
        }

        onReleased: mouse => {
            if (dragged)
                return;
            const url = linkAt(md.hit(mouse.x, mouse.y));
            if (url !== "")
                md.openLink(url);
        }

        onDoubleClicked: mouse => {
            const at = md.hit(mouse.x, mouse.y);
            if (!at)
                return;
            at.text.cursorPosition = at.pos;
            at.text.selectWord();
            md.anchorPoint = {
                index: at.index,
                pos: at.text.selectionStart
            };
            md.focusPoint = {
                index: at.index,
                pos: at.text.selectionEnd
            };
            md.applySelection();
        }
    }

    // The shell's text rendering, read off its own text item for the
    // selectable text below (a TextEdit, which StyledText is not).
    StyledText {
        id: themeText
        visible: false
    }

    // One block's text. The body's mouse area selects it (see selection
    // above), so it takes no mouse input of its own.
    component Selectable: GitHubTextView {
        // Copied one per line with its neighbours, not a paragraph apart.
        property bool inList: false

        width: parent ? parent.width : 0
        renderProbe: themeText
        selectByMouse: false
        activeFocusOnPress: false
        persistentSelection: true
        Component.onCompleted: md.register(this)
        Component.onDestruction: md.unregister(this)
    }

    // Rich text in a TextEdit has no lineHeight; the same spacing comes
    // from the block's CSS line-height.
    component RichBody: Selectable {
        property string html: ""
        property real lineHeight: 1.3

        textFormat: TextEdit.RichText
        text: "<div style=\"line-height:" + Math.round(lineHeight * 100) + "%\">" + html + "</div>"
    }

    Component {
        id: headingView

        RichBody {
            topPadding: parent.first ? 0 : Theme.spacingXS
            html: parent.block.html
            lineHeight: 1.1
            font.pixelSize: parent.block.level <= 2 ? Theme.fontSizeLarge : Theme.fontSizeMedium
            font.weight: Font.Bold
        }
    }

    Component {
        id: paragraphView

        RichBody {
            html: parent.block.html || ""
        }
    }

    Component {
        id: quoteView

        Item {
            implicitHeight: quoteText.implicitHeight

            Rectangle {
                width: 3
                height: parent.height
                radius: 1.5
                color: Theme.outlineVariant
            }

            RichBody {
                id: quoteText
                x: Theme.spacingM
                width: parent.width - x
                html: parent.parent.block.html
                color: Theme.surfaceVariantText
            }
        }
    }

    Component {
        id: codeView

        // Every character as written; a long block shows its first lines
        // until asked for all.
        Rectangle {
            id: codeBox
            readonly property var block: parent.block
            property bool whole: false
            readonly property bool cut: !whole && block.lines > md.codeLines
            implicitHeight: codeColumn.implicitHeight + Theme.spacingS * 2
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceText, 0.06)
            border.width: 1
            border.color: Theme.withAlpha(Theme.outlineVariant, 0.5)

            Column {
                id: codeColumn
                x: Theme.spacingM
                y: Theme.spacingS
                width: parent.width - Theme.spacingM * 2

                Selectable {
                    width: parent.width
                    text: codeBox.cut ? codeBox.block.text.split("\n").slice(0, md.codeLines).join("\n") : codeBox.block.text
                    textFormat: TextEdit.PlainText
                    isMonospace: true
                    wrapMode: TextEdit.WrapAnywhere
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                }

                GitHubLinkRow {
                    visible: codeBox.cut
                    icon: "unfold_more"
                    text: "Show all " + codeBox.block.lines + " lines"
                    action: () => codeBox.whole = true
                }
            }
        }
    }

    Component {
        id: listView

        Column {
            id: listColumn
            readonly property var items: parent.block.items
            spacing: Theme.spacingXS

            Repeater {
                model: listColumn.items

                Item {
                    id: listItem
                    required property var modelData
                    readonly property real indent: modelData.level * 18

                    width: listColumn.width
                    implicitHeight: itemText.implicitHeight

                    Item {
                        id: markerBox
                        x: listItem.indent
                        width: 20
                        height: Math.round(Theme.fontSizeMedium * 1.3)

                        Rectangle {
                            visible: listItem.modelData.task === "" && listItem.modelData.marker === ""
                            anchors.centerIn: parent
                            width: 5
                            height: 5
                            radius: 2.5
                            color: Theme.surfaceVariantText
                        }

                        StyledText {
                            visible: listItem.modelData.task === "" && listItem.modelData.marker !== ""
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            text: listItem.modelData.marker
                            font.pixelSize: Theme.fontSizeMedium
                            color: Theme.surfaceVariantText
                        }

                        DankIcon {
                            visible: listItem.modelData.task !== ""
                            anchors.centerIn: parent
                            name: listItem.modelData.task === "done" ? "check_box" : "check_box_outline_blank"
                            size: Theme.iconSizeSmall
                            color: listItem.modelData.task === "done" ? Theme.primary : Theme.surfaceVariantText
                        }
                    }

                    RichBody {
                        id: itemText
                        x: markerBox.x + markerBox.width + Theme.spacingXS
                        width: listItem.width - x
                        html: listItem.modelData.html
                        inList: true
                        color: listItem.modelData.task === "done" ? Theme.surfaceVariantText : Theme.surfaceText
                    }
                }
            }
        }
    }

    Component {
        id: tableView

        RichBody {
            html: parent.block.html
            font.pixelSize: Theme.fontSizeSmall
            lineHeight: 1.1
        }
    }

    // A picture at its natural size, narrowed to the column and capped in
    // height; a click opens it on GitHub at full size. Until GitHub's signed
    // URL is known the image is a link, and a failed load goes back to one.
    Component {
        id: imageView

        Item {
            id: imageBox
            readonly property var block: parent.block
            readonly property string signed: md.images[block.url] || ""
            readonly property bool failed: picture.status === Image.Error
            readonly property real naturalWidth: picture.implicitWidth > 0 ? picture.implicitWidth : width
            readonly property real ratio: picture.implicitWidth > 0 ? picture.implicitHeight / picture.implicitWidth : 0.5

            implicitHeight: signed === "" || failed ? fallback.implicitHeight : frame.height

            Rectangle {
                id: frame
                readonly property bool takesClicks: true
                visible: imageBox.signed !== "" && !imageBox.failed
                width: picture.status === Image.Ready ? Math.min(imageBox.width, imageBox.naturalWidth, 420 / imageBox.ratio) : imageBox.width
                height: picture.status === Image.Ready ? width * imageBox.ratio : 120
                radius: Theme.cornerRadius
                color: Theme.withAlpha(Theme.surfaceText, 0.05)
                border.width: 1
                border.color: Theme.withAlpha(Theme.outlineVariant, 0.5)

                Image {
                    id: picture
                    anchors.fill: parent
                    anchors.margins: 1
                    source: imageBox.signed
                    asynchronous: true
                    cache: true
                    smooth: true
                    mipmap: true
                    fillMode: Image.PreserveAspectFit
                }

                DankSpinner {
                    anchors.centerIn: parent
                    visible: picture.status === Image.Loading
                    size: 22
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: md.openLink(imageBox.block.href)
                }
            }

            RichBody {
                id: fallback
                visible: imageBox.signed === "" || imageBox.failed
                html: Logic.linkHtml(imageBox.block.href, Logic.escapeHtml("🖼 " + imageBox.block.alt), md.style)
            }
        }
    }

    Component {
        id: ruleView

        Item {
            implicitHeight: 1

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.withAlpha(Theme.outlineVariant, 0.6)
            }
        }
    }
}
