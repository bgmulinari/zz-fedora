import QtQuick
import qs.Common
import qs.Widgets

// The menu itself: the popout under the bar widget. It walks the inventory
// tree one group at a time, the way a menu does, with a search field that
// narrows the current group first and then everything below it. Arrow
// keys move, Enter opens, Backspace or Left goes up, Escape clears the
// search, goes up, then closes. Running a row closes the popout.
Item {
    id: panel

    property var inventory: null
    // The group id to open at, "" for the root; set before the popout opens.
    property string initialMenu: ""
    // The host: assigned by the popout host once this item is loaded, bound
    // by the modal host. Either answers shouldBeVisible and close().
    property var parentPopout: null
    // In a fixed-size host (the centered modal) the list takes the room
    // that is left instead of sizing the panel; padding insets everything.
    property bool fillMode: false
    property real padding: 0
    property bool started: false

    readonly property string rootLabel: "ZZ Menu"
    readonly property int rowHeight: 50
    property int maxVisibleRows: 9

    property string activeId: ""
    property var navStack: []
    property string filter: ""
    property int selectedIndex: 0
    property var displayRows: []
    property var nodes: ({})
    property var childrenOf: ({})
    // Where the pointer was first seen after the list last changed. A row
    // that appears under a resting pointer must not take the cursor from
    // the keyboard; real motion from that spot does.
    property point pointerOrigin: Qt.point(-1, -1)

    readonly property var activeNode: activeId && nodes[activeId] ? nodes[activeId] : null
    readonly property string activeLabel: activeNode ? activeNode.label : rootLabel
    readonly property string activeTrail: activeNode ? [rootLabel].concat(activeNode.path).join(" › ") + " ›" : ""
    readonly property int activeDepth: activeNode ? activeNode.path.length + 1 : 0
    // Emitted once the menu is on screen at its starting group, so the
    // widget can forget a group it was asked to open at.
    signal opened()

    readonly property var selectedRow: selectedIndex >= 0 && selectedIndex < displayRows.length ? displayRows[selectedIndex] : null

    implicitHeight: layout.implicitHeight + padding * 2

    // One map of every group and row keyed by id, and the ordered children
    // of every parent ("" is the root).
    function index() {
        const map = {};
        const kids = {};
        const groups = inventory ? inventory.groups : [];
        const rows = inventory ? inventory.rows : [];
        for (let i = 0; i < groups.length; i++) {
            const group = groups[i];
            map[group.id] = {
                id: group.id, kind: "group", parent: group.parent, label: group.label, icon: group.icon,
                description: group.description, path: group.path, order: group.order, search: group.search
            };
        }
        for (let i = 0; i < rows.length; i++) {
            const row = rows[i];
            map[row.id] = {
                id: row.id, kind: "action", parent: row.parent, label: row.label, icon: row.icon,
                description: row.description, path: row.path, order: row.order, search: row.search,
                action: row.action, terminal: row.terminal
            };
        }
        const ids = Object.keys(map);
        for (let i = 0; i < ids.length; i++) {
            const node = map[ids[i]];
            const parent = map[node.parent] ? node.parent : "";
            if (!kids[parent])
                kids[parent] = [];
            kids[parent].push(node);
        }
        const parents = Object.keys(kids);
        for (let i = 0; i < parents.length; i++)
            kids[parents[i]].sort((a, b) => a.order - b.order);
        nodes = map;
        childrenOf = kids;
    }

    function matches(node, terms) {
        for (let t = 0; t < terms.length; t++) {
            if (node.search.indexOf(terms[t]) < 0)
                return false;
        }
        return true;
    }

    function score(node, terms) {
        const label = node.label.toLowerCase();
        const query = terms.join(" ");
        if (label === query)
            return 4;
        if (label.indexOf(query) === 0)
            return 3;
        if (label.indexOf(query) >= 0)
            return 2;
        if (terms.every(term => label.indexOf(term) >= 0))
            return 1;
        return 0;
    }

    function display(node, deeper) {
        let subtitle = node.description;
        if (deeper) {
            const relative = node.path.slice(activeDepth).join(" › ");
            subtitle = relative + (node.description ? " · " + node.description : "");
        }
        return { id: node.id, kind: node.kind, label: node.label, icon: node.icon, subtitle: subtitle, node: node };
    }

    function collect(parentId, terms, direct, here, deeper) {
        const kids = childrenOf[parentId] || [];
        for (let i = 0; i < kids.length; i++) {
            const node = kids[i];
            if (matches(node, terms))
                (direct ? here : deeper).push({ node: node, score: score(node, terms) });
            if (node.kind === "group")
                collect(node.id, terms, false, here, deeper);
        }
    }

    function rebuild() {
        const terms = filter.toLowerCase().split(/\s+/).filter(term => term.length > 0);
        let list = [];
        if (terms.length === 0) {
            const kids = childrenOf[activeId] || [];
            for (let i = 0; i < kids.length; i++)
                list.push(display(kids[i], false));
        } else {
            const here = [];
            const deeper = [];
            collect(activeId, terms, true, here, deeper);
            const byScore = (a, b) => b.score - a.score || a.node.order - b.node.order;
            here.sort(byScore);
            deeper.sort(byScore);
            for (let i = 0; i < here.length; i++)
                list.push(display(here[i].node, false));
            for (let i = 0; i < deeper.length; i++)
                list.push(display(deeper[i].node, true));
        }
        displayRows = list;
        if (selectedIndex >= list.length)
            selectedIndex = Math.max(0, list.length - 1);
        pointerOrigin = Qt.point(-1, -1);
    }

    function pointerMovedTo(item, x, y) {
        const pos = item.mapToItem(panel, x, y);
        if (pointerOrigin.x < 0) {
            pointerOrigin = Qt.point(pos.x, pos.y);
            return false;
        }
        return Math.abs(pos.x - pointerOrigin.x) + Math.abs(pos.y - pointerOrigin.y) >= 6;
    }

    function openAt(menuId) {
        navStack = [];
        activeId = nodes[menuId] ? String(menuId) : "";
        clearFilter();
        selectedIndex = 0;
        rebuild();
    }

    function enter(menuId) {
        if (!nodes[menuId])
            return;
        navStack = navStack.concat([activeId]);
        activeId = String(menuId);
        clearFilter();
        selectedIndex = 0;
        rebuild();
    }

    function back() {
        if (!activeId)
            return false;
        let previous = "";
        if (navStack.length > 0) {
            previous = navStack[navStack.length - 1];
            navStack = navStack.slice(0, navStack.length - 1);
        } else if (activeNode) {
            previous = activeNode.parent;
        }
        activeId = nodes[previous] ? previous : "";
        clearFilter();
        selectedIndex = 0;
        rebuild();
        return true;
    }

    function clearFilter() {
        filter = "";
        if (field.text !== "")
            field.text = "";
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

    function activate(index) {
        const row = displayRows[index];
        if (!row)
            return;
        if (row.kind === "group") {
            enter(row.id);
            return;
        }
        if (inventory)
            inventory.run(row.node);
        close();
    }

    function close() {
        if (parentPopout)
            parentPopout.close();
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
            moveTo(selectedIndex + maxVisibleRows);
            break;
        case Qt.Key_PageUp:
            moveTo(selectedIndex - maxVisibleRows);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            activate(selectedIndex);
            break;
        case Qt.Key_Escape:
            if (filter)
                clearFilter(), rebuild();
            else if (!back())
                close();
            break;
        case Qt.Key_Left:
            if (filter)
                return;
            back();
            break;
        case Qt.Key_Right:
            if (filter || !selectedRow || selectedRow.kind !== "group")
                return;
            enter(selectedRow.id);
            break;
        case Qt.Key_Backspace:
            if (filter)
                return;
            back();
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

    readonly property bool showing: !!parentPopout && parentPopout.shouldBeVisible

    // The host and its window hand focus around while the popout comes up
    // (the content container asks for it after the content is shown), so
    // one forceActiveFocus at open time is not enough: keep asking until
    // the field has it, and take it back if it goes while the popout is
    // still showing. The field is the only thing here that takes keys.
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

    function reset() {
        started = true;
        if (inventory)
            inventory.refreshIfStale();
        index();
        openAt(initialMenu);
        Qt.callLater(focusSearch);
        opened();
    }

    Connections {
        target: panel.inventory
        function onLoaded() {
            panel.index();
            panel.rebuild();
        }
    }

    // The host keeps this item alive between opens, so every open starts
    // over: fresh rows if the inventory is stale, the requested group, and
    // the cursor in the search field. The host usually loads the content
    // before it shows the popout, so the reset waits for the visibility
    // change; when the content arrives with the popout already showing,
    // the hand-over of the popout reference is the open.
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
        spacing: Theme.spacingS

        Item {
            id: header
            width: parent.width
            height: 36

            Row {
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS

                Rectangle {
                    id: backButton
                    width: 30
                    height: 30
                    radius: 15
                    visible: panel.activeId !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    color: backArea.containsMouse ? Theme.surfaceContainerHighest : "transparent"

                    DankIcon {
                        anchors.centerIn: parent
                        name: "arrow_back"
                        size: Theme.iconSize - 2
                        color: Theme.surfaceText
                    }

                    MouseArea {
                        id: backArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: panel.back()
                    }
                }

                DankIcon {
                    visible: panel.activeId === ""
                    anchors.verticalCenter: parent.verticalCenter
                    name: "terminal"
                    size: Theme.iconSize
                    color: Theme.primary
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 0

                    StyledText {
                        visible: panel.activeTrail !== ""
                        text: panel.activeTrail
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        text: panel.activeLabel
                        font.pixelSize: panel.activeTrail !== "" ? Theme.fontSizeMedium : Theme.fontSizeLarge
                        font.weight: Font.Bold
                        color: Theme.surfaceText
                    }
                }
            }

            Rectangle {
                width: 30
                height: 30
                radius: 15
                anchors.right: parent.right
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

        DankTextField {
            id: field
            width: parent.width
            height: 40
            leftIconName: "search"
            placeholderText: panel.activeId ? "Search " + panel.activeLabel : "Search the menu"
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
            width: parent.width
            height: panel.fillMode
                ? Math.max(panel.rowHeight, panel.height - panel.padding * 2 - header.height - field.height - footer.height - layout.spacing * 3)
                : Math.max(1, Math.min(panel.displayRows.length, panel.maxVisibleRows)) * panel.rowHeight

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

                    DankIcon {
                        id: rowIcon
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        name: rowItem.modelData.icon
                        size: Theme.iconSize
                        color: rowItem.selected ? Theme.primary : Theme.surfaceVariantText
                    }

                    Column {
                        anchors.left: rowIcon.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.right: chevron.visible ? chevron.left : parent.right
                        anchors.rightMargin: Theme.spacingM
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 1

                        StyledText {
                            width: parent.width
                            text: rowItem.modelData.label
                            font.pixelSize: Theme.fontSizeMedium
                            font.weight: rowItem.selected ? Font.DemiBold : Font.Normal
                            color: Theme.surfaceText
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                        }

                        StyledText {
                            width: parent.width
                            visible: text !== ""
                            text: rowItem.modelData.subtitle
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                            wrapMode: Text.NoWrap
                            elide: Text.ElideRight
                        }
                    }

                    DankIcon {
                        id: chevron
                        visible: rowItem.modelData.kind === "group"
                        anchors.right: parent.right
                        anchors.rightMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        name: "chevron_right"
                        size: Theme.iconSize - 2
                        color: rowItem.selected ? Theme.primary : Theme.surfaceVariantText
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
                visible: panel.displayRows.length === 0
                text: panel.filter ? "Nothing matches “" + panel.filter + "”" : "Nothing here"
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceVariantText
            }
        }

        StyledText {
            id: footer
            width: parent.width
            leftPadding: Theme.spacingXS
            text: panel.activeId ? "↑↓ move · ↵ open · ⌫ back · esc close" : "↑↓ move · ↵ open · esc close"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }
    }

    Component.onCompleted: {
        // A host that was already showing has reset this item through the
        // popout hand-over; do not send it back to the requested group.
        if (started)
            return;
        index();
        openAt(initialMenu);
    }
}
