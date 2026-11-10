import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "GitHubLogic.js" as Logic

// The suggestions under the panel's search field, as github.com's search
// bar offers them: the qualifiers of the tab's search while a word is
// typed (or every one, from the field's filter button), then the values of
// the qualifier being written: states and sorts from here, what the panel
// has loaded (localValues), and what GitHub answers for the repository on
// screen or searched (repo:owner/name), or for a name typed. The field
// keeps the keys: the panel hands them to handleKey first, where Down and
// Up pick a suggestion, Tab takes the picked one (or the first), Enter a
// picked one, and Escape puts the menu away until the word changes. The
// card lies over the top of the list.
Item {
    id: helper

    required property var github
    // The DTextField the suggestions are for.
    property Item input: null
    property string tab: "inbox"
    property string scope: ""
    // Whether the field is on screen and taking keys.
    property bool active: false
    // The loaded values of a source (see Logic.searchQualifiers): a
    // function (source) returning [{ value, detail, color, login }].
    property var localValues: source => []

    readonly property string text: input ? input.text : ""
    readonly property int cursor: input ? input.cursorPosition : 0
    readonly property var context: Logic.searchContext(tab, scope, text, cursor)
    readonly property string source: context.mode === "value" ? context.def.source : ""
    // The repository whose labels and people a value comes from.
    readonly property string repo: Logic.isRepo(scope) ? scope : Logic.searchedRepo(text)
    // The word under the cursor, for what was put away or picked.
    readonly property string wordKey: tab + "|" + context.start + "|" + context.text

    // Where the filter button opened every qualifier (a word not begun
    // yet); -1 for none.
    property int listAllAt: -1
    property string dismissedFor: ""
    property int highlighted: -1

    // What GitHub answered: key -> { at, values }, kept freshMs. A lookup
    // on its way is in pending; gen tells an answer for an earlier account
    // (or none, gh dropping it) from one for this account.
    property var remote: ({})
    property var pending: ({})
    property int pendingCount: 0
    property int gen: 0
    readonly property int freshMs: 300000

    readonly property var lookups: computeLookups()
    readonly property var entries: computeEntries()
    readonly property bool open: active && entries.length > 0 && dismissedFor !== wordKey && (context.text !== "" || listAllAt === context.start)

    onWordKeyChanged: {
        highlighted = -1;
        if (listAllAt !== context.start)
            listAllAt = -1;
    }
    onEntriesChanged: {
        if (highlighted >= entries.length)
            highlighted = -1;
    }
    onLookupsChanged: lookupTimer.restart()

    // What GitHub is asked for the word under the cursor: the repository's
    // labels, milestones, and types once (and its labels by what is typed
    // when it has more than that answer holds), its branches and people by
    // what is typed, and GitHub's users from two letters on.
    function computeLookups() {
        const c = context;
        if (!active || c.mode !== "value")
            return [];
        const typed = c.value.replace(/^@/, "");
        const out = [];
        const ask = (what, where, search) => out.push({
                "key": what + "@" + where + "@" + search,
                "what": what,
                "repo": where,
                "search": search
            });
        if (repo && (source === "label" || source === "milestone" || source === "type")) {
            ask("repository", repo, "");
            const kept = remote["repository@" + repo + "@"];
            if (source === "label" && typed !== "" && kept && kept.values.moreLabels)
                ask("labels", repo, typed);
        }
        if (repo && source === "branch" && tab === "prs")
            ask("branches", repo, typed);
        if (source === "user") {
            if (repo)
                ask("people", repo, typed);
            if (typed.length >= 2)
                ask("users", "", typed);
        }
        return out;
    }

    function fresh(key) {
        const kept = remote[key];
        return !!kept && Date.now() - kept.at < freshMs;
    }

    function lookUp() {
        for (const lookup of lookups) {
            const key = lookup.key;
            if (fresh(key) || pending[key])
                continue;
            pending[key] = true;
            pendingCount++;
            const asked = gen;
            github.loadSuggestions(lookup.what, lookup.repo, lookup.search, values => {
                if (asked !== helper.gen)
                    return;
                delete helper.pending[key];
                helper.pendingCount--;
                // A failed lookup leaves the loaded values to stand alone,
                // and is asked again with the next word.
                if (values)
                    helper.keep(key, values);
            }, helper);
        }
    }

    // An answer kept, and the stale ones let go.
    function keep(key, values) {
        const now = Date.now();
        const next = {};
        for (const other in remote)
            if (now - remote[other].at < freshMs)
                next[other] = remote[other];
        next[key] = {
            "at": now,
            "values": values
        };
        remote = next;
    }

    Timer {
        id: lookupTimer
        interval: 250
        onTriggered: helper.lookUp()
    }

    // Another account's answers are not this one's.
    Connections {
        target: helper.github
        function onAccountSwitched() {
            helper.gen++;
            helper.remote = {};
            helper.pending = {};
            helper.pendingCount = 0;
        }
    }

    function valuesFor(source) {
        let values = [];
        // GitHub reads @me as the viewer; the inbox's own filter does not.
        if (source === "user" && (tab === "issues" || tab === "prs"))
            values.push({
                "value": "@me",
                "detail": github.login ? "You (" + github.login + ")" : "You",
                "login": github.login || ""
            });
        values = values.concat(localValues(source) || []);
        for (const lookup of lookups) {
            const kept = remote[lookup.key];
            if (kept && kept.values[source])
                values = values.concat(kept.values[source]);
        }
        // Without a repository, the issue types GitHub starts every
        // organization with.
        if (source === "type" && !repo)
            values = values.concat(["Bug", "Feature", "Task"].map(name => ({
                        "value": name
                    })));
        return values;
    }

    function computeEntries() {
        if (!active)
            return [];
        const c = context;
        const values = c.mode === "value" && c.def.source ? valuesFor(c.def.source) : [];
        return Logic.searchSuggestions(tab, scope, c, values, Date.now(), listAllAt === c.start);
    }

    function choosable(index) {
        return index >= 0 && index < entries.length && !entries[index].hint;
    }

    function step(delta) {
        let next = highlighted;
        do {
            next += delta;
        } while (next >= 0 && next < entries.length && !choosable(next));
        if (next < 0)
            highlighted = -1;
        else if (next < entries.length)
            highlighted = next;
        if (highlighted >= 0)
            list.positionViewAtIndex(highlighted, ListView.Contain);
    }

    function accept(index) {
        if (!choosable(index) || !input)
            return;
        const next = Logic.applySuggestion(text, context, entries[index]);
        listAllAt = -1;
        input.text = next.text;
        input.cursorPosition = next.cursor;
        input.forceActiveFocus();
    }

    // The filter button: every qualifier, for a word after what is typed.
    function listAll() {
        if (!input)
            return;
        let s = input.text;
        if (s !== "" && !/\s$/.test(s))
            s += " ";
        input.text = s;
        input.cursorPosition = s.length;
        dismissedFor = "";
        listAllAt = s.length;
        input.forceActiveFocus();
    }

    function dismiss() {
        dismissedFor = wordKey;
        listAllAt = -1;
    }

    // Whether a key went to the menu.
    function handleKey(event) {
        if (!open)
            return false;
        const control = event.modifiers & Qt.ControlModifier;
        const shift = event.modifiers & Qt.ShiftModifier;
        switch (event.key) {
        case Qt.Key_Down:
            step(1);
            return true;
        case Qt.Key_Up:
            step(-1);
            return true;
        case Qt.Key_N:
        case Qt.Key_J:
            if (!control)
                return false;
            step(1);
            return true;
        case Qt.Key_P:
        case Qt.Key_K:
            if (!control)
                return false;
            step(-1);
            return true;
        case Qt.Key_Tab:
            if (shift)
                return false;
            if (choosable(highlighted)) {
                accept(highlighted);
                return true;
            }
            for (let i = 0; i < entries.length; i++)
                if (choosable(i)) {
                    accept(i);
                    return true;
                }
            return false;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (control || !choosable(highlighted))
                return false;
            accept(highlighted);
            return true;
        case Qt.Key_Escape:
            dismiss();
            return true;
        }
        return false;
    }

    visible: open
    height: open ? card.height : 0

    Rectangle {
        id: card

        width: parent.width
        height: Math.min(helper.maxCardHeight, list.y + list.contentHeight + footer.height + Theme.spacingS * 2)
        color: Theme.surfaceContainer
        radius: Theme.cornerRadius
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.8)
        border.width: 1

        // The card keeps the pointer from the rows under it.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
            onWheel: wheel => wheel.accepted = true
        }

        Row {
            id: titleRow
            x: Theme.spacingM
            y: Theme.spacingS
            height: 20
            spacing: Theme.spacingS

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    const c = helper.context;
                    if (c.mode === "value")
                        return (c.exclude ? "Exclude " : "") + c.def.label;
                    return c.exclude ? "Exclude" : "Filters";
                }
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
                color: Theme.surfaceVariantText
            }

            DSpinner {
                visible: helper.pendingCount > 0
                anchors.verticalCenter: parent.verticalCenter
                size: 12
            }
        }

        DListView {
            id: list
            x: Theme.spacingXS
            y: titleRow.y + titleRow.height + Theme.spacingXS
            width: parent.width - Theme.spacingXS * 2
            height: parent.height - y - footer.height - Theme.spacingS
            clip: true
            model: helper.entries
            spacing: 1

            delegate: Rectangle {
                id: entry

                required property var modelData
                required property int index
                readonly property bool picked: index === helper.highlighted

                width: list.width
                height: 30
                radius: Theme.cornerRadius
                color: picked ? Theme.withAlpha(Theme.primary, 0.16) : "transparent"

                Item {
                    id: lead
                    x: Theme.spacingS
                    width: 20
                    height: parent.height

                    Rectangle {
                        visible: entry.modelData.color !== undefined && entry.modelData.color !== ""
                        anchors.centerIn: parent
                        width: 12
                        height: 12
                        radius: 6
                        color: visible ? "#" + entry.modelData.color : "transparent"
                    }

                    GitHubAvatar {
                        visible: !!entry.modelData.login && !entry.modelData.color
                        anchors.centerIn: parent
                        login: entry.modelData.login || ""
                        size: 18
                    }

                    DIcon {
                        visible: !entry.modelData.color && !entry.modelData.login
                        anchors.centerIn: parent
                        name: entry.modelData.icon || "search"
                        size: Theme.iconSizeSmall
                        color: entry.picked ? Theme.primary : Theme.surfaceVariantText
                    }
                }

                StyledText {
                    id: label
                    anchors.left: lead.right
                    anchors.leftMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, parent.width - lead.width - Theme.spacingS * 4 - (detail.text !== "" ? Math.min(detail.implicitWidth, parent.width * 0.45) : 0))
                    text: entry.modelData.label
                    elide: Text.ElideRight
                    font.pixelSize: Theme.fontSizeSmall + 1
                    font.italic: !!entry.modelData.hint
                    font.weight: entry.modelData.hint ? Font.Normal : Font.Medium
                    color: entry.modelData.hint ? Theme.surfaceVariantText : Theme.surfaceText
                }

                StyledText {
                    id: detail
                    anchors.left: label.right
                    anchors.leftMargin: Theme.spacingS
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    text: entry.modelData.detail || ""
                    elide: Text.ElideRight
                    horizontalAlignment: Text.AlignRight
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: !entry.modelData.hint
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onEntered: helper.highlighted = entry.index
                    onClicked: helper.accept(entry.index)
                }
            }
        }

        StyledText {
            id: footer
            x: Theme.spacingM
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Theme.spacingS
            width: parent.width - Theme.spacingM * 2
            height: implicitHeight
            text: "Tab completes · ↑↓ pick · Enter takes the pick · Esc hides"
            elide: Text.ElideRight
            font.pixelSize: Theme.fontSizeSmall - 1
            color: Theme.surfaceVariantText
        }
    }

    // The card may cover most of the list, not all of it.
    property real maxCardHeight: 320
}
