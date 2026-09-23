import QtQuick
import Quickshell.Io
import qs.Common
import qs.Widgets

// The list inside the modal: every bind as keycaps in a column the eye
// reads straight down, its name beside it, most-used first. Typing
// searches names, chords, and actions through fzf ("clwin", "wsp 3",
// "'vol"), best match first; a chord typed out in full jumps to the top.
// Arrow keys (or Ctrl+N/P, Ctrl+J/K) move, Enter runs the bind, Ctrl+E
// opens the bind editor in Settings, Escape clears the search and then
// closes.
Item {
    id: panel

    property var host: null
    // The modal: answers shouldBeVisible and close().
    property var parentPopout: null
    property real padding: Theme.spacingL

    property string filter: ""
    property int selectedIndex: 0
    property var displayRows: []
    // Where the pointer was first seen after the list last changed. A row
    // that appears under a resting pointer must not take the cursor from
    // the keyboard; real motion from that spot does.
    property point pointerOrigin: Qt.point(-1, -1)

    readonly property int rowHeight: 44
    readonly property int capHeight: 24
    readonly property real chordWidth: Math.round((width - padding * 2) * 0.42)
    readonly property int visibleRows: Math.max(1, Math.floor(listBox.height / rowHeight))
    readonly property var allRows: host ? host.rows : []
    readonly property bool showing: !!parentPopout && parentPopout.shouldBeVisible

    function normalizeChord(text) {
        return String(text || "").toLowerCase().replace(/\s*\+\s*/g, " ").replace(/\s+/g, " ").trim();
    }

    // A chord typed out in full ("super shift s") names one bind exactly;
    // fzf ranks it among every row holding those letters, so it is lifted
    // to the top here.
    function exactChord(row, query) {
        const chords = Array.isArray(row.chords) ? row.chords : [];
        const wanted = normalizeChord(query);
        return chords.some(chord => normalizeChord(chord) === wanted);
    }

    // fzf does the matching: `fzf --filter` over one line per row, the row
    // index then its search text (name, chord, raw key names, action), and
    // prints the matches best first, so the full fzf query syntax works
    // ('exact, ^prefix, !not, a | b). Ties keep the list's own order. One
    // search runs at a time; a query typed meanwhile runs when it ends.
    readonly property string finderScript: 'q=$1; shift; printf "%s\\n" "$@" | exec fzf --filter "$q" -i --delimiter "\\t" --nth 2.. --tiebreak index'

    function rebuild() {
        const query = filter.trim();
        if (!query) {
            displayRows = allRows;
            clampSelection();
            return;
        }
        if (finder.running)
            return;
        const lines = allRows.map((row, index) => index + "\t" + String(row.search || "").replace(/[\t\n]/g, " "));
        finder.query = query;
        finder.rows = allRows;
        finder.command = ["sh", "-c", finderScript, "sh", query].concat(lines);
        finder.running = true;
    }

    function applyMatches(query, rows, text) {
        if (query !== filter.trim())
            return;
        const matches = [];
        const lines = String(text || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const index = parseInt(lines[i], 10);
            if (!isNaN(index) && rows[index])
                matches.push(rows[index]);
        }
        const exact = matches.filter(row => exactChord(row, query));
        displayRows = exact.concat(matches.filter(row => !exactChord(row, query)));
        clampSelection();
        list.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    function clampSelection() {
        if (selectedIndex >= displayRows.length)
            selectedIndex = Math.max(0, displayRows.length - 1);
        pointerOrigin = Qt.point(-1, -1);
    }

    Process {
        id: finder
        property string query: ""
        property var rows: []
        running: false

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: panel.applyMatches(finder.query, finder.rows, text)
        }

        // fzf exits 1 when nothing matches, which is an empty list, not an
        // error. The query or the rows may have moved on while it ran.
        onExited: Qt.callLater(() => {
            if (panel.filter.trim() && (panel.filter.trim() !== finder.query || panel.allRows !== finder.rows))
                panel.rebuild();
        })
    }

    function setFilter(text) {
        text = String(text || "");
        if (text === filter)
            return;
        filter = text;
        selectedIndex = 0;
        rebuild();
        list.positionViewAtBeginning();
    }

    function clearFilter() {
        filter = "";
        if (field.text !== "")
            field.text = "";
    }

    function pointerMovedTo(item, x, y) {
        const pos = item.mapToItem(panel, x, y);
        if (pointerOrigin.x < 0) {
            pointerOrigin = Qt.point(pos.x, pos.y);
            return false;
        }
        return Math.abs(pos.x - pointerOrigin.x) + Math.abs(pos.y - pointerOrigin.y) >= 6;
    }

    function move(delta) {
        const count = displayRows.length;
        if (count === 0)
            return;
        selectedIndex = (selectedIndex + delta + count) % count;
        list.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    function moveTo(index) {
        const count = displayRows.length;
        if (count === 0)
            return;
        selectedIndex = Math.max(0, Math.min(count - 1, index));
        list.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    function runnable(row) {
        return !!row && Array.isArray(row.command) && row.command.length > 0;
    }

    // A bind the command line cannot run (Alt-Tab style recent-windows
    // actions) stays listed but only works from the keyboard, so picking it
    // leaves the list open.
    function activate(index) {
        const row = displayRows[index];
        if (runnable(row) && host)
            host.run(row);
    }

    function close() {
        if (parentPopout)
            parentPopout.close();
    }

    function handleKey(event) {
        const control = event.modifiers & Qt.ControlModifier;
        switch (event.key) {
        case Qt.Key_Down:
        case Qt.Key_Tab:
            move(1);
            break;
        case Qt.Key_Up:
        case Qt.Key_Backtab:
            move(-1);
            break;
        case Qt.Key_PageDown:
            moveTo(selectedIndex + visibleRows);
            break;
        case Qt.Key_PageUp:
            moveTo(selectedIndex - visibleRows);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            activate(selectedIndex);
            break;
        case Qt.Key_Escape:
            if (filter) {
                clearFilter();
                rebuild();
            } else {
                close();
            }
            break;
        case Qt.Key_E:
            if (!control)
                return;
            if (host)
                host.editBinds();
            break;
        case Qt.Key_N:
        case Qt.Key_J:
            if (!control)
                return;
            move(1);
            break;
        case Qt.Key_P:
        case Qt.Key_K:
            if (!control)
                return;
            move(-1);
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // The modal and its window hand focus around while it comes up, so one
    // forceActiveFocus at open time is not enough: keep asking until the
    // field has it, and take it back if it goes while the list is showing.
    function focusSearch() {
        field.forceActiveFocus();
        focusRetry.tries = 0;
        focusRetry.restart();
    }

    Timer {
        id: focusRetry
        interval: 40
        repeat: true
        property int tries: 0
        onTriggered: {
            if (!panel.showing || field.getActiveFocus() || ++tries > 25) {
                stop();
                return;
            }
            field.forceActiveFocus();
        }
    }

    // Every open starts over: no search, the cursor on the first row.
    function reset() {
        clearFilter();
        selectedIndex = 0;
        rebuild();
        list.positionViewAtBeginning();
        Qt.callLater(focusSearch);
    }

    onAllRowsChanged: rebuild()

    Connections {
        target: panel.parentPopout
        function onShouldBeVisibleChanged() {
            if (panel.parentPopout.shouldBeVisible)
                panel.reset();
        }
    }

    onParentPopoutChanged: {
        if (parentPopout && parentPopout.shouldBeVisible)
            reset();
    }

    Component.onCompleted: rebuild()

    // The search field forwards every key here first, so navigation wins
    // over text editing and the field only sees what is left.
    Item {
        id: keys
        width: 1
        height: 1
        Keys.onPressed: event => panel.handleKey(event)
    }

    Column {
        id: layout
        x: panel.padding
        y: panel.padding
        width: parent.width - panel.padding * 2
        height: parent.height - panel.padding * 2
        spacing: Theme.spacingS

        Item {
            id: header
            width: parent.width
            height: 40

            Row {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS

                DankIcon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "keyboard"
                    size: Theme.iconSize
                    color: Theme.primary
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    StyledText {
                        text: "Keybindings"
                        font.pixelSize: Theme.fontSizeLarge
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                    }

                    StyledText {
                        text: panel.filter
                            ? panel.displayRows.length + " of " + panel.allRows.length + " shortcuts"
                            : panel.allRows.length + " shortcuts"
                        visible: panel.allRows.length > 0
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }
                }
            }

            Row {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingXS

                Rectangle {
                    width: editRow.implicitWidth + Theme.spacingM * 2
                    height: 30
                    radius: 15
                    anchors.verticalCenter: parent.verticalCenter
                    color: editArea.containsMouse ? Theme.surfaceContainerHighest : "transparent"

                    Row {
                        id: editRow
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS

                        DankIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "edit"
                            size: Theme.iconSize - 6
                            color: Theme.surfaceText
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Edit"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceText
                        }
                    }

                    MouseArea {
                        id: editArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (panel.host)
                                panel.host.editBinds();
                        }
                    }
                }

                Rectangle {
                    width: 30
                    height: 30
                    radius: 15
                    anchors.verticalCenter: parent.verticalCenter
                    color: closeArea.containsMouse ? Theme.errorHover : "transparent"

                    DankIcon {
                        anchors.centerIn: parent
                        name: "close"
                        size: Theme.iconSize - 4
                        color: closeArea.containsMouse ? Theme.error : Theme.surfaceText
                    }

                    MouseArea {
                        id: closeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.close()
                    }
                }
            }
        }

        DankTextField {
            id: field
            width: parent.width
            height: 40
            leftIconName: "search"
            placeholderText: "Search by name or chord"
            showClearButton: true
            ignoreUpDownKeys: true
            ignoreTabKeys: true
            keyForwardTargets: [keys]
            onTextEdited: panel.setFilter(text)
            onFocusStateChanged: hasFocus => {
                if (!hasFocus && panel.showing)
                    Qt.callLater(panel.focusSearch);
            }
        }

        Item {
            id: listBox
            width: parent.width
            height: Math.max(panel.rowHeight, layout.height - header.height - field.height - footer.height - layout.spacing * 3)

            DankListView {
                id: list
                anchors.fill: parent
                clip: true
                model: panel.displayRows
                currentIndex: panel.selectedIndex
                spacing: 0

                delegate: Rectangle {
                    id: rowItem
                    required property int index
                    required property var modelData
                    readonly property bool selected: index === panel.selectedIndex

                    width: list.width
                    height: panel.rowHeight
                    radius: Theme.cornerRadius
                    color: selected ? Theme.withAlpha(Theme.primary, 0.16) : (rowArea.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.06) : "transparent")

                    // Chords line up in one column; one wider than the column
                    // pushes its own name right rather than losing keycaps.
                    Item {
                        id: chordBox
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(panel.chordWidth - Theme.spacingM, chordCaps.implicitWidth)
                        height: panel.capHeight

                        Row {
                            id: chordCaps
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingS

                            Repeater {
                                model: rowItem.modelData.caps || []

                                Row {
                                    id: chordRow
                                    required property int index
                                    required property var modelData
                                    spacing: 4

                                    StyledText {
                                        visible: chordRow.index > 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        rightPadding: Theme.spacingXS
                                        text: "or"
                                        font.pixelSize: Theme.fontSizeSmall
                                        color: Theme.surfaceVariantText
                                    }

                                    Repeater {
                                        model: chordRow.modelData

                                        Rectangle {
                                            id: cap
                                            required property var modelData
                                            width: Math.max(panel.capHeight, capText.implicitWidth + 12)
                                            height: panel.capHeight
                                            radius: 5
                                            color: rowItem.selected ? Theme.withAlpha(Theme.primary, 0.14) : Theme.surfaceContainerHighest
                                            border.width: 1
                                            border.color: rowItem.selected ? Theme.withAlpha(Theme.primary, 0.4) : Theme.outlineMedium

                                            StyledText {
                                                id: capText
                                                anchors.centerIn: parent
                                                text: String(cap.modelData)
                                                textFormat: Text.PlainText
                                                isMonospace: true
                                                font.pixelSize: Theme.fontSizeSmall
                                                font.weight: Font.DemiBold
                                                color: rowItem.selected ? Theme.primary : Theme.surfaceText
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    StyledText {
                        anchors.left: chordBox.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.right: runHint.left
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        text: rowItem.modelData.label
                        textFormat: Text.PlainText
                        font.pixelSize: Theme.fontSizeMedium
                        font.weight: rowItem.selected ? Font.DemiBold : Font.Normal
                        color: Theme.surfaceText
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }

                    DankIcon {
                        id: runHint
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        name: "keyboard_return"
                        size: Theme.iconSize - 6
                        color: Theme.primary
                        opacity: rowItem.selected && panel.runnable(rowItem.modelData) ? 1 : 0
                    }

                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onPositionChanged: mouse => {
                            if (panel.pointerMovedTo(rowArea, mouse.x, mouse.y) && panel.selectedIndex !== rowItem.index)
                                panel.selectedIndex = rowItem.index;
                        }
                        onClicked: panel.activate(rowItem.index)
                    }
                }
            }

            StyledText {
                anchors.centerIn: parent
                width: parent.width - Theme.spacingXL * 2
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                visible: panel.displayRows.length === 0
                text: {
                    if (panel.filter)
                        return "Nothing matches “" + panel.filter + "”";
                    if (panel.host && panel.host.error)
                        return panel.host.error;
                    if (panel.host && panel.host.loading)
                        return "Reading the keybindings…";
                    return "No keybindings found";
                }
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceVariantText
            }
        }

        Item {
            id: footer
            width: parent.width
            height: footerHint.implicitHeight

            StyledText {
                id: footerHint
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingXS
                text: "↑↓ move · ↵ run · esc close"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            StyledText {
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingXS
                text: "ctrl+e edit binds"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }
    }
}
