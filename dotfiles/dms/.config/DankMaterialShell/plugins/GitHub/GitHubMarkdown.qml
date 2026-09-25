import QtQuick
import qs.Common
import qs.Widgets
import "GitHubLogic.js" as Logic
import "GitHubMarkdown.js" as Markdown

// GitHub-flavored Markdown the way github.com shows it in an issue or a pull
// request. Qt's own Markdown mode packs blocks together, sizes inline code
// above the body text, and ignores the theme for links, so bodies are
// parsed (GitHubMarkdown.js, which lists what it reads) into blocks that
// each render as their own item, quotes, list items, and collapsible
// sections holding blocks of their own, and inline markup becomes rich
// text styled from the shell
// theme, sized and spaced after github.com's stylesheet. References and
// mentions link to GitHub like they do there. A long body shows its first
// blocks and a long code block its first lines, each with a way to show the
// rest. The text selects with the mouse across every block of the body (a
// drag from one paragraph into the next, or into a list, a table, or a code
// block) and copies with Ctrl+C, so the page it sits on scrolls by wheel,
// touchpad, or touch, not by a mouse drag. page is the GitHubDetail it sits
// on: it opens every link (images included), scrolls to what an in-page
// link names, knows the repository a bare #123 belongs to and the signed
// URLs of the images, and takes the keys the body does not use.
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
            "keyBackground": Theme.surfaceContainerHigh,
            "dark": !Theme.isLightMode,
            "mark": Theme.withAlpha(Theme.warning, 0.25)
        })
    readonly property var blocks: Markdown.parseMarkdown(source, repo, style)
    readonly property int fitting: Markdown.blocksWithin(blocks, maxChars)

    // Collapsible sections (<details>) the viewer opened or closed: id ->
    // open; the rest keep how the body has them (closed unless open).
    property var toggled: ({})

    onSourceChanged: {
        expanded = false;
        toggled = {};
    }

    function isOpen(section) {
        return section.id in toggled ? toggled[section.id] : section.open;
    }

    function toggleSection(section) {
        toggled = Logic.withKey(toggled, section.id, !isOpen(section));
    }

    implicitHeight: column.implicitHeight

    // ------------------------------------------------------------- links
    //
    // An in-page link (#section, a footnote and its way back) scrolls to
    // the block it names, opening the sections around it and the rest of a
    // long body first; every other link goes to the page.

    property var anchorItems: ({})

    function anchorBlock(loader) {
        for (const name of (loader.block.anchors || []))
            anchorItems[name] = loader;
    }

    function unanchorBlock(loader) {
        for (const name of (loader.block.anchors || []))
            if (anchorItems[name] === loader)
                delete anchorItems[name];
    }

    function openLink(url) {
        if (String(url).charAt(0) === "#") {
            revealAnchor(decodeURIComponent(String(url).slice(1)).replace(/^user-content-/, ""), false);
            return;
        }
        if (page)
            page.openLink(url);
    }

    function revealAnchor(name, tries) {
        const target = anchorItems[name];
        if (target) {
            Qt.callLater(() => {
                if (page && page.scrollToItem)
                    page.scrollToItem(target);
            });
            return;
        }
        // What is not built yet (past a long body's cut, in a closed
        // section) is shown, and then scrolled to.
        const path = (tries || 0) < 2 ? Markdown.anchorPath(blocks, name) : null;
        if (!path)
            return;
        if (path.index >= fitting)
            expanded = true;
        if (path.sections.some(id => toggled[id] !== true)) {
            const next = Object.assign({}, toggled);
            path.sections.forEach(id => next[id] = true);
            toggled = next;
        }
        Qt.callLater(() => revealAnchor(name, (tries || 0) + 1));
    }

    // Whether a point of the body is on something that takes its own
    // clicks (a picture, a "show more" row, a copy button) rather than on
    // text.
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

    // Where the pointer is over the body, for what shows on hover (a code
    // block's copy button); off the body, (-1, -1).
    property point pointerAt: Qt.point(-1, -1)

    function hovers(item) {
        if (pointerAt.x < 0)
            return false;
        const local = item.mapFromItem(md, pointerAt.x, pointerAt.y);
        return local.x >= 0 && local.y >= 0 && local.x <= item.width && local.y <= item.height;
    }

    // -------------------------------------------------------- highlighting
    //
    // Code in a language colors as github.com colors it (GitHubHighlighter,
    // KDE's syntax highlighting) when the module is installed; without it,
    // code stays one color. The component loads with the first code block.

    property var highlighter: undefined

    function highlight(edit, lang) {
        const lookup = Markdown.codeLookup(lang);
        if (!lookup)
            return;
        if (highlighter === undefined) {
            const component = Qt.createComponent("GitHubHighlighter.qml");
            highlighter = component.status === Component.Ready ? component : null;
        }
        if (!highlighter)
            return;
        const made = highlighter.createObject(edit);
        if (made.use(lookup))
            made.textEdit = edit;
        else
            made.destroy();
    }

    readonly property var views: ({
            "details": detailsView,
            "heading": headingView,
            "paragraph": paragraphView,
            "quote": quoteView,
            "code": codeView,
            "math": mathView,
            "list": listView,
            "table": tableView,
            "images": imagesView,
            "video": videoView,
            "rule": ruleView,
            "footnotes": footnotesView
        })

    // ----------------------------------------------------------- selection
    //
    // Every block renders into its own read-only TextEdit, and a TextEdit
    // selects only within itself, so the body selects as a whole: each
    // text registers here, a mouse area over the body finds the text and
    // the character under the pointer, and the drag selects the tail of the
    // first text, every text between, and the head of the last.

    property var texts: []
    // The texts in reading order (top to bottom, then left to right along
    // a table's row) with where each begins, and the texts alone, worked
    // out again only when they or their places change.
    property var orderedTexts: []
    property var orderedList: []
    property bool orderStale: true
    // Where the drag began and where it is: { index, pos } in reading order.
    property var anchorPoint: null
    property var focusPoint: null
    readonly property bool hasSelection: anchorPoint !== null && focusPoint !== null && (anchorPoint.index !== focusPoint.index || anchorPoint.pos !== focusPoint.pos)

    function register(text) {
        texts.push(text);
        orderStale = true;
    }

    function unregister(text) {
        const at = texts.indexOf(text);
        if (at >= 0)
            texts.splice(at, 1);
        orderStale = true;
    }

    onHeightChanged: orderStale = true
    onWidthChanged: orderStale = true

    // The texts on screen, in reading order, with where each begins.
    function ordered() {
        if (orderStale) {
            orderedTexts = texts.filter(text => text.visible && text.width > 0).map(text => {
                const at = text.mapToItem(md, 0, 0);
                return {
                    text: text,
                    top: at.y,
                    left: at.x
                };
            }).sort((a, b) => (a.top - b.top) || (a.left - b.left));
            orderedList = orderedTexts.map(entry => entry.text);
            orderStale = false;
        }
        return orderedList;
    }

    // The text and character at a point of the body; between two texts, the
    // end of the one above (or before it along a row).
    function hit(x, y) {
        const list = ordered();
        if (list.length === 0)
            return null;
        let last = 0;
        for (let i = 0; i < orderedTexts.length; i++) {
            if (orderedTexts[i].top <= y)
                last = i;
        }
        // Along a row of table cells (texts level with each other), the
        // cell under the pointer.
        let index = last;
        while (index > 0 && orderedTexts[index - 1].top === orderedTexts[last].top)
            index--;
        while (index < last && orderedTexts[index + 1].left <= x)
            index++;
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
    // line per list item or table row, a tab between a row's cells, and the
    // text's own paragraph breaks as newlines.
    function selectedText() {
        let out = "";
        let previous = null;
        for (const text of ordered()) {
            const part = String(text.selectedText || "").replace(/[\u2028\u2029]/g, "\n");
            if (part === "")
                continue;
            if (previous) {
                if (previous.row !== "" && previous.row === text.row)
                    out += "\t";
                else if ((previous.row !== "" && text.row !== "") || (previous.inList && text.inList))
                    out += "\n";
                else
                    out += "\n\n";
            }
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

        // What fits, and the rest once asked for: showing it adds to what
        // is built.
        BlockList {
            width: parent.width
            blocks: md.blocks.slice(0, md.fitting)
        }

        BlockList {
            visible: md.expanded
            width: parent.width
            blocks: md.expanded ? md.blocks.slice(md.fitting) : []
            atTop: false
        }

        GitHubLinkRow {
            visible: !md.expanded && md.fitting < md.blocks.length
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

        onExited: md.pointerAt = Qt.point(-1, -1)

        onPositionChanged: mouse => {
            md.pointerAt = Qt.point(mouse.x, mouse.y);
            if (!pressed) {
                const at = md.hit(mouse.x, mouse.y);
                cursorShape = md.takesClick(mouse.x, mouse.y) || linkAt(at) !== "" ? Qt.PointingHandCursor : (overText(at) ? Qt.IBeamCursor : Qt.ArrowCursor);
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

    // A column of blocks: the body's own, or what a quote, a list item, or a
    // section holds. Each block's view reads block, first, textColor, and
    // inList off the loader it sits in.
    component BlockList: Column {
        id: blockList

        property var blocks: []
        property color textColor: Theme.surfaceText
        property bool inList: false
        property real gap: Theme.spacingM
        // Whether its first block is the first of what holds it.
        property bool atTop: true

        spacing: gap

        Repeater {
            model: blockList.blocks

            Loader {
                required property var modelData
                required property int index
                readonly property var block: modelData
                readonly property bool first: blockList.atTop && index === 0
                readonly property color textColor: blockList.textColor
                readonly property bool inList: blockList.inList

                width: blockList.width
                sourceComponent: md.views[modelData.type] || paragraphView
                Component.onCompleted: md.anchorBlock(this)
                Component.onDestruction: md.unanchorBlock(this)
            }
        }
    }

    // One block's text. The body's mouse area selects it (see selection
    // above), so it takes no mouse input of its own.
    component Selectable: GitHubTextView {
        // Copied one per line with its neighbours, not a paragraph apart.
        property bool inList: false
        // A table cell's row, whose cells copy a tab apart.
        property string row: ""

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
        property string align: ""

        textFormat: TextEdit.RichText
        text: "<div align=\"" + (align || "left") + "\" style=\"line-height:" + Math.round(lineHeight * 100) + "%\">" + html + "</div>"
    }

    // A picture at its natural size (or the width the body gives it),
    // narrowed to the room it has and capped in height; a click opens it on
    // GitHub at full size. Until GitHub's signed URL is known the image is a
    // link, and a failed load goes back to one. One GitHub marked as
    // animated (a GIF) plays and loops, as it does there, from the local
    // copy the data layer makes of it (GitHubData.copyMedia), since Qt
    // plays a download only once, and only while it is on screen; without
    // a copy it shows still.
    component ImageTile: Item {
        id: tile

        property var image: ({})
        property real room: 0
        readonly property var rendered: md.images[image.url] || ({})
        // The signed URL it loads: the first GitHub gave, kept while it
        // loads (a page's reload brings new ones, which would load it
        // again), and a newer one once a load failed, which a signature
        // that expired does: the page is asked for new ones then, once.
        property string signed: ""
        property bool renewed: false
        readonly property bool failed: picture.status === Image.Error
        readonly property bool animated: !!rendered.animated
        // The animated image's local copy: "" until made, null when none
        // could be.
        property var copy: ""
        readonly property bool moves: animated && copy !== null
        readonly property Image picture: moves ? moving : still

        function takeSigned() {
            if (rendered.src && (signed === "" || failed))
                signed = rendered.src;
        }

        function fetchCopy() {
            if (!animated || signed === "" || copy !== "" || !md.page || !md.page.github)
                return;
            md.page.github.copyMedia(signed, file => {
                // The tile may be gone by the time the copy is made.
                if (Qt.isQtObject(tile))
                    tile.copy = file === "" ? null : file;
            });
        }

        onRenderedChanged: takeSigned()
        onFailedChanged: {
            if (failed && !renewed && md.page && md.page.refreshMedia) {
                renewed = true;
                md.page.refreshMedia();
            }
        }
        onSignedChanged: fetchCopy()
        onAnimatedChanged: fetchCopy()
        Component.onCompleted: {
            takeSigned();
            fetchCopy();
        }
        readonly property bool shown: signed !== "" && !failed
        readonly property bool ready: picture.status === Image.Ready
        readonly property real ratio: picture.implicitWidth > 0 ? picture.implicitHeight / picture.implicitWidth : 0.5
        readonly property real natural: image.width > 0 ? image.width : (ready ? picture.implicitWidth : room)

        width: shown ? Math.max(1, Math.min(room, natural, ready ? 420 / ratio : room)) : room
        height: shown ? (ready ? width * ratio : Math.min(120, width * ratio)) : fallback.implicitHeight

        Rectangle {
            readonly property bool takesClicks: true
            anchors.fill: parent
            visible: tile.shown
            color: tile.ready ? "transparent" : Theme.withAlpha(Theme.surfaceText, 0.05)
            radius: tile.ready ? 0 : Theme.cornerRadius

            // A picture of pixels (a screenshot) decodes no wider than the
            // widest a body shows one, at twice the pixels; a drawing (an
            // SVG badge) would scale up to that, so it keeps its size.
            Image {
                id: still
                anchors.fill: parent
                visible: !tile.moves
                source: tile.moves ? "" : tile.signed
                sourceSize.width: tile.rendered.raster ? 1600 : 0
                asynchronous: true
                cache: true
                smooth: true
                mipmap: true
                fillMode: Image.PreserveAspectFit
            }

            AnimatedImage {
                id: moving
                anchors.fill: parent
                visible: tile.moves
                source: tile.moves ? tile.copy : ""
                playing: tile.moves && tile.visible && (!md.page || !md.page.inView || md.page.inView(tile, md.page.viewY))
                asynchronous: true
                cache: false
                smooth: true
                fillMode: Image.PreserveAspectFit
            }

            DankSpinner {
                anchors.centerIn: parent
                visible: tile.picture.status === Image.Loading || (tile.moves && tile.copy === "")
                size: 22
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: md.openLink(tile.image.href)
            }
        }

        RichBody {
            id: fallback
            visible: !tile.shown
            html: Markdown.linkHtml(tile.image.href || "", Logic.escapeHtml("🖼 " + (tile.image.alt || "image")), md.style)
        }
    }

    // github.com's heading sizes (2em down to .85em), the two largest
    // ruled underneath.
    Component {
        id: headingView

        Item {
            id: heading
            readonly property var block: parent.block
            readonly property int level: block.level
            readonly property bool ruled: level <= 2

            implicitHeight: headingText.implicitHeight + (ruled ? Math.round(headingText.font.pixelSize * 0.3) + 1 : 0)

            RichBody {
                id: headingText
                topPadding: heading.parent.first ? 0 : Theme.spacingS
                html: heading.block.html
                align: heading.block.align || ""
                lineHeight: 1.25
                font.pixelSize: Math.round(Theme.fontSizeMedium * [2, 1.5, 1.25, 1, 0.875, 0.85][heading.level - 1])
                font.weight: Font.DemiBold
                color: heading.level === 6 ? Theme.surfaceVariantText : heading.parent.textColor
            }

            Rectangle {
                visible: heading.ruled
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.withAlpha(Theme.outlineVariant, 0.7)
            }
        }
    }

    Component {
        id: paragraphView

        RichBody {
            html: parent.block.html || ""
            align: parent.block.align || ""
            color: parent.textColor
            inList: parent.inList
        }
    }

    // A quote, muted behind a bar; an alert, its bar and title in its
    // color, its text as the body's.
    Component {
        id: quoteView

        Item {
            id: quote
            readonly property var block: parent.block
            readonly property string alert: block.alert || ""
            readonly property var kind: Markdown.ALERTS[alert] || null
            readonly property color tone: kind ? (Theme.isLightMode ? kind.light : kind.dark) : Theme.outlineVariant

            implicitHeight: quoteColumn.implicitHeight + (alert !== "" ? Theme.spacingXS * 2 : 0)

            Rectangle {
                width: 3
                height: parent.height
                color: quote.alert !== "" ? quote.tone : Theme.outlineVariant
            }

            Column {
                id: quoteColumn
                x: Theme.spacingM
                y: quote.alert !== "" ? Theme.spacingXS : 0
                width: parent.width - x
                spacing: Theme.spacingS

                Row {
                    visible: quote.alert !== ""
                    spacing: Theme.spacingS

                    DankIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: quote.kind ? quote.kind.icon : ""
                        size: Theme.iconSizeSmall
                        color: quote.tone
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: quote.alert.charAt(0).toUpperCase() + quote.alert.slice(1)
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: Font.Medium
                        color: quote.tone
                    }
                }

                BlockList {
                    width: parent.width
                    blocks: quote.block.blocks
                    gap: Theme.spacingS
                    textColor: quote.alert !== "" ? quote.parent.textColor : Theme.surfaceVariantText
                    inList: quote.parent.inList
                }
            }
        }
    }

    Component {
        id: codeView

        // Every character as written, colored by its language when that is
        // known (a diff's lines by what they do); a long block shows its
        // first lines until asked for all. The copy button shows on hover,
        // as on github.com; a suggestion says what it is, and a diagram or
        // map github.com draws shows as its source.
        Rectangle {
            id: codeBox
            readonly property var block: parent.block
            readonly property string lang: block.lang || ""
            readonly property bool suggestion: lang === "suggestion"
            readonly property bool diff: lang === "diff" || lang === "patch" || suggestion
            readonly property var drawn: ({
                    "mermaid": ["account_tree", "Mermaid diagram"],
                    "geojson": ["map", "GeoJSON map"],
                    "topojson": ["map", "TopoJSON map"],
                    "stl": ["view_in_ar", "3D model"]
                })[lang] || null
            property bool whole: false
            readonly property bool cut: !whole && block.lines > md.codeLines
            readonly property string shownText: cut ? block.text.split("\n").slice(0, md.codeLines).join("\n") : block.text
            readonly property bool hovered: md.hovers(codeBox)

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
                spacing: Theme.spacingXS

                Row {
                    visible: codeBox.suggestion || codeBox.drawn !== null
                    spacing: Theme.spacingXS

                    DankIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: codeBox.suggestion ? "edit_note" : (codeBox.drawn ? codeBox.drawn[0] : "")
                        size: Theme.iconSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: codeBox.suggestion ? "Suggested change" : (codeBox.drawn ? codeBox.drawn[1] + " (source)" : "")
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.Medium
                        color: Theme.surfaceVariantText
                    }
                }

                Selectable {
                    id: codeText
                    width: parent.width
                    text: codeBox.diff ? Markdown.diffHtml(codeBox.shownText, {
                        "added": Theme.success,
                        "addedBackground": Theme.withAlpha(Theme.success, 0.15),
                        "removed": Theme.error,
                        "removedBackground": Theme.withAlpha(Theme.error, 0.15),
                        "hunk": Theme.primary
                    }, codeBox.suggestion) : codeBox.shownText
                    textFormat: codeBox.diff ? TextEdit.RichText : TextEdit.PlainText
                    isMonospace: true
                    wrapMode: TextEdit.WrapAnywhere
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceText
                    Component.onCompleted: {
                        if (!codeBox.diff)
                            md.highlight(codeText, codeBox.lang);
                    }
                }

                GitHubLinkRow {
                    visible: codeBox.cut
                    icon: "unfold_more"
                    text: "Show all " + codeBox.block.lines + " lines"
                    action: () => codeBox.whole = true
                }
            }

            GitHubCopyButton {
                readonly property bool takesClicks: true
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: Theme.spacingXS
                visible: codeBox.hovered || copied
                github: md.page ? md.page.github : null
                copyText: codeBox.block.text
                tooltipText: "Copy"
            }
        }
    }

    // Display math, centered as MathJax sets it.
    Component {
        id: mathView

        RichBody {
            html: parent.block.html
            align: "center"
            font.pixelSize: Theme.fontSizeMedium + 2
            color: parent.textColor
        }
    }

    // Items hold blocks of their own. Bullets turn from discs to circles to
    // squares as lists nest, and numbers to roman numerals to letters
    // (GitHubMarkdown.js listMarker); a task shows its box.
    Component {
        id: listView

        Column {
            id: listColumn
            readonly property var block: parent.block
            readonly property bool ordered: block.ordered
            readonly property color textColor: parent.textColor
            // As wide as the longest number, right-aligned against the text.
            readonly property real markerWidth: ordered ? Math.max(20, markerMetrics.advanceWidth + 6) : 20
            readonly property real lineHeight: Math.round(Theme.fontSizeMedium * 1.3)

            TextMetrics {
                id: markerMetrics
                font.family: Theme.fontFamily
                font.pixelSize: Theme.fontSizeMedium
                text: listColumn.ordered ? listColumn.block.items.reduce((longest, item) => item.marker.length > longest.length ? item.marker : longest, "") : ""
            }

            spacing: block.loose ? Theme.spacingS : Theme.spacingXS

            Repeater {
                model: listColumn.block.items

                Item {
                    id: listItem
                    required property var modelData
                    readonly property bool bullet: !listColumn.ordered && modelData.task === ""

                    width: listColumn.width
                    implicitHeight: Math.max(itemBlocks.implicitHeight, listColumn.lineHeight)

                    Item {
                        id: markerBox
                        width: listColumn.markerWidth
                        height: listColumn.lineHeight

                        Rectangle {
                            visible: listItem.bullet
                            anchors.centerIn: parent
                            width: 6
                            height: 6
                            radius: listItem.modelData.marker === "square" ? 0 : 3
                            color: listItem.modelData.marker === "circle" ? "transparent" : listColumn.textColor
                            border.width: listItem.modelData.marker === "circle" ? 1 : 0
                            border.color: listColumn.textColor
                        }

                        StyledText {
                            visible: listColumn.ordered && listItem.modelData.task === ""
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            anchors.verticalCenter: parent.verticalCenter
                            text: listItem.modelData.marker
                            font.pixelSize: Theme.fontSizeMedium
                            color: listColumn.textColor
                        }

                        DankIcon {
                            visible: listItem.modelData.task !== ""
                            anchors.centerIn: parent
                            name: listItem.modelData.task === "done" ? "check_box" : "check_box_outline_blank"
                            size: Theme.iconSizeSmall
                            color: listItem.modelData.task === "done" ? Theme.primary : Theme.surfaceVariantText
                        }
                    }

                    BlockList {
                        id: itemBlocks
                        x: markerBox.width + Theme.spacingXS
                        width: listItem.width - x
                        blocks: listItem.modelData.blocks
                        textColor: listColumn.textColor
                        inList: true
                        gap: listColumn.block.loose ? Theme.spacingM : Theme.spacingXS
                    }
                }
            }
        }
    }

    // A table as github.com draws one: ruled cells, the header bold and
    // (unless its column says otherwise) centered, every other row tinted,
    // columns as wide as what they hold until the table has to share the
    // body's width. Cells of pictures show them.
    Component {
        id: tableView

        Item {
            id: table
            readonly property var block: parent.block
            readonly property var rows: [block.header].concat(block.rows)
            readonly property int columns: block.aligns.length
            readonly property real padX: 10
            readonly property real padY: 5
            // Each column's natural width, measured off its cells.
            property var natural: block.aligns.map(() => 0)
            readonly property var widths: Markdown.fitColumns(natural, width - 1, 48)
            // Where each column ends.
            readonly property var edges: {
                let x = 0;
                return widths.map(w => x += w);
            }
            readonly property real tableWidth: edges.length > 0 ? edges[edges.length - 1] : 0

            function measure(index, w) {
                if (w > natural[index]) {
                    const next = natural.slice();
                    next[index] = w;
                    natural = next;
                }
            }

            implicitHeight: grid.height + 1

            Column {
                id: grid
                y: 1

                Repeater {
                    model: table.rows

                    Rectangle {
                        id: rowBox
                        required property var modelData
                        required property int index
                        readonly property string key: String(table) + ":" + index

                        width: table.tableWidth
                        height: rowCells.height
                        color: index > 0 && index % 2 === 0 ? Theme.withAlpha(Theme.surfaceText, 0.04) : "transparent"

                        Row {
                            id: rowCells

                            Repeater {
                                model: table.columns

                                Item {
                                    id: cellBox
                                    required property int index
                                    readonly property var cell: rowBox.modelData[index] || ({
                                            "html": "",
                                            "images": []
                                        })
                                    readonly property bool header: rowBox.index === 0
                                    readonly property bool pictures: cell.images.length > 0

                                    width: table.widths[index] || 0
                                    height: (pictures ? cellImages.height : cellText.implicitHeight) + table.padY * 2

                                    Component.onCompleted: {
                                        if (pictures)
                                            table.measure(index, cell.images.reduce((sum, image) => sum + (image.width || 240) + Theme.spacingXS, 0) + table.padX * 2);
                                    }

                                    // The cell's width with nothing wrapped.
                                    Text {
                                        visible: false
                                        textFormat: Text.RichText
                                        text: cellBox.pictures ? "" : cellBox.cell.html
                                        font.family: Theme.fontFamily
                                        font.pixelSize: Theme.fontSizeMedium
                                        font.weight: cellBox.header ? Font.DemiBold : Theme.fontWeight
                                        onImplicitWidthChanged: table.measure(cellBox.index, implicitWidth + table.padX * 2 + 2)
                                    }

                                    RichBody {
                                        id: cellText
                                        visible: !cellBox.pictures
                                        x: table.padX
                                        y: table.padY
                                        width: parent.width - table.padX * 2
                                        html: cellBox.cell.html
                                        lineHeight: 1.25
                                        align: table.block.aligns[cellBox.index] || (cellBox.header ? "center" : "")
                                        font.weight: cellBox.header ? Font.DemiBold : Theme.fontWeight
                                        row: rowBox.key
                                    }

                                    Flow {
                                        id: cellImages
                                        visible: cellBox.pictures
                                        x: table.padX
                                        y: table.padY
                                        width: parent.width - table.padX * 2
                                        spacing: Theme.spacingXS

                                        Repeater {
                                            model: cellBox.pictures ? cellBox.cell.images : []

                                            ImageTile {
                                                required property var modelData
                                                image: modelData
                                                room: cellImages.width
                                            }
                                        }
                                    }
                                }
                            }
                        }

                        Rectangle {
                            width: parent.width
                            height: 1
                            y: -1
                            color: Theme.outlineVariant
                        }
                    }
                }
            }

            // The outer edge and the rules between columns.
            Rectangle {
                width: table.tableWidth + 1
                height: grid.height + 1
                color: "transparent"
                border.width: 1
                border.color: Theme.outlineVariant
            }

            Repeater {
                model: Math.max(0, table.columns - 1)

                Rectangle {
                    required property int index
                    x: table.edges[index]
                    width: 1
                    height: grid.height + 1
                    color: Theme.outlineVariant
                }
            }
        }
    }

    // A line of pictures, side by side as they fit.
    Component {
        id: imagesView

        Item {
            id: pictures
            readonly property var block: parent.block
            readonly property string align: block.align || ""

            implicitHeight: flow.implicitHeight

            Flow {
                id: flow
                readonly property real natural: {
                    let sum = 0;
                    for (let i = 0; i < children.length; i++)
                        sum += children[i].width + (i > 0 ? spacing : 0);
                    return sum;
                }
                width: Math.min(pictures.width, natural > 0 ? natural : pictures.width)
                x: pictures.align === "center" ? (pictures.width - width) / 2 : (pictures.align === "right" ? pictures.width - width : 0)
                spacing: Theme.spacingXS

                Repeater {
                    model: pictures.block.images

                    ImageTile {
                        required property var modelData
                        image: modelData
                        room: pictures.width
                    }
                }
            }
        }
    }

    // A video attachment, played in place as github.com does
    // (GitHubVideo.qml) once GitHub's signed URL for it is known, and only
    // while the page shows; until then, or without Qt Multimedia, a link to
    // it.
    Component {
        id: videoView

        Item {
            id: videoBox
            readonly property var block: parent.block
            readonly property var rendered: md.images[block.url] || ({})
            readonly property bool playable: !!rendered.src && player.status !== Loader.Error

            implicitHeight: playable ? player.implicitHeight : videoLink.height

            Loader {
                id: player
                width: parent.width
                active: !!videoBox.rendered.src
                visible: videoBox.playable
                source: "GitHubVideo.qml"
                onLoaded: {
                    item.source = Qt.binding(() => videoBox.rendered.src || "");
                    item.name = Qt.binding(() => videoBox.rendered.name || "");
                    item.active = Qt.binding(() => !md.page || md.page.active !== false);
                    item.openOutside = () => md.openLink(videoBox.block.url);
                    item.renew = done => {
                        if (md.page && md.page.refreshMedia)
                            md.page.refreshMedia(done);
                        else
                            done();
                    };
                }
            }

            GitHubLinkRow {
                id: videoLink
                visible: !videoBox.playable
                icon: "smart_display"
                text: "Video attachment"
                note: "Plays on GitHub"
                action: () => md.openLink(videoBox.block.url)
            }
        }
    }

    // A collapsible section as github.com draws it: its summary after a
    // triangle that turns as a click opens or closes it, and, open, what it
    // holds (built only then).
    Component {
        id: detailsView

        Column {
            id: section
            readonly property var block: parent.block
            readonly property bool open: md.isOpen(block)
            readonly property color textColor: parent.textColor
            readonly property bool inList: parent.inList

            spacing: Theme.spacingM

            Item {
                readonly property bool takesClicks: true
                width: parent.width
                height: summaryText.implicitHeight

                // Beside the summary's first line.
                DankIcon {
                    id: triangle
                    y: Math.round((summaryText.implicitHeight / Math.max(1, summaryText.lineCount) - height) / 2)
                    name: "arrow_right"
                    size: Theme.iconSize - 4
                    color: Theme.surfaceVariantText
                    rotation: section.open ? 90 : 0

                    Behavior on rotation {
                        NumberAnimation {
                            duration: Theme.shortDuration
                        }
                    }
                }

                StyledText {
                    id: summaryText
                    anchors.left: triangle.right
                    anchors.leftMargin: 2
                    anchors.right: parent.right
                    text: section.block.html
                    textFormat: Text.RichText
                    font.pixelSize: Theme.fontSizeMedium
                    color: section.textColor
                    wrapMode: Text.Wrap
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: md.toggleSection(section.block)
                }
            }

            Loader {
                width: parent.width
                active: section.open
                visible: active

                sourceComponent: BlockList {
                    blocks: section.block.blocks
                    textColor: section.textColor
                    inList: section.inList
                }
            }
        }
    }

    // github.com's rule: a band, not a hairline.
    Component {
        id: ruleView

        Item {
            implicitHeight: 4

            Rectangle {
                width: parent.width
                height: 3
                y: 0.5
                radius: 1.5
                color: Theme.withAlpha(Theme.outlineVariant, 0.8)
            }
        }
    }

    // The footnotes, numbered in the order the body cites them, small and
    // muted under a rule; each leads back to where it was cited.
    Component {
        id: footnotesView

        Column {
            id: notes
            readonly property var block: parent.block

            spacing: Theme.spacingXS

            Rectangle {
                width: notes.width
                height: 1
                color: Theme.outlineVariant
            }

            Item {
                width: 1
                height: Theme.spacingXS
            }

            Repeater {
                model: notes.block.items

                Item {
                    required property var modelData
                    required property int index

                    width: notes.width
                    implicitHeight: noteText.implicitHeight

                    StyledText {
                        width: 22
                        horizontalAlignment: Text.AlignRight
                        text: (parent.index + 1) + "."
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    RichBody {
                        id: noteText
                        x: 28
                        width: parent.width - x
                        html: parent.modelData.html
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        inList: true
                    }
                }
            }
        }
    }
}
