import QtQuick
import qs.Common
import qs.Widgets

// A searchable picker hung under a button, as github.com's menus are: a
// card with an optional title, a filter field, and a list moved with the
// arrow keys (Tab too) and chosen with Enter or a click; Escape or a click
// outside the card dismisses it. It lies over its parent, which it covers
// with a layer that closes it. What it lists and what a row looks like
// belong to the menu built on it (GitHubScopeMenu, GitHubAssigneeMenu):
// entries, rowDelegate (given modelData, index), and selectable(entry) for
// rows that are not choices (a section header). A menu that asks GitHub
// gives `search`, a function (words, done) that calls done(answer): it
// runs a moment after typing stops (and on show), only the latest answer
// lands in `found` (for `foundFor`), and `searching` says one is on its way.
Item {
    id: picker

    // The button the card hangs under, right edges aligned.
    property Item anchorItem: null
    property bool open: false
    property string title: ""
    // Something is on its way (a search, a change): a spinner says so.
    property bool busy: false
    property string placeholder: ""
    property string emptyText: ""
    property int maxWidth: 340
    property int maxHeight: 440
    property var entries: []
    property Component rowDelegate: null
    property var selectable: entry => true
    property int selectedIndex: 0

    property var search: null
    property int searchDelay: 350
    property var found: null
    property string foundFor: ""
    property bool searching: false
    property int searchSeq: 0

    readonly property string text: field.text
    property alias listView: list

    signal chosen(var entry)
    signal dismissed()

    property point anchorPos: Qt.point(0, 0)

    visible: open

    function show(anchor) {
        if (anchor)
            anchorItem = anchor;
        if (anchorItem)
            anchorPos = anchorItem.mapToItem(picker, 0, 0);
        field.text = "";
        found = null;
        foundFor = "";
        open = true;
        selectedIndex = firstSelectable(0, 1);
        Qt.callLater(() => field.forceActiveFocus());
        if (search)
            runSearch();
    }

    // Closing drops the search on its way.
    function close() {
        open = false;
        searchTimer.stop();
        searchSeq++;
        searching = false;
    }

    function runSearch() {
        const words = text.trim();
        const seq = ++searchSeq;
        searching = true;
        search(words, answer => {
            if (seq !== picker.searchSeq)
                return;
            picker.searching = false;
            picker.found = answer;
            picker.foundFor = words;
        });
    }

    Timer {
        id: searchTimer
        interval: picker.searchDelay
        onTriggered: picker.runSearch()
    }

    function select(index) {
        selectedIndex = index;
        if (index >= 0)
            list.positionViewAtIndex(index, ListView.Contain);
    }

    function firstSelectable(from, step) {
        for (let i = from; i >= 0 && i < entries.length; i += step)
            if (selectable(entries[i]))
                return i;
        return -1;
    }

    function move(step) {
        const next = firstSelectable(selectedIndex + step, step);
        if (next >= 0)
            select(next);
    }

    function choose(entry) {
        if (entry && selectable(entry))
            chosen(entry);
    }

    onEntriesChanged: {
        if (selectedIndex < 0 || selectedIndex >= entries.length || !selectable(entries[selectedIndex]))
            selectedIndex = firstSelectable(0, 1);
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: picker.dismissed()
        onWheel: wheel => wheel.accepted = true
    }

    Item {
        id: keys
        width: 1
        height: 1
        Keys.onPressed: event => {
            switch (event.key) {
            case Qt.Key_Down:
            case Qt.Key_Tab:
                picker.move(1);
                break;
            case Qt.Key_Up:
            case Qt.Key_Backtab:
                picker.move(-1);
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                picker.choose(picker.entries[picker.selectedIndex]);
                break;
            case Qt.Key_Escape:
                picker.dismissed();
                break;
            default:
                return;
            }
            event.accepted = true;
        }
    }

    Rectangle {
        id: card

        width: Math.min(picker.maxWidth, picker.width)
        x: Math.max(0, Math.min(picker.width - width, picker.anchorPos.x + (picker.anchorItem ? picker.anchorItem.width : 0) - width))
        y: picker.anchorPos.y + (picker.anchorItem ? picker.anchorItem.height : 0) + Theme.spacingXS
        height: Math.min(picker.height - y, picker.maxHeight, field.y + field.height + Theme.spacingS * 2 + Math.max(list.contentHeight, 40))
        color: Theme.surfaceContainer
        radius: Theme.cornerRadius
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.8)
        border.width: 1

        // Swallows clicks between the entries, which would otherwise reach
        // the closing layer behind the card.
        MouseArea {
            anchors.fill: parent
            onWheel: wheel => wheel.accepted = false
        }

        Row {
            id: titleRow
            visible: picker.title !== ""
            x: Theme.spacingM
            y: Theme.spacingS
            height: visible ? 22 : 0
            spacing: Theme.spacingS

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: picker.title
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
                color: Theme.surfaceText
            }

            DankSpinner {
                visible: picker.busy
                anchors.verticalCenter: parent.verticalCenter
                size: 12
            }
        }

        DankTextField {
            id: field
            x: Theme.spacingS
            y: titleRow.visible ? titleRow.y + titleRow.height + Theme.spacingS : Theme.spacingS
            width: parent.width - Theme.spacingS * 2
            height: 36
            leftIconName: "search"
            placeholderText: picker.placeholder
            showClearButton: true
            hidePlaceholderOnFocus: false
            ignoreUpDownKeys: true
            ignoreTabKeys: true
            keyForwardTargets: [keys]
            onTextEdited: {
                list.positionViewAtBeginning();
                if (picker.search)
                    searchTimer.restart();
                picker.selectedIndex = picker.firstSelectable(0, 1);
            }
        }

        DankListView {
            id: list
            x: Theme.spacingS
            y: field.y + field.height + Theme.spacingS
            width: parent.width - Theme.spacingS * 2
            height: parent.height - y - Theme.spacingS
            clip: true
            model: picker.entries
            spacing: 1
            delegate: picker.rowDelegate

            StyledText {
                visible: list.count === 0
                anchors.centerIn: parent
                width: parent.width - Theme.spacingM * 2
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: picker.emptyText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }
    }
}
