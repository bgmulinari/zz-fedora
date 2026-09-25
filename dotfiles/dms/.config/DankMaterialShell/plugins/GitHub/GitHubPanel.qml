import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import "GitHubLogic.js" as Logic

// The popout: four tabs in GitHub's order (notifications, issues, pull
// requests, Actions runs), each with the filters of GitHub's own pages, a
// search field that narrows the list, and a detail page (GitHubDetail) for
// the row that is opened. The scope button in the header switches every tab
// from what involves the viewer to everything in one repository
// (GitHubScopeMenu); the inbox then holds that repository's notifications.
// Arrow keys move, Enter opens the detail, Ctrl+Enter opens the row on
// GitHub, Tab switches tabs, Left and Right switch filters, Escape goes
// back, then closes. In the inbox, as on github.com, rows check for a bulk
// change; Delete marks the checked threads (or the row) done, Ctrl+I read,
// Ctrl+M unsubscribes, and Space (Ctrl+Space while searching) checks the
// row. The same panel fills the popped-out window (windowed), where it
// never closes itself: the window stays until it is closed.
Item {
    id: panel

    // GitHubData: the host hands it over, and the popout waits for it.
    required property var github
    // The tab to show on the next open ("inbox", "issues", "prs",
    // "actions"), or "" to keep the last one.
    property string initialTab: ""
    // Assigned by the popout host once this item is loaded.
    property var parentPopout: null
    // Set when the panel fills its own window instead of the popout.
    property bool windowed: false
    property var hostWindow: null

    signal opened()
    // The window's close button; the popout closes itself.
    signal closeRequested()
    // Carry what is on screen (see snapshot) into a window.
    signal popOutRequested(var state)
    // The popout's size handles: the popout width and this panel's height,
    // while a drag makes them and once it is done.
    signal resizing(real width, real height)
    signal resized(real width, real height)
    signal resizeReset()
    // A repository whose lists came, for the picker's recent ones.
    signal repoOpened(string repo)
    // The scope changed on screen (the popout keeps it for its next open).
    signal scopeChosen(string scope)

    // "" for what involves the viewer, or "owner/name": everything in that
    // repository, whoever it involves.
    property string scope: ""
    property var recentRepos: []
    // The popout starts every open (reset) at the scope it had last; a
    // window keeps the one it opened with.
    property string startScope: ""

    // A window's title: the page it shows, so windows tell apart.
    readonly property string windowTitle: {
        if (!detailItem)
            return (scope || "GitHub") + " · " + (tabs.find(t => t.id === tab) || tabs[0]).label;
        const name = detailItem.title || detailItem.displayTitle || "";
        return detail.headerTitle + (name ? " " + name : "") + " · " + detailItem.repo;
    }
    readonly property bool showing: windowed ? (!!hostWindow && hostWindow.visible) : (!!parentPopout && parentPopout.shouldBeVisible)
    // The list, rather than a page over it.
    readonly property bool listShowing: showing && !detailItem
    // What the scope on screen has: when its lists came, whether they are
    // coming, and its runs.
    readonly property var scopeState: github.scopeOf(scope)
    readonly property var scopeRuns: scopeState.runs
    // The header's refresh and open buttons act on whatever is on screen:
    // the lists, or the detail page when one is open.
    readonly property bool busy: detailItem ? detail.loading : (scopeState.loading || scopeState.runsLoading || (tab === "inbox" && scopeState.threadsLoading))

    property string tab: "inbox"
    property var filterIndexes: defaultFilters()
    readonly property string query: field.text
    property int selectedIndex: 0
    property var detailItem: null
    // Pages opened from links inside a page: Back returns through them to
    // the page the list opened, then to the list.
    property var detailStack: []

    readonly property int rowHeight: 58
    readonly property int visibleRows: Math.max(1, Math.floor(listArea.height / rowHeight))

    readonly property var tabs: Logic.TABS
    readonly property var currentFilters: Logic.filtersFor(scope, tab)
    readonly property int filterIndex: Math.min(filterIndexes[tab] || 0, currentFilters.length - 1)
    readonly property string filterKey: currentFilters[filterIndex].key

    // The rows follow GitHub only while they are on screen; hidden (or
    // under a page), the panel keeps the last ones instead of rebuilding
    // them on every poll.
    readonly property var liveRows: listShowing ? computeRows() : null
    property var rows: []
    onLiveRowsChanged: {
        if (liveRows)
            rows = liveRows;
    }
    readonly property var selectedRow: selectedIndex >= 0 && selectedIndex < rows.length ? rows[selectedIndex] : null

    // One clock for the durations of runs in progress.
    property double now: Date.now()

    Timer {
        interval: 1000
        repeat: true
        running: panel.listShowing && panel.tab === "actions" && panel.scopeRuns.some(run => Logic.isActiveRun(run))
        onTriggered: panel.now = Date.now()
    }

    implicitHeight: 640

    function defaultFilters() {
        return {
            "inbox": 0,
            "prs": 0,
            "issues": 0,
            "actions": 0
        };
    }

    // The panel says while it is on screen, so the full lists and runs in
    // progress are fetched only while someone looks.
    onShowingChanged: github.setWatching(panel, showing)
    Component.onCompleted: github.setWatching(panel, showing)
    Component.onDestruction: github.setWatching(panel, false)

    // ------------------------------------------------------------- the rows

    function filterItems(key) {
        if (tab === "inbox")
            return Logic.filterThreads(github.inboxThreads(scope), key);
        if (tab === "actions")
            return Logic.filterRuns(scopeRuns, key);
        return github.visibleItems(key);
    }

    // The loaded rows the search words match, at once as they are typed;
    // on the pull request and issue lists, GitHub's answer to the search
    // follows and leads, with the loaded matches it missed (a number, a
    // repository name) after it.
    function computeRows() {
        if (tab === "inbox")
            return inboxRows();
        // A repository's search covers every state, and so do the loaded
        // rows it matches.
        let items = statesIgnored ? [].concat(...currentFilters.map(filter => filterItems(filter.key))) : filterItems(filterKey);
        const words = Logic.searchWords(query);
        if (words.length === 0)
            return items;
        items = items.filter(item => Logic.rowMatches(item, words));
        if (!searchFresh)
            return items;
        const found = statesIgnored ? searchResult.items : searchResult.items.filter(item => !github.isHidden(item, filterKey));
        const seen = {};
        for (const item of found)
            seen[item.url] = true;
        return found.concat(items.filter(item => !seen[item.url]));
    }

    // The inbox's search is github.com's: qualifiers (Logic.inboxQuery) and
    // the words of the rows.
    readonly property var inboxQuery: Logic.inboxQuery(tab === "inbox" ? query : "")

    // github.com's All / Unread toggle over the inbox.
    property bool unreadOnly: false

    function setUnreadOnly(on) {
        unreadOnly = on;
        checked = {};
        selectedIndex = 0;
        list.positionViewAtBeginning();
    }

    function inboxRows() {
        const q = inboxQuery;
        if (q.unsupported !== "")
            return [];
        let items = filterItems(filterKey);
        if (unreadOnly)
            items = items.filter(thread => github.isUnread(thread));
        if (q.words.length === 0 && Object.keys(q.qualifiers).length === 0)
            return items;
        return items.filter(thread => {
            const subject = github.subjectOf(thread);
            return Logic.threadMatches(thread, q, github.isUnread(thread), subject ? subject.author : "");
        });
    }

    // ------------------------------------------------------------- search
    //
    // Pull requests and issues search GitHub (the list's own search with
    // the words added, in every state), a moment after typing stops. A
    // repository's filters are its states, so its search leaves them aside
    // and covers the whole tab; the viewer's filters say how the viewer is
    // involved, so the search keeps to the one chosen. The notifications
    // API has no text search, so searching the inbox loads its remaining
    // pages (bounded) and filters those; Actions runs filter what is loaded.
    readonly property bool searchActive: (tab === "prs" || tab === "issues") && query.trim() !== ""
    property var searchResult: null
    property bool searching: false
    property int searchSeq: 0
    readonly property bool statesIgnored: searchActive && scope !== ""
    // The list the search runs on: any of a repository's lists stands for
    // its whole kind.
    readonly property string searchKey: statesIgnored ? currentFilters[0].key : filterKey
    // The answer on hand is for the words and list on screen.
    readonly property bool searchFresh: searchActive && !!searchResult && searchResult.key === searchKey && searchResult.terms === query.trim()

    function runSearch() {
        const seq = ++searchSeq;
        if (!searchActive) {
            searchResult = null;
            searching = false;
            if (tab === "inbox" && query.trim() !== "")
                github.loadAllThreads(scope);
            return;
        }
        const key = searchKey;
        const words = query.trim();
        searching = true;
        github.searchPage(key, words, "", result => {
            if (seq !== searchSeq)
                return;
            searching = false;
            searchResult = Object.assign({
                "key": key,
                "terms": words
            }, result);
        }, panel);
    }

    function loadMoreSearch() {
        const current = searchResult;
        if (!searchFresh || !current.more || searching)
            return;
        const seq = searchSeq;
        searching = true;
        github.searchPage(current.key, current.terms, current.cursor, result => {
            if (seq !== searchSeq)
                return;
            searching = false;
            searchResult = Object.assign({}, result, {
                "key": current.key,
                "terms": current.terms,
                "items": Logic.appendNew(current.items, result.items, "url"),
                "error": result.error
            });
        }, panel);
    }

    Timer {
        id: searchTimer
        interval: 350
        onTriggered: panel.runSearch()
    }

    // Another account's answers are not this one's: a search on its way is
    // dropped and the one on screen asked again.
    Connections {
        target: panel.github
        function onAccountSwitched() {
            panel.searchSeq++;
            panel.searching = false;
            panel.searchResult = null;
            if (panel.query.trim() !== "")
                searchTimer.restart();
        }
    }

    onQueryChanged: searchTimer.restart()
    onSearchKeyChanged: {
        if (query.trim() !== "")
            searchTimer.restart();
    }

    // The chips follow GitHub only while they are on screen, like the rows.
    readonly property var liveChips: listShowing ? chipModel() : null
    property var chipEntries: []
    onLiveChipsChanged: {
        if (liveChips)
            chipEntries = liveChips;
    }

    // The inbox's chips count what is unread, as github.com's inbox does.
    function chipModel() {
        const unread = tab === "inbox" ? github.inboxThreads(scope).filter(thread => github.isUnread(thread)) : [];
        return currentFilters.map(filter => ({
                    "label": filter.label,
                    "value": filter.key,
                    "count": tab === "inbox" ? Logic.filterThreads(unread, filter.key).length : (tab === "actions" ? filterItems(filter.key).length : github.total(filter.key))
                }));
    }

    // ---------------------------------------------------------------- scope

    function setScope(repo) {
        if (applyScope(repo))
            scopeChosen(scope);
        loadScope();
        focusInput();
    }

    // Whether the scope changed.
    function applyScope(repo) {
        const next = Logic.isRepo(repo) ? String(repo) : "";
        if (next === scope)
            return false;
        scope = next;
        filterIndexes = Object.assign({}, filterIndexes, {
            "prs": 0,
            "issues": 0
        });
        resetList();
        return true;
    }

    // How long what came from GitHub counts as fresh: a list shown again
    // within it is not asked for again, nor a page coming back on screen.
    readonly property int freshMs: 20000

    // Fetches the repository on screen unless what is kept of it is fresh.
    function loadScope() {
        if (scope && Date.now() - scopeState.at > freshMs)
            github.refreshRepo(scope);
        loadInbox();
    }

    // The inbox on screen, unless what is kept of it is fresh.
    function loadInbox() {
        if (tab === "inbox" && Date.now() - scopeState.threadsAt > freshMs)
            github.refreshThreads(scope);
    }

    // While the list shows, a repository's lists follow GitHub every two
    // minutes (its runs along); the Actions tab looks at every repository
    // for new runs every minute; and runs in progress, which the Actions
    // tab counts, move every 15 seconds. Two panels on one scope share the
    // answers; a page over the list polls what it shows itself.
    function poll() {
        const s = scopeState;
        if (tab === "inbox" && s.threadsAt > 0 && Date.now() - s.threadsAt > 120000)
            github.refreshThreads(scope);
        if (scope && Date.now() - s.at > 120000)
            github.refreshRepo(scope);
        else if (tab === "actions" && Date.now() - s.runsFullAt > 60000)
            github.refreshRuns(scope);
        else if (Date.now() - s.runsAt > 10000 && Logic.filterRuns(scopeRuns, "active").length > 0)
            github.refreshRuns(scope, {
                "onlyActive": true
            });
    }

    Timer {
        interval: 15000
        repeat: true
        running: panel.listShowing
        onTriggered: panel.poll()
    }

    // Back from a page, what went stale meanwhile follows at once.
    onListShowingChanged: {
        if (listShowing && detailStack.length === 0)
            poll();
    }

    // A repository whose lists came is one the viewer opened lately.
    onScopeStateChanged: {
        if (scope && scopeState && scopeState.at > 0 && !scopeState.error && !scopeState.loading)
            repoOpened(scope);
    }

    // --------------------------------------------------------------- moving

    // Back to the top of a list with nothing open and nothing searched.
    function resetList() {
        detailStack = [];
        detailItem = null;
        clearQuery();
        checked = {};
        selectedIndex = 0;
        list.positionViewAtBeginning();
    }

    function showTab(id) {
        if (tabs.every(t => t.id !== id))
            return;
        tab = id;
        resetList();
        if (id === "actions" && Date.now() - scopeState.runsFullAt > 30000)
            github.refreshRuns(scope);
        if (id === "inbox" && Date.now() - github.notificationsAt > 30000)
            github.refreshNotifications();
        loadInbox();
        focusInput();
    }

    // The viewer's own inbox, which the bar's menu and a desktop
    // notification count and announce.
    function showInbox() {
        if (scope)
            setScope("");
        showTab("inbox");
    }

    function stepTab(delta) {
        const index = Math.max(0, tabs.findIndex(t => t.id === tab));
        showTab(tabs[(index + delta + tabs.length) % tabs.length].id);
    }

    function setFilter(index) {
        filterIndexes = Logic.withKey(filterIndexes, tab, (index + currentFilters.length) % currentFilters.length);
        checked = {};
        selectedIndex = 0;
        list.positionViewAtBeginning();
    }

    function move(delta) {
        if (rows.length === 0)
            return;
        selectedIndex = (selectedIndex + delta + rows.length) % rows.length;
        list.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    function moveTo(index) {
        if (rows.length === 0)
            return;
        selectedIndex = Math.max(0, Math.min(rows.length - 1, index));
        list.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    function clearQuery() {
        field.text = "";
    }

    // A page: from the list (`push` false, the Back history starts over) or
    // from a link on a page (`push`, Back returns to it).
    function openDetail(item, push) {
        if (!item)
            return;
        detailStack = push && detailItem ? detailStack.concat([detailItem]) : [];
        detailItem = item;
        github.markReadFor(item.url);
        focusInput();
    }

    // A row's click or Enter: the page, or for a notification the page of
    // its subject when that is a pull request or an issue (opened at once
    // from what the thread says, and read as the page opens, so its row
    // leaves the list behind the page), and the browser for anything else.
    function activate(item) {
        if (!item)
            return;
        if (item.kind !== "notification") {
            openDetail(item, false);
            return;
        }
        const page = Logic.itemForThread(item);
        if (page) {
            openDetail(page, false);
            return;
        }
        github.markRead(item);
        Qt.openUrlExternally(item.url);
        close();
    }

    function openExternally(item) {
        if (!item)
            return;
        if (item.kind === "notification")
            github.markRead(item);
        Qt.openUrlExternally(item.url);
    }

    // ------------------------------------------------------------ checking
    //
    // Inbox rows check as on github.com, and a change applies to the
    // checked threads, or to the highlighted row when none is checked.
    // thread id -> true.
    property var checked: ({})
    readonly property var checkedRows: tab === "inbox" ? rows.filter(row => !!checked[row.id]) : []
    readonly property bool allChecked: rows.length > 0 && checkedRows.length === rows.length
    // Everything the inbox has, which "Mark as read" reads in one request
    // (GitHub's Mark all as read), those past the loaded pages too.
    readonly property bool everythingChecked: allChecked && filterKey === "all" && query.trim() === ""

    function toggleChecked(item) {
        if (item && item.kind === "notification")
            checked = Logic.withKey(checked, item.id, checked[item.id] ? undefined : true);
    }

    function checkAll(on) {
        const next = {};
        if (on)
            for (const row of rows)
                next[row.id] = true;
        checked = next;
    }

    function targets() {
        if (checkedRows.length > 0)
            return checkedRows;
        return selectedRow && selectedRow.kind === "notification" ? [selectedRow] : [];
    }

    // An inbox action (Logic.INBOX_ACTIONS) on threads.
    function act(key, threads) {
        if (key === "done")
            github.markDone(threads);
        else if (key === "read")
            github.markThreadsRead(threads);
        else if (key === "unsubscribe")
            github.unsubscribe(threads);
    }

    // The same on the checked threads or the highlighted row. Read with
    // everything checked is GitHub's "Mark all as read", which reads the
    // threads past the loaded pages too and cannot be taken back: it takes
    // a second press (a click or Ctrl+I) within a few seconds.
    function actOnTargets(key) {
        if (key === "read" && everythingChecked) {
            if (!markAllArmed) {
                markAllArmed = true;
                disarmMarkAll.restart();
                return;
            }
            markAllArmed = false;
            github.markAllRead(scope, rows);
        } else {
            act(key, targets());
        }
        checked = {};
    }

    property bool markAllArmed: false
    onEverythingCheckedChanged: markAllArmed = false

    Timer {
        id: disarmMarkAll
        interval: 4000
        onTriggered: panel.markAllArmed = false
    }

    // A label or a search link from a page: that repository's list, with
    // the search in the field, as github.com goes to its search.
    function openSearch(repo, tabId, terms) {
        setScope(repo);
        showTab(tabId);
        field.text = terms;
    }

    function closeDetail() {
        if (detailStack.length > 0) {
            detailItem = detailStack[detailStack.length - 1];
            detailStack = detailStack.slice(0, -1);
        } else {
            detailItem = null;
        }
        focusInput();
    }

    // Dismisses the popout, as after handing something to the browser; a
    // window stays open.
    function close() {
        if (!windowed && parentPopout)
            parentPopout.close();
    }

    // What a window needs to pick up where the popout was, the page's
    // draft included (kept by page, which the window's page reads back).
    function snapshot() {
        return {
            "scope": scope,
            "tab": tab,
            "filterIndexes": filterIndexes,
            "unreadOnly": unreadOnly,
            "query": query,
            "detailItem": detailItem,
            "detailStack": detailStack
        };
    }

    function restore(state) {
        if (state) {
            scope = Logic.isRepo(state.scope) ? state.scope : "";
            tab = tabs.some(t => t.id === state.tab) ? state.tab : tabs[0].id;
            filterIndexes = Object.assign(defaultFilters(), state.filterIndexes || {});
            unreadOnly = state.unreadOnly === true;
            field.text = state.query || "";
            detailStack = state.detailStack || [];
            detailItem = state.detailItem || null;
        }
        loadScope();
        focusInput();
    }

    // Everything on screen again from GitHub: the scope's lists (from
    // their first page), its runs, and the search shown.
    function refresh() {
        // The viewer's own inbox, once loaded, comes with refreshInbox.
        if (tab === "inbox" && (scope || scopeState.threadsAt === 0))
            github.refreshThreads(scope, {
                "reset": true
            });
        if (scope)
            github.refreshRepo(scope, {
                "reset": true
            });
        else
            github.refreshInbox({
                "reset": true
            });
        if (searchActive)
            runSearch();
    }

    // ------------------------------------------------------------- paging
    //
    // The inbox and the pull request and issue lists fetch a page at a
    // time; scrolling near the end of one asks for the next; a search's
    // results page the same way.
    readonly property bool pageable: {
        if (tab === "actions")
            return false;
        if (searchActive)
            return searchFresh && searchResult.more;
        // Unread, the inbox pages on only while there may be unread threads
        // past the newest 50 the background poll knows.
        if (tab === "inbox")
            return scopeState.threadsMore && query.trim() === "" && (!unreadOnly || github.moreNotifications);
        return github.listOf(filterKey).more;
    }
    readonly property bool pageLoading: {
        if (tab === "actions")
            return false;
        if (searchActive)
            return searching;
        return tab === "inbox" ? scopeState.threadsPaging : github.listOf(filterKey).loading;
    }

    function loadNextPage() {
        if (searchActive)
            loadMoreSearch();
        else if (tab === "inbox")
            github.loadMoreThreads(scope);
        else if (tab !== "actions")
            github.loadMore(filterKey);
    }

    function maybeLoadMore() {
        if (!showing || detailItem || !pageable || pageLoading)
            return;
        if (list.count === 0 || list.contentY + list.height >= list.originY + list.contentHeight - list.height / 2)
            loadNextPage();
    }

    Timer {
        id: pageTimer
        interval: 250
        onTriggered: panel.maybeLoadMore()
    }

    onFilterKeyChanged: pageTimer.restart()
    onPageableChanged: pageTimer.restart()

    function handleKey(event) {
        if (detailItem) {
            if (detail.handleKey(event))
                event.accepted = true;
            return;
        }
        const control = event.modifiers & Qt.ControlModifier;
        const shift = event.modifiers & Qt.ShiftModifier;
        switch (event.key) {
        case Qt.Key_Down:
            move(1);
            break;
        case Qt.Key_Up:
            move(-1);
            break;
        case Qt.Key_PageDown:
            moveTo(selectedIndex + visibleRows);
            break;
        case Qt.Key_PageUp:
            moveTo(selectedIndex - visibleRows);
            break;
        case Qt.Key_Tab:
            stepTab(shift ? -1 : 1);
            break;
        case Qt.Key_Backtab:
            stepTab(-1);
            break;
        case Qt.Key_Left:
            if (query)
                return;
            setFilter(filterIndex - 1);
            break;
        case Qt.Key_Right:
            if (query)
                return;
            setFilter(filterIndex + 1);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (!selectedRow)
                return;
            if (control)
                openExternally(selectedRow);
            else
                activate(selectedRow);
            break;
        case Qt.Key_Delete:
            // The field's own Delete while there is text after the cursor.
            if (tab !== "inbox" || field.cursorPosition < query.length)
                return;
            actOnTargets("done");
            break;
        case Qt.Key_I:
            if (!control || tab !== "inbox")
                return;
            actOnTargets("read");
            break;
        case Qt.Key_M:
            if (!control || tab !== "inbox")
                return;
            actOnTargets("unsubscribe");
            break;
        case Qt.Key_Space:
            if (tab !== "inbox" || !selectedRow || (query && !control))
                return;
            toggleChecked(selectedRow);
            break;
        case Qt.Key_Escape:
            if (query)
                clearQuery();
            else if (windowed)
                return;
            else
                close();
            break;
        case Qt.Key_R:
            if (!control)
                return;
            refresh();
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

    // ---------------------------------------------------------------- focus
    //
    // The list takes keys through the search field; the detail takes them
    // directly unless its comment box is being written. The popout host
    // takes focus for itself as it comes up, and a click on the window's
    // edge can too: whenever focus leaves this panel while it shows, the
    // input takes it back. Focus moving within the panel (the comment box,
    // a picker, selected text) is left alone.
    function focusInput() {
        Qt.callLater(takeFocus);
    }

    function takeFocus() {
        if (!showing || scopeMenu.open)
            return;
        if (detailItem) {
            if (!detail.editing)
                keys.forceActiveFocus();
        } else {
            field.forceActiveFocus();
        }
    }

    function contains(item) {
        for (let p = item; p; p = p.parent)
            if (p === panel)
                return true;
        return false;
    }

    readonly property Item focusedItem: Window.activeFocusItem
    onFocusedItemChanged: {
        if (showing && !contains(focusedItem))
            focusInput();
    }

    // How long a dismissed popout keeps its place: opened again from the bar
    // within it, it shows what it showed (the page, where it was scrolled,
    // the tab, the search); later, or opened for something (a tab, a
    // notification), it starts over. 0 always starts over. The widget sets
    // it from the plugin's settings.
    property int resumeSeconds: 0
    // When the popout last went away; 0 before it ever showed.
    property real hiddenAt: 0

    GitHubScrollPlace {
        id: listPlace
        target: list
    }

    function wentAway() {
        hiddenAt = Date.now();
        listPlace.keep();
        detail.place.keep();
    }

    function cameBack() {
        if (Logic.resumes(initialTab, hiddenAt, Date.now(), resumeSeconds))
            resume();
        else
            reset();
    }

    // The popout as it was left, brought up to date like a fresh open: the
    // lists, and a page gone a while from screen (which keeps its place
    // when GitHub answers the same).
    function resume() {
        scopeMenu.close();
        loadScope();
        if (detailItem && Date.now() - hiddenAt > freshMs)
            detail.reload();
        listPlace.restore();
        detail.place.restore();
        focusInput();
        opened();
    }

    // Every open of the popout: its last scope, the tab asked for or the
    // list's top, and fresh data (the lists and the inbox refresh as the
    // panel comes on screen: GitHubData.onWatchedChanged).
    function reset() {
        scopeMenu.close();
        // Asked for the inbox (the bar's menu, a desktop notification):
        // the viewer's, which those count.
        applyScope(initialTab === "inbox" ? "" : startScope);
        showTab(initialTab || tab);
        loadScope();
        focusInput();
        opened();
    }

    // The host keeps this item alive between opens, so an open starts over
    // at the list unless it comes back within resumeSeconds (cameBack);
    // that waits for the visibility change, or for the popout hand-over
    // when the content arrives already showing.
    Connections {
        target: panel.parentPopout
        function onShouldBeVisibleChanged() {
            if (panel.parentPopout.shouldBeVisible)
                panel.cameBack();
            else
                panel.wentAway();
        }
    }

    onParentPopoutChanged: {
        if (parentPopout && parentPopout.shouldBeVisible)
            reset();
    }

    onRowsChanged: {
        if (selectedIndex >= rows.length)
            selectedIndex = Math.max(0, rows.length - 1);
        // A thread that left the rows (done, or filtered out) is no longer
        // checked.
        const shown = {};
        for (const row of rows)
            shown[row.id] = true;
        if (Object.keys(checked).some(id => !shown[id]))
            checked = Object.keys(checked).filter(id => shown[id]).reduce((next, id) => Logic.withKey(next, id, true), {});
    }

    // The chips set their own index on a click; a tab or scope switch sets
    // it from the filter kept for the tab.
    onFilterIndexChanged: chips.currentIndex = filterIndex

    // The search field forwards every key here first, so navigation wins
    // over text editing and the field only sees what is left.
    Item {
        id: keys
        width: 1
        height: 1
        Keys.onPressed: event => panel.handleKey(event)
    }

    // ---------------------------------------------------------------- layout

    Column {
        id: layout
        anchors.fill: parent
        spacing: Theme.spacingS

        // A page's header holds the page's compact header: two lines, more
        // when its title wraps.
        Item {
            id: header
            width: parent.width
            height: panel.detailItem ? Math.max(48, compactHeader.implicitHeight + Theme.spacingS) : 40

            // A window has no title bar of its own: the header moves it,
            // and a double click maximizes it.
            MouseArea {
                anchors.fill: parent
                enabled: panel.windowed && !!panel.hostWindow
                onPressed: panel.hostWindow.startSystemMove()
                onDoubleClicked: panel.hostWindow.maximized = !panel.hostWindow.maximized
            }

            // One header for both pages: the account on the lists, and on a
            // detail page the way back plus what is open.
            Row {
                anchors.left: parent.left
                anchors.leftMargin: panel.detailItem ? 0 : Theme.spacingXS
                anchors.right: headerActions.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS

                DankActionButton {
                    readonly property var previous: panel.detailStack.length > 0 ? panel.detailStack[panel.detailStack.length - 1] : null
                    visible: !!panel.detailItem
                    anchors.verticalCenter: parent.verticalCenter
                    iconName: "arrow_back"
                    iconColor: Theme.surfaceText
                    tooltipText: previous ? "Back to " + (previous.kind === "run" ? "run" : "#" + previous.number) + " (Esc)" : "Back to the list (Esc)"
                    onClicked: panel.closeDetail()
                }

                GitHubMark {
                    visible: !panel.detailItem
                    anchors.verticalCenter: parent.verticalCenter
                    size: Theme.iconSize
                    color: Theme.surfaceText
                }

                // On a page, the header says what the page is, as
                // github.com's sticky header does: the number with its
                // state under it, and the title and branches beside them
                // (GitHubCompactHeader). On the lists, the account.
                Item {
                    id: headerText
                    readonly property bool condensed: !!panel.detailItem
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - x
                    height: header.height

                    Column {
                        id: headerLead
                        anchors.verticalCenter: parent.verticalCenter
                        // On a page, the number and its state center on
                        // each other, as wide as the wider of the two.
                        width: headerText.condensed ? Math.max(headerNumber.implicitWidth, stateBadge.width) : parent.width
                        spacing: headerText.condensed ? 2 : 0

                        // On a page, the number opens it on GitHub (so does
                        // Enter).
                        GitHubLinkText {
                            id: headerNumber
                            x: headerText.condensed ? Math.round((parent.width - width) / 2) : 0
                            width: headerText.condensed ? implicitWidth : parent.width
                            page: detail
                            action: panel.detailItem ? () => detail.openOnGitHub() : null
                            text: panel.detailItem ? detail.headerTitle : "GitHub"
                            font.pixelSize: Theme.fontSizeLarge
                            font.weight: Font.Bold
                            color: panel.detailItem ? Theme.primary : Theme.surfaceText
                            elide: Text.ElideRight
                        }

                        Item {
                            width: parent.width
                            height: headerText.condensed ? stateBadge.height : (subtitle.text !== "" ? subtitle.implicitHeight : 0)

                            // The account on the lists, which opens on GitHub.
                            GitHubLinkText {
                                id: subtitle
                                width: Math.min(implicitWidth, parent.width)
                                visible: !headerText.condensed && text !== ""
                                text: panel.github.login ? "@" + panel.github.login : ""
                                action: () => Qt.openUrlExternally(Logic.profileUrl(panel.github.login))
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                elide: Text.ElideMiddle
                            }

                            // Until a page says where it stands, its row
                            // may not know either.
                            GitHubStateBadge {
                                id: stateBadge
                                anchors.horizontalCenter: parent.horizontalCenter
                                page: detail
                                visible: headerText.condensed && (!!detail.detail || !(panel.detailItem && panel.detailItem.stateUnknown))
                            }
                        }
                    }

                    GitHubCompactHeader {
                        id: compactHeader
                        anchors.left: headerLead.right
                        anchors.leftMargin: Theme.spacingM
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: headerText.condensed
                        page: detail
                    }
                }
            }

            Row {
                id: headerActions
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: 2

                // What the lists cover: what involves the viewer, or one
                // repository; a click opens the picker.
                Rectangle {
                    id: scopeButton
                    visible: !panel.detailItem && !problem.visible
                    anchors.verticalCenter: parent.verticalCenter
                    width: scopeRow.implicitWidth + Theme.spacingS + Theme.spacingXS
                    height: 30
                    radius: Theme.cornerRadius
                    color: scopeArea.containsMouse || scopeMenu.open ? Theme.withAlpha(Theme.surfaceText, 0.1) : Theme.withAlpha(Theme.surfaceText, 0.05)

                    Row {
                        id: scopeRow
                        anchors.left: parent.left
                        anchors.leftMargin: Theme.spacingS
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: Theme.spacingXS

                        DankIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: panel.scope ? "book" : "person"
                            size: 16
                            color: panel.scope ? Theme.primary : Theme.surfaceVariantText
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: Math.min(implicitWidth, Math.max(80, header.width * 0.4 - 56))
                            text: panel.scope || "Involving you"
                            textFormat: Text.PlainText
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: panel.scope ? Font.DemiBold : Font.Normal
                            color: Theme.surfaceText
                            elide: Text.ElideMiddle
                        }

                        DankIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: scopeMenu.open ? "expand_less" : "expand_more"
                            size: 16
                            color: Theme.surfaceVariantText
                        }
                    }

                    MouseArea {
                        id: scopeArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (scopeMenu.open) {
                                scopeMenu.close();
                                panel.focusInput();
                            } else {
                                scopeMenu.showAt(scopeButton);
                            }
                        }
                    }
                }

                Item {
                    visible: scopeButton.visible
                    width: Theme.spacingXS
                    height: 1
                }

                // Whether the page's notifications reach the viewer, as
                // github.com's Subscribe button in its sidebar; a click
                // flips it.
                DankActionButton {
                    readonly property var subscription: panel.detailItem ? detail.subscription : null
                    visible: !!subscription
                    iconName: !subscription ? "" : (subscription.on ? "notifications_active" : (subscription.next === "SUBSCRIBED" && subscription.reason.indexOf("ignoring") >= 0 ? "notifications_off" : "notifications_none"))
                    iconColor: subscription && subscription.on ? Theme.primary : Theme.surfaceVariantText
                    tooltipText: {
                        if (!subscription)
                            return "";
                        const reason = subscription.reason !== "" ? subscription.reason + " " : "";
                        if (!panel.github.canSubscribe)
                            return reason + "Changing it needs gh's notifications scope: click to add it.";
                        return reason + (subscription.on ? "Click to unsubscribe." : "Click to subscribe.");
                    }
                    onClicked: detail.toggleSubscription()
                }

                DankActionButton {
                    visible: !!panel.detailItem
                    iconName: "content_copy"
                    iconColor: Theme.surfaceVariantText
                    tooltipText: "Copy link"
                    onClicked: detail.copyLink()
                }

                DankRefreshButton {
                    busy: panel.busy
                    iconColor: Theme.surfaceVariantText
                    tooltipText: "Refresh (Ctrl+R)"
                    onClicked: panel.detailItem ? detail.reload() : panel.refresh()
                }

                // A page opens on GitHub from its number.
                DankActionButton {
                    visible: !panel.detailItem
                    iconName: "open_in_new"
                    iconColor: Theme.surfaceVariantText
                    tooltipText: panel.scope ? "Open " + panel.scope + " on GitHub" : "Open GitHub"
                    onClicked: {
                        Qt.openUrlExternally(Logic.tabUrl(panel.scope, panel.tab));
                        panel.close();
                    }
                }

                DankActionButton {
                    visible: !panel.windowed
                    iconName: "pip_exit"
                    iconColor: Theme.surfaceVariantText
                    tooltipText: "Open in a window"
                    onClicked: panel.popOutRequested(panel.snapshot())
                }

                DankActionButton {
                    iconName: "close"
                    iconColor: Theme.surfaceVariantText
                    tooltipText: panel.windowed ? "Close the window" : ""
                    onClicked: panel.windowed ? panel.closeRequested() : panel.close()
                }
            }
        }

        // ---------- Signed out, or gh failing before the first answer ----------
        Column {
            id: problem
            readonly property bool signedOut: panel.github.authState === "signedOut"
            visible: signedOut || panel.github.authState === "error"
            width: parent.width
            topPadding: Theme.spacingXL
            spacing: Theme.spacingM

            DankIcon {
                anchors.horizontalCenter: parent.horizontalCenter
                name: problem.signedOut ? "key" : "cloud_off"
                size: 40
                color: Theme.surfaceVariantText
            }

            StyledText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                text: problem.signedOut ? "The GitHub CLI is not signed in." : "GitHub could not be reached."
                font.pixelSize: Theme.fontSizeLarge
                color: Theme.surfaceText
            }

            StyledText {
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: problem.signedOut ? "This widget signs in through gh and never stores a token itself. Sign in once in a terminal, then refresh." : panel.github.scopeOf("").error
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: Theme.spacingS

                DankButton {
                    visible: problem.signedOut
                    text: "Sign in with gh"
                    iconName: "login"
                    buttonHeight: 36
                    onClicked: {
                        panel.github.runInTerminal("GitHub sign-in", "gh auth login");
                        panel.close();
                    }
                }

                DankButton {
                    text: "Try again"
                    iconName: "refresh"
                    buttonHeight: 36
                    backgroundColor: Theme.surfaceContainerHigh
                    textColor: Theme.surfaceText
                    onClicked: panel.refresh()
                }
            }
        }

        // ---------- Tabs ----------
        // Tabs are the page's navigation and read as such: text with an
        // underline under the current one. The filter chips below them are
        // the only filled selection, so the two never compete.
        Item {
            id: tabRow
            visible: !problem.visible && !panel.detailItem
            width: parent.width
            height: 38

            readonly property real cellWidth: width / panel.tabs.length

            Rectangle {
                anchors.bottom: parent.bottom
                width: parent.width
                height: 1
                color: Theme.withAlpha(Theme.outlineVariant, 0.5)
            }

            Rectangle {
                anchors.bottom: parent.bottom
                x: Math.max(0, panel.tabs.findIndex(t => t.id === panel.tab)) * tabRow.cellWidth + Theme.spacingM
                width: tabRow.cellWidth - Theme.spacingM * 2
                height: 3
                radius: 1.5
                color: Theme.primary

                Behavior on x {
                    NumberAnimation {
                        duration: Theme.shortDuration
                        easing.type: Theme.standardEasing
                    }
                }
            }

            Row {
                anchors.fill: parent

                Repeater {
                    model: panel.tabs

                    Item {
                        id: tabCell
                        required property var modelData
                        readonly property bool selected: modelData.id === panel.tab
                        // Counted while on screen only, like the rows.
                        readonly property string count: panel.listShowing ? panel.github.countText(panel.github.tabCount(panel.scope, modelData.id), modelData.id, panel.scope) : ""

                        width: tabRow.cellWidth
                        height: tabRow.height

                        Rectangle {
                            anchors.fill: parent
                            anchors.bottomMargin: 3
                            radius: Theme.cornerRadius
                            color: tabArea.containsMouse && !tabCell.selected ? Theme.withAlpha(Theme.surfaceText, 0.06) : "transparent"
                        }

                        Row {
                            anchors.centerIn: parent
                            anchors.verticalCenterOffset: -1
                            spacing: Theme.spacingXS

                            DankIcon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: tabCell.modelData.icon
                                size: Theme.iconSizeSmall
                                color: tabCell.selected ? Theme.primary : Theme.surfaceVariantText
                            }

                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                text: tabCell.modelData.label
                                font.pixelSize: Theme.fontSizeSmall + 1
                                font.weight: tabCell.selected ? Font.DemiBold : Font.Normal
                                color: tabCell.selected ? Theme.primary : Theme.surfaceVariantText
                            }

                            Rectangle {
                                visible: tabCell.count !== ""
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.max(18, countText.implicitWidth + 8)
                                height: 18
                                radius: 9
                                color: tabCell.selected ? Theme.withAlpha(Theme.primary, 0.2) : Theme.withAlpha(Theme.surfaceText, 0.08)

                                StyledText {
                                    id: countText
                                    anchors.centerIn: parent
                                    text: tabCell.count
                                    font.pixelSize: Theme.fontSizeSmall - 1
                                    font.weight: Font.DemiBold
                                    color: tabCell.selected ? Theme.primary : Theme.surfaceVariantText
                                }
                            }
                        }

                        MouseArea {
                            id: tabArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.showTab(tabCell.modelData.id)
                        }
                    }
                }
            }
        }

        DankFilterChips {
            id: chips
            visible: tabRow.visible
            width: parent.width
            model: panel.chipEntries
            currentIndex: panel.filterIndex
            // A repository's search spans every state: its state chips step
            // back until the search is cleared.
            enabled: !panel.statesIgnored
            opacity: panel.statesIgnored ? 0.4 : 1
            showCheck: false
            chipHeight: 28
            onSelectionChanged: index => {
                panel.setFilter(index);
                panel.focusInput();
            }
        }

        DankTextField {
            id: field
            visible: tabRow.visible
            width: parent.width
            height: 38
            leftIconName: "search"
            placeholderText: {
                if (panel.tab === "actions")
                    return panel.scope ? "Filter runs by title, workflow, or branch" : "Filter runs by title, workflow, branch, or repository";
                if (panel.tab === "inbox")
                    return "Filter: is:unread, reason:mention, repo:owner/name, author:name, or words";
                return panel.scope ? "Search " + panel.scope + ": words, #number, label:bug, author:name…" : "Search GitHub: words, #number, or label:bug, repo:owner/name…";
            }
            showClearButton: true
            hidePlaceholderOnFocus: false
            ignoreUpDownKeys: true
            ignoreTabKeys: true
            keyForwardTargets: [keys]
            onTextEdited: {
                panel.selectedIndex = 0;
                list.positionViewAtBeginning();
            }
        }

        // ---------- The list ----------
        Item {
            id: listArea
            visible: tabRow.visible
            width: parent.width
            height: panel.height - header.height - tabRow.height - chips.height - field.height - footer.height - layout.spacing * 5

            // github.com's bar over the inbox: Select all, and All / Unread,
            // which once rows are checked give way to what to do with them.
            Item {
                id: bulkBar
                visible: panel.tab === "inbox"
                width: parent.width
                height: visible ? 36 : 0

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.withAlpha(Theme.outlineVariant, 0.5)
                }

                Row {
                    visible: panel.rows.length > 0
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS

                    DankActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        buttonSize: 28
                        iconName: panel.allChecked ? "check_box" : (panel.checkedRows.length > 0 ? "indeterminate_check_box" : "check_box_outline_blank")
                        iconSize: Theme.iconSizeSmall + 2
                        iconColor: panel.checkedRows.length > 0 ? Theme.primary : Theme.surfaceVariantText
                        tooltipText: panel.checkedRows.length > 0 ? "Uncheck all" : "Select all"
                        onClicked: {
                            panel.checkAll(!panel.allChecked && panel.checkedRows.length === 0);
                            panel.focusInput();
                        }
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: panel.checkedRows.length === 0 ? "Select all" : (panel.everythingChecked && panel.scopeState.threadsMore ? "All " + panel.rows.length + " loaded selected" : panel.checkedRows.length + " selected")
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.DemiBold
                        color: Theme.surfaceText
                    }
                }

                // All / Unread, as github.com draws it: two segments, the
                // chosen one raised.
                Rectangle {
                    visible: panel.checkedRows.length === 0
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                    width: segments.implicitWidth + 4
                    height: 28
                    radius: Theme.cornerRadius
                    color: Theme.withAlpha(Theme.surfaceText, 0.05)
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.outlineVariant, 0.8)

                    Row {
                        id: segments
                        anchors.centerIn: parent
                        spacing: 0

                        Repeater {
                            model: [
                                {
                                    "label": "All",
                                    "unread": false
                                },
                                {
                                    "label": "Unread",
                                    "unread": true
                                }
                            ]

                            Rectangle {
                                id: segment
                                required property var modelData
                                readonly property bool chosen: panel.unreadOnly === modelData.unread
                                width: segmentText.implicitWidth + Theme.spacingM * 2
                                height: 24
                                radius: Theme.cornerRadius - 2
                                color: chosen ? Theme.surfaceContainerHighest : (segmentArea.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.06) : "transparent")
                                border.width: chosen ? 1 : 0
                                border.color: Theme.withAlpha(Theme.outlineVariant, 0.9)

                                StyledText {
                                    id: segmentText
                                    anchors.centerIn: parent
                                    text: segment.modelData.label
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: segment.chosen ? Font.DemiBold : Font.Normal
                                    color: segment.chosen ? Theme.surfaceText : Theme.surfaceVariantText
                                }

                                MouseArea {
                                    id: segmentArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        panel.setUnreadOnly(segment.modelData.unread);
                                        panel.focusInput();
                                    }
                                }
                            }
                        }
                    }
                }

                Row {
                    visible: panel.checkedRows.length > 0
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingXS

                    Repeater {
                        model: Logic.INBOX_ACTIONS

                        GitHubPillButton {
                            required property var modelData
                            readonly property bool markAll: modelData.key === "read" && panel.everythingChecked
                            anchors.verticalCenter: parent.verticalCenter
                            compact: true
                            icon: modelData.icon
                            text: markAll ? (panel.markAllArmed ? "Click again to mark all as read" : "Mark all as read") : modelData.label
                            tone: markAll && panel.markAllArmed ? Theme.error : Theme.primary
                            tonal: markAll && panel.markAllArmed
                            onActivated: {
                                panel.actOnTargets(modelData.key);
                                panel.focusInput();
                            }
                        }
                    }
                }
            }

            DankListView {
                id: list
                anchors.fill: parent
                anchors.topMargin: bulkBar.height
                clip: true
                model: panel.rows
                currentIndex: panel.selectedIndex
                spacing: 0
                onContentYChanged: pageTimer.restart()
                onContentHeightChanged: pageTimer.restart()
                onHeightChanged: pageTimer.restart()

                // Where the list stands against everything GitHub has.
                footer: Item {
                    width: list.width
                    height: list.count > 0 && (panel.pageable || panel.pageLoading) ? 44 : 0
                    visible: height > 0

                    Row {
                        anchors.centerIn: parent
                        spacing: Theme.spacingS

                        DankSpinner {
                            visible: panel.pageLoading
                            anchors.verticalCenter: parent.verticalCenter
                            size: 16
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: {
                                if (!panel.pageLoading)
                                    return "Scroll for more";
                                if (panel.searchActive)
                                    return "Searching GitHub…";
                                return panel.tab === "inbox" && panel.query.trim() !== "" ? "Loading notifications to filter…" : "Loading more…";
                            }
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }
                }

                delegate: GitHubRow {
                    required property int index
                    required property var modelData

                    width: list.width
                    height: panel.rowHeight
                    item: modelData
                    github: panel.github
                    now: panel.now
                    selected: index === panel.selectedIndex
                    checked: !!panel.checked[modelData.id]
                    onHovered: panel.selectedIndex = index
                    onActivated: panel.activate(modelData)
                    onCheckToggled: {
                        panel.toggleChecked(modelData);
                        panel.focusInput();
                    }
                    onActed: key => panel.act(key, [modelData])
                    onOpenedExternally: panel.openExternally(modelData)
                }
            }

            Column {
                anchors.centerIn: parent
                width: parent.width - Theme.spacingXL * 2
                visible: panel.rows.length === 0
                spacing: Theme.spacingS

                DankIcon {
                    anchors.horizontalCenter: parent.horizontalCenter
                    name: panel.tab === "actions" ? "play_circle" : (panel.tab === "inbox" ? "notifications_none" : "inbox")
                    size: 36
                    color: Theme.surfaceVariantText
                }

                StyledText {
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    textFormat: Text.PlainText
                    color: Theme.surfaceVariantText
                    font.pixelSize: Theme.fontSizeMedium
                    text: {
                        const g = panel.github;
                        const s = panel.scopeState;
                        if (g.authState === "unknown")
                            return "Loading…";
                        // Your lists and a repository's alike: nothing to
                        // say about them before their first answer, and
                        // why they failed.
                        if (panel.tab !== "inbox") {
                            const loaded = panel.tab === "actions" ? s.runsAt > 0 : s.at > 0;
                            const failure = panel.tab === "actions" ? s.runsError : s.error;
                            if (!loaded)
                                return panel.scope ? "Loading " + panel.scope + "…" : "Loading…";
                            if (failure)
                                return failure;
                        }
                        if (panel.tab === "inbox") {
                            if (panel.inboxQuery.unsupported !== "")
                                return panel.inboxQuery.unsupported;
                            if (s.threadsError)
                                return s.threadsError;
                            if (s.threadsAt === 0)
                                return "Loading…";
                        }
                        if (panel.searchActive && (panel.searching || !panel.searchFresh))
                            return "Searching GitHub…";
                        if (panel.searchFresh && panel.searchResult.error)
                            return panel.searchResult.error;
                        if (panel.tab === "inbox" && panel.query && (s.threadsPaging || s.threadsLoading))
                            return "Loading notifications to filter…";
                        if (panel.query)
                            return "Nothing matches “" + panel.query + "”";
                        if (panel.tab === "inbox" && panel.filterKey !== "all")
                            return panel.unreadOnly ? "Nothing unread here." : "Nothing here.";
                        if (panel.tab === "inbox" && panel.unreadOnly)
                            return "No unread notifications.";
                        if (panel.tab === "inbox")
                            return panel.scope ? "No notifications from " + panel.scope + "." : "All caught up!";
                        if (panel.tab === "actions" && panel.scope)
                            return panel.filterKey === "all" ? "No workflow runs in " + panel.scope + "." : "Nothing here right now.";
                        if (panel.scope)
                            return "No " + panel.currentFilters[panel.filterIndex].label.toLowerCase() + (panel.tab === "prs" ? " pull requests" : " issues") + " in " + panel.scope + ".";
                        if (panel.tab === "actions") {
                            if (g.watchedRepos.length === 0)
                                return "No repositories to watch. Add some in Settings > Plugins > GitHub.";
                            return panel.filterKey === "all" ? "No workflow runs in the watched repositories." : "Nothing here right now.";
                        }
                        return "Nothing here. Nice.";
                    }
                }
            }
        }

        StyledText {
            id: footer
            visible: tabRow.visible
            width: parent.width
            leftPadding: Theme.spacingXS
            elide: Text.ElideRight
            textFormat: Text.PlainText
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            text: {
                const g = panel.github;
                let context = "";
                if (panel.tab === "inbox") {
                    if (panel.scopeState.threadsMore && panel.query.trim() === "")
                        context = g.inboxThreads(panel.scope).length + " loaded";
                    return (context !== "" ? context + " · " : "") + ["↵ open", "space select"].concat(Logic.INBOX_ACTIONS.map(action => action.shortcut.toLowerCase() + " " + action.hint)).join(" · ");
                } else if (panel.tab === "actions" && panel.scope) {
                    context = panel.scopeRuns.length + (panel.scopeRuns.length === 1 ? " run" : " runs");
                } else if (panel.tab === "actions") {
                    context = g.watchedRepos.length + (g.watchedRepos.length === 1 ? " repository" : " repositories");
                } else {
                    const total = g.total(panel.filterKey);
                    const shown = g.visibleItems(panel.filterKey).length;
                    if (panel.searchFresh && !panel.searchResult.error)
                        context = panel.searchResult.count + (panel.searchResult.count === 1 ? " result" : " results");
                    else if (total > shown)
                        context = shown + " of " + total;
                }
                return (context !== "" ? context + " · " : "") + "↑↓ move · ↵ details · ctrl+↵ browser · tab switch";
            }
        }

        GitHubDetail {
            id: detail
            visible: !!panel.detailItem && !problem.visible
            width: parent.width
            height: panel.height - header.height - layout.spacing
            item: panel.detailItem
            github: panel.github
            active: panel.showing && !!panel.detailItem
            onBack: panel.closeDetail()
            onOpenItem: item => panel.openDetail(item, true)
            onSearchRequested: (repo, tab, terms) => panel.openSearch(repo, tab, terms)
            onEditingFinished: panel.focusInput()
            onCloseRequested: panel.close()
        }
    }

    GitHubScopeMenu {
        id: scopeMenu
        anchors.fill: parent
        z: 10
        github: panel.github
        scope: panel.scope
        recentRepos: panel.recentRepos
        onPicked: repo => panel.setScope(repo)
        onDismissed: {
            close();
            panel.focusInput();
        }
    }

    GitHubResizer {
        anchors.fill: parent
        visible: !panel.windowed && !!panel.parentPopout
        popout: panel.parentPopout
        onResizing: (width, height) => panel.resizing(width, height)
        onFinished: (width, height) => panel.resized(width, height)
        onResetRequested: panel.resizeReset()
    }
}
