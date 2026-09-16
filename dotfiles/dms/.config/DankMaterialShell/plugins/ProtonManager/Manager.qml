import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginComponent {
    id: lifecycleHost
    property var popoutService: null

    // Keep only the IPC entry alive. The window, models and helper are created
    // on demand and released after closing once any explicit mutation finishes.
    function toggle() {
        if (sessionLoader.item) sessionLoader.item.toggle();
        else sessionLoader.active = true;
    }
    function releaseIfIdle() {
        if (sessionLoader.item?.canUnload) sessionLoader.active = false;
    }
    Loader {
        id: sessionLoader
        active: false
        onLoaded: item.toggle()
        sourceComponent: Component {
            PluginComponent {
                id: root
                pluginService: lifecycleHost.pluginService
                pluginId: lifecycleHost.pluginId
                readonly property bool canUnload: !managerWindow.visible && !busy
                onCanUnloadChanged: {
                    if (canUnload) Qt.callLater(lifecycleHost.releaseIfIdle);
                }
                property var popoutService: null
                readonly property string pluginPath: pluginService && pluginId ? String(pluginService.getPluginPath(pluginId) || "") : ""
                property var inventory: ({roots: [], tools: [], games: [], selection: null, warnings: []})
                property var releases: []
                property string providerId: "ge"
                property int releasePage: 0
                property int requestedPage: 1
                property bool hasMoreReleases: true
                property bool releaseError: false
                property bool paginationPaused: false
                readonly property bool isSteam: !inventory.target || inventory.target.launcher === "steam"
                readonly property var sources: inventory.providers || []
                readonly property string providerName: sources.find(p => p.id === providerId)?.name || "Runtime source"
                property string targetPath: ""
                property string tab: "Games"
                property string scope: "default"
                property string gameId: ""
                property string gameName: ""
                property string query: ""
                property string message: ""
                property bool failed: false
                property string action: ""
                property bool receivedResult: false
                property int progress: -1
                property string pendingRemoval: ""
                property string notes: ""
                property bool notesAreHtml: false
                property string notesTitle: ""
                // Process.running changes only after startup. Reserve the operation before
                // launching so opening the manager cannot overwrite an in-flight command.
                property bool busy: false
                readonly property var selection: inventory.selection
                readonly property string currentPath: !selection ? "" : scope === "game" ? (selection.games[gameId] || "") : (selection[scope] || "")
                readonly property var rows: {
                    const source = tab === "Games" ? inventory.games : tab === "Installed" ? inventory.tools.slice() : releases;
                    if (tab === "Installed") {
                        const rank = tool => isSteam && tool.path === selection?.default ? 0 : 1;
                        source.sort((a, b) => rank(a) - rank(b) || (b.buildTime || 0) - (a.buildTime || 0) || a.name.localeCompare(b.name));
                    }
                    const q = query.toLowerCase();
                    return source.filter(row => (row.name + " " + (row.id || "")).toLowerCase().includes(q));
                }
                // A desktop application entry calls the DMS plugins IPC target. The daemon
                // owns the window and any active download independently of launcher searches.
                function toggle() {
                    if (!managerWindow.visible) {
                        managerWindow.visible = true;
                        refresh();
                        return;
                    }
                    for (const toplevel of ToplevelManager.toplevels.values) {
                        if (toplevel.title !== managerWindow.title) continue;
                        if (toplevel.activated) managerWindow.visible = false;
                        else toplevel.activate();
                        return;
                    }
                    managerWindow.visible = false;
                    managerWindow.visible = true;
                }
                function toolName(path) {
                    if (!path) return "Use active build";
                    const tool = inventory.tools.find(t => t.path === path);
                    return tool ? tool.name : "Unavailable: " + path.split("/").pop();
                }
                ListModel { id: installedRows; dynamicRoles: true }
                function syncInstalledRows() {
                    if (tab !== "Installed") return;
                    const wanted = new Set(rows.map(tool => tool.path));
                    for (let i = installedRows.count - 1; i >= 0; --i) {
                        if (!wanted.has(installedRows.get(i).entry.path)) installedRows.remove(i);
                    }
                    for (let i = 0; i < rows.length; ++i) {
                        let existing = i;
                        while (existing < installedRows.count && installedRows.get(existing).entry.path !== rows[i].path) ++existing;
                        if (existing === installedRows.count) installedRows.insert(i, {entry: rows[i]});
                        else {
                            if (existing !== i) installedRows.move(existing, i, 1);
                            installedRows.setProperty(i, "entry", rows[i]);
                        }
                    }
                }
                onRowsChanged: syncInstalledRows()
                ListModel { id: releaseRows; dynamicRoles: true }
                function matchesQuery(row) {
                    return (row.name + " " + (row.id || "")).toLowerCase().includes(query.toLowerCase());
                }
                function resetReleases() {
                    releases = []; releaseRows.clear(); releasePage = 0;
                    hasMoreReleases = true; releaseError = false; paginationPaused = false;
                }
                function loadReleases(reset = false) {
                    if (busy) return;
                    if (!hasMoreReleases && !reset && !releaseError) return;
                    requestedPage = reset ? 1 : releaseError ? requestedPage : releasePage + 1;
                    releaseError = false;
                    run("releases", []);
                }
                function maybeLoadMore() {
                    if (!managerWindow.visible || tab !== "Download" || busy || releaseError || paginationPaused || !hasMoreReleases || query.trim()) return;
                    if (list.count === 0 || list.contentY + list.height >= list.originY + list.contentHeight - list.height / 2)
                        loadReleases();
                }
                onQueryChanged: {
                    releaseRows.clear();
                    for (const row of releases) if (matchesQuery(row)) releaseRows.append({entry: row});
                    paginationTimer.restart();
                }
                onTabChanged: paginationTimer.restart()
                Timer { id: paginationTimer; interval: 350; onTriggered: root.maybeLoadMore() }
                function refresh() { run("scan", []); }
                function run(kind, args) {
                    if (busy || !pluginPath || (!managerWindow.visible && (kind === "scan" || kind === "releases"))) return;
                    busy = true;
                    action = kind;
                    receivedResult = false;
                    progress = -1;
                    if (kind !== "scan") { failed = false; message = ""; }
                    worker.command = ["/usr/bin/python3", pluginPath + "/scripts/manager.py", kind, "--root", targetPath,
                                      "--provider", providerId, "--page", String(requestedPage)].concat(args);
                    worker.running = true;
                    startupTimeout.restart();
                }
                function setScope(value, id, name) {
                    scope = value; gameId = id || ""; gameName = name || "";
                    tab = "Installed"; query = ""; notes = ""; pendingRemoval = "";
                }
                function choose(path) {
                    run("select", ["--scope", scope, "--game", gameId, "--tool", path]);
                }
                function changeTab(value) {
                    if (value === "Games" && !isSteam) value = "Installed";
                    scope = "default"; gameId = ""; gameName = "";
                    tab = value; query = ""; notes = ""; pendingRemoval = "";
                    if (tab === "Download" && releasePage === 0) loadReleases();
                }
                function handle(line) {
                    try {
                        const result = JSON.parse(line);
                        if (result.type === "progress") {
                            message = result.message; progress = result.percent; return;
                        }
                        receivedResult = true;
                        if (result.type === "error") {
                            failed = true; message = result.message;
                            if (action === "releases") releaseError = true;
                            return;
                        }
                        if (action === "scan") {
                            if (targetPath !== result.root) {
                                scope = "default"; gameId = ""; gameName = ""; pendingRemoval = ""; notes = "";
                                resetReleases();
                            }
                            inventory = result; targetPath = result.root;
                            if (!sources.some(p => p.id === providerId)) {
                                providerId = sources.length ? sources[0].id : "ge";
                                resetReleases();
                            }
                            if (!isSteam && tab === "Games") tab = "Installed";
                        } else if (action === "releases") {
                            // Keep existing results until a refresh has succeeded.
                            if (result.page === 1) { releases = []; releaseRows.clear(); }
                            // Append to the existing model so scrolling does not jump on each page.
                            const seen = new Set(releases.map(row => row.tag + "\n" + row.asset));
                            const added = result.releases.filter(row => {
                                const key = row.tag + "\n" + row.asset;
                                if (seen.has(key)) return false;
                                seen.add(key); return true;
                            });
                            releases = releases.concat(added);
                            for (const row of added) if (matchesQuery(row)) releaseRows.append({entry: row});
                            releasePage = result.page;
                            hasMoreReleases = result.hasMore;
                            // Empty or duplicate-only pages require an explicit request to continue.
                            paginationPaused = added.length === 0;
                            message = result.notice || providerName + " · " + releases.length + " builds loaded" + (result.cached ? " · cached" : "");
                        } else { message = result.message; }
                    } catch (error) { console.warn("Proton response failed:", action, String(error)); failed = true; if (action === "releases") releaseError = true; message = "Could not read the Proton helper response: " + error; }
                }
                Process {
                    id: worker
                    stdout: SplitParser { onRead: data => root.handle(data) }
                    stderr: StdioCollector { id: errors }
                    onStarted: {
                        startupTimeout.stop();
                        if (!managerWindow.visible && (root.action === "scan" || root.action === "releases")) worker.signal(15);
                    }
                    onExited: (exitCode, exitStatus) => {
                        startupTimeout.stop();
                        root.busy = false;
                        root.progress = -1;
                        if (!root.receivedResult) {
                            root.failed = exitCode !== 130;
                            if (root.action === "releases") root.releaseError = true;
                            root.message = exitCode === 130 ? "Operation cancelled." : "Proton helper stopped: " + (errors.text || "exit " + exitCode);
                        }
                        if (managerWindow.visible) {
                            if (root.action !== "scan" && root.action !== "releases") Qt.callLater(root.refresh);
                            paginationTimer.restart();
                        }
                    }
                }

                Timer {
                    id: startupTimeout
                    interval: 3000
                    onTriggered: {
                        if (root.busy && !worker.running) {
                            // Clear Quickshell's pending start intent before accepting another command.
                            worker.running = false;
                            root.busy = false;
                            root.failed = true;
                            if (root.action === "releases") root.releaseError = true;
                            root.message = "Could not start the Proton helper. Check that the system python3 is installed.";
                        }
                    }
                }

                component NavigationTab: Rectangle {
                    id: nav
                    property string label: ""
                    property string icon: ""
                    property string value: ""
                    readonly property bool selected: root.tab === value
                    implicitWidth: tabContents.implicitWidth + Theme.spacingM * 2
                    implicitHeight: Math.round(Theme.fontSizeMedium * 3.1)
                    radius: Theme.cornerRadius
                    color: selected ? Theme.primaryPressed : (hovered.hovered ? Theme.primaryHoverLight : "transparent")
                    border.color: selected ? Theme.primary : "transparent"
                    border.width: selected ? 1 : 0
                    activeFocusOnTab: true
                    opacity: root.busy ? 0.5 : 1
                    function activate() { if (!root.busy) root.changeTab(value); }
                    Keys.onReturnPressed: activate()
                    Keys.onSpacePressed: activate()
                    HoverHandler { id: hovered }
                    TapHandler { onTapped: nav.activate() }
                    Row {
                        id: tabContents
                        anchors.centerIn: parent
                        spacing: Theme.spacingXS
                        DankIcon { name: nav.icon; size: Theme.iconSize - 2; color: nav.selected ? Theme.primary : Theme.surfaceVariantText; anchors.verticalCenter: parent.verticalCenter }
                        StyledText { text: nav.label; color: nav.selected ? Theme.primary : Theme.surfaceText; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
                    }
                }

                DankFloatingWindow {
                    id: managerWindow
                    title: "Proton Manager"
                    implicitWidth: 980
                    implicitHeight: 680
                    minimumSize: Qt.size(Math.min(800, Screen.width), Math.min(520, Screen.height))
                    visible: false
                    onClosed: visible = false
                    onVisibleChanged: {
                        if (visible) paginationTimer.restart();
                        else {
                            paginationTimer.stop();
                            if (root.busy && (root.action === "scan" || root.action === "releases")) worker.signal(15);
                        }
                    }

                    FocusScope {
                        anchors.fill: parent
                        focus: true
                        Keys.onPressed: event => {
                            if ((event.modifiers & Qt.ControlModifier) && event.key >= Qt.Key_1 && event.key <= Qt.Key_3 && !root.busy) {
                                root.changeTab(["Games", "Installed", "Download"][event.key - Qt.Key_1]); event.accepted = true;
                            } else if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
                                search.forceActiveFocus(); event.accepted = true;
                            } else if (event.key === Qt.Key_Escape) {
                                if (root.notes) root.notes = "";
                                else if (root.query) root.query = "";
                                else managerWindow.visible = false;
                                event.accepted = true;
                            }
                        }
                        ColumnLayout {
                            anchors.fill: parent
                            spacing: 0
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.round(Theme.fontSizeMedium * 3.4)
                                MouseArea {
                                    anchors.fill: parent
                                    onPressed: windowControls.tryStartMove()
                                    onDoubleClicked: windowControls.tryToggleMaximize()
                                }
                                Row {
                                    anchors.left: parent.left
                                    anchors.leftMargin: Theme.spacingL
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spacingM
                                    DankIcon { name: "sports_esports"; size: Theme.iconSize; color: Theme.primary; anchors.verticalCenter: parent.verticalCenter }
                                    StyledText { text: "Proton Manager"; font.pixelSize: Theme.fontSizeXLarge; font.weight: Font.Medium; anchors.verticalCenter: parent.verticalCenter }
                                }
                                Row {
                                    anchors.right: parent.right
                                    anchors.rightMargin: Theme.spacingM
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spacingXS
                                    DankActionButton {
                                        iconName: "help_outline"; circular: false; tooltipText: "Set up Proton Manager"
                                        onClicked: {
                                            root.notesTitle = "Getting started";
                                            root.notesAreHtml = false;
                                            root.notes = "Choose an Install for destination, then a source in Download. Heroic has separate Proton and Wine folders. Select installed builds in each launcher’s game settings.\n\nSteam live switching:\n\n1. Open Steam once, then refresh your library.\n\n2. Choose Set as active in Installed, or download a GE-Proton build first.\n\n3. Restart Steam once, then select Proton Manager in each game's Properties → Compatibility.\n\n4. Choose a game here to set its build. Changes apply on the next launch, without restarting Steam.\n\nBuilds must share the registered Steam runtime. Other builds can be selected directly in Steam.\n\nIf the selected build is missing or incompatible, choose another installed build.";
                                        }
                                    }
                                    DankActionButton { iconName: managerWindow.maximized ? "fullscreen_exit" : "fullscreen"; circular: false; tooltipText: "Maximize"; onClicked: windowControls.tryToggleMaximize() }
                                    DankActionButton { iconName: "close"; circular: false; tooltipText: "Close"; onClicked: managerWindow.visible = false }
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: Theme.spacingL
                                Layout.rightMargin: Theme.spacingL
                                Layout.preferredHeight: Math.round(Theme.fontSizeMedium * 3.7)
                                spacing: Theme.spacingM
                                Row {
                                    spacing: Theme.spacingXXS
                                    NavigationTab { visible: root.isSteam; label: "Games"; icon: "sports_esports"; value: "Games" }
                                    NavigationTab { label: "Installed"; icon: "inventory_2"; value: "Installed" }
                                    NavigationTab { label: "Download"; icon: "download"; value: "Download" }
                                }
                                Item { Layout.fillWidth: true }
                                DankTextField {
                                    id: search
                                    Layout.fillWidth: true
                                    Layout.maximumWidth: Math.round(Theme.fontSizeMedium * 22)
                                    Layout.minimumWidth: Theme.fontSizeMedium * 10
                                    Layout.preferredHeight: Math.round(Theme.fontSizeMedium * 2.8)
                                    placeholderText: root.tab === "Games" ? "Search games or App ID…" : "Search builds…"
                                    leftIconName: "search"
                                    showClearButton: true
                                    text: root.query
                                    onTextEdited: root.query = text
                                }
                                DankActionButton {
                                    iconName: "refresh"; tooltipText: "Refresh"; circular: false; enabled: !root.busy
                                    onClicked: root.tab === "Download" ? root.loadReleases(true) : root.refresh()
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: Theme.spacingL
                                Layout.rightMargin: Theme.spacingL
                                Layout.topMargin: Theme.spacingM
                                Layout.bottomMargin: Theme.spacingS
                                spacing: Theme.spacingM
                                StyledText { text: "Install for"; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
                                DankDropdown {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 38
                                    dropdownWidth: width
                                    enabled: !root.busy && root.inventory.roots.length > 0
                                    options: root.inventory.roots.map(t => t.name)
                                    currentValue: root.inventory.target?.name || "No launcher detected"
                                    onValueChanged: value => {
                                        const target = root.inventory.roots.find(t => t.name === value);
                                        if (!target || target.path === root.targetPath) return;
                                        root.targetPath = target.path;
                                        root.resetReleases();
                                        root.scope = "default"; root.gameId = ""; root.query = ""; root.notes = ""; root.pendingRemoval = "";
                                        root.refresh();
                                    }
                                }
                                DankButton {
                                    visible: root.isSteam && root.tab === "Games"
                                    text: "Change active build"; buttonHeight: 30
                                    enabled: !root.busy && !!root.targetPath
                                    onClicked: root.changeTab("Installed")
                                }
                                StyledText { visible: root.tab === "Download"; text: "Source"; color: Theme.surfaceVariantText; font.pixelSize: Theme.fontSizeSmall }
                                DankDropdown {
                                    visible: root.tab === "Download"
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 38
                                    dropdownWidth: width
                                    enableFuzzySearch: true
                                    enabled: !root.busy
                                    options: root.sources.map(p => p.name)
                                    currentValue: root.providerName
                                    onValueChanged: value => {
                                        const source = root.sources.find(p => p.name === value);
                                        if (!source || source.id === root.providerId) return;
                                        root.providerId = source.id; root.resetReleases();
                                        root.notes = ""; root.query = "";
                                        root.loadReleases();
                                    }
                                }
                            }
                            RowLayout {
                                visible: root.tab === "Download" || (root.tab === "Installed" && (!root.isSteam || root.scope === "game")) || (root.tab === "Games" && /^[0-9]{1,20}$/.test(root.query))
                                Layout.fillWidth: true
                                Layout.leftMargin: Theme.spacingL
                                Layout.rightMargin: Theme.spacingL
                                Layout.topMargin: Theme.spacingS
                                Layout.bottomMargin: Theme.spacingS
                                spacing: Theme.spacingS
                                StyledText {
                                    Layout.fillWidth: true
                                    elide: Text.ElideRight
                                    maximumLineCount: 1
                                    font.pixelSize: Theme.fontSizeSmall
                                    color: root.tab === "Installed" ? Theme.primary : Theme.surfaceVariantText
                                    text: root.tab === "Installed" ? (root.isSteam ? (root.scope === "game" ? "Build for " + root.gameName : "Choose your active build") : "Select installed builds in your launcher’s game settings") : root.tab === "Download" ? root.providerName + " · builds for this computer" : "Game compatibility"
                                }
                                DankButton {
                                    visible: root.isSteam && root.tab === "Installed" && root.scope === "game" && !!root.selection?.games[root.gameId]
                                    text: "Use active build"; buttonHeight: 30
                                    enabled: !root.busy
                                    onClicked: root.choose("")
                                }
                                DankButton {
                                    visible: root.isSteam && root.tab === "Installed" && root.scope === "game"
                                    text: "Back to games"; buttonHeight: 30
                                    enabled: !root.busy
                                    onClicked: root.changeTab("Games")
                                }
                                DankButton {
                                    visible: root.isSteam && root.tab === "Games" && /^[0-9]{1,20}$/.test(root.query)
                                    text: "Set App " + root.query
                                    enabled: !root.busy && !!root.selection
                                    buttonHeight: 30; horizontalPadding: Theme.spacingS
                                    onClicked: root.setScope("game", root.query, "Game " + root.query)
                                }
                            }
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                Layout.leftMargin: Theme.spacingL
                                Layout.rightMargin: Theme.spacingL
                                Layout.bottomMargin: Theme.spacingM
                                spacing: Theme.spacingM
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: Theme.cornerRadius
                                    color: Theme.floatingWindowNestedSurface
                                    border.color: Theme.outlineLight
                                    border.width: 1
                                    clip: true
                                    ColumnLayout {
                                        anchors.fill: parent
                                        anchors.margins: 1
                                        spacing: 0
                                        RowLayout {
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 36
                                            Layout.leftMargin: Theme.spacingM
                                            Layout.rightMargin: Theme.spacingM
                                            spacing: Theme.spacingM
                                            StyledText { Layout.fillWidth: true; text: root.tab === "Games" ? "GAME" : "BUILD"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                                            StyledText { visible: root.tab !== "Installed"; Layout.preferredWidth: root.notes ? 110 : 210; Layout.minimumWidth: Layout.preferredWidth; Layout.maximumWidth: Layout.preferredWidth; text: root.tab === "Games" ? "PROTON" : root.tab === "Installed" ? "SOURCE" : "RELEASE"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                                            Item { Layout.preferredWidth: 170 }
                                        }
                                        Rectangle { Layout.fillWidth: true; height: 1; color: Theme.outlineLight }
                                        DankListView {
                                            id: list
                                            Layout.fillWidth: true
                                            Layout.fillHeight: true
                                            clip: true
                                            model: root.tab === "Download" ? releaseRows : root.tab === "Installed" ? installedRows : root.rows
                                            onContentYChanged: paginationTimer.restart()
                                            onContentHeightChanged: paginationTimer.restart()
                                            onHeightChanged: paginationTimer.restart()
                                            footer: Item {
                                                width: list.width
                                                height: root.tab === "Download" && list.count > 0 ? 42 : 0
                                                visible: height > 0
                                                Row {
                                                    anchors.centerIn: parent
                                                    spacing: Theme.spacingS
                                                    StyledText {
                                                        anchors.verticalCenter: parent.verticalCenter
                                                        text: root.releaseError ? "Could not load more releases" : root.busy && root.action === "releases" ? "Loading more releases…" : root.hasMoreReleases ? (root.paginationPaused ? "No new compatible builds on this page" : root.query ? "Searching loaded builds" : "Scroll for more") : "All releases loaded"
                                                        color: root.releaseError ? Theme.error : Theme.surfaceVariantText
                                                        font.pixelSize: Theme.fontSizeSmall
                                                    }
                                                    DankButton { visible: root.releaseError || ((!!root.query || root.paginationPaused) && root.hasMoreReleases); text: root.releaseError ? "Retry" : "Search older releases"; buttonHeight: 28; enabled: !root.busy; onClicked: root.loadReleases() }
                                                }
                                            }
                                            delegate: Rectangle {
                                                id: row
                                                required property var model
                                                readonly property var modelData: (root.tab === "Games" ? model.modelData : model.entry) || ({})
                                                required property int index
                                                width: ListView.view.width
                                                height: Math.round(Theme.fontSizeMedium * 4.5)
                                                readonly property bool installed: root.tab === "Download" && root.inventory.tools.some(t => t.path.split("/").pop() === modelData.name)
                                                readonly property bool active: root.isSteam && root.tab === "Installed" && root.selection?.default === modelData.path
                                                readonly property bool selected: root.tab === "Installed" && root.currentPath === modelData.path
                                                readonly property bool compatible: !root.isSteam || root.tab !== "Installed" || (!!modelData.runtime && (!root.selection || modelData.runtime === root.selection.runtime))
                                                color: active ? Theme.withAlpha(Theme.success, 0.15) : selected ? Theme.primaryPressed : hover.hovered ? Theme.primaryHoverLight : index % 2 ? Theme.withAlpha(Theme.surfaceText, 0.025) : "transparent"
                                                Behavior on color {
                                                    ColorAnimation { duration: Theme.shortDuration; easing.type: Theme.standardEasing }
                                                }
                                                HoverHandler { id: hover }
                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: Theme.spacingM
                                                    anchors.rightMargin: Theme.spacingM
                                                    spacing: Theme.spacingM
                                                    ColumnLayout {
                                                        Layout.minimumWidth: 0
                                                        Layout.fillWidth: true
                                                        spacing: Theme.spacingXS
                                                        StyledText { Layout.fillWidth: true; text: row.modelData.name; maximumLineCount: 1; elide: Text.ElideRight; font.pixelSize: Theme.fontSizeMedium; font.weight: row.active ? Font.Bold : Font.Medium; color: Theme.surfaceText }
                                                        StyledText {
                                                            Layout.fillWidth: true; maximumLineCount: 1; elide: Text.ElideRight; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText
                                                            text: root.tab === "Games" ? "App " + row.modelData.id : root.tab === "Download" ? Math.round(row.modelData.size / 1048576) + " MiB · " + row.modelData.verification + (row.modelData.prerelease ? " · Preview" : "") : !root.isSteam ? row.modelData.path : row.compatible ? (row.modelData.official ? "Steam" : row.modelData.managed ? "Installed by Proton Manager" : "External build") + " · Runtime " + row.modelData.runtime : "Select directly in Steam · different or unknown runtime"
                                                        }
                                                    }
                                                    StyledText {
                                                        visible: root.tab !== "Installed"
                                                        Layout.preferredWidth: root.notes ? 110 : 210
                                                        Layout.minimumWidth: Layout.preferredWidth
                                                        Layout.maximumWidth: Layout.preferredWidth
                                                        maximumLineCount: 2; elide: Text.ElideRight; wrapMode: Text.WordWrap; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText
                                                        text: root.tab === "Games" ? root.toolName(root.selection?.games[row.modelData.id] || "") : root.tab === "Download" ? row.modelData.date : row.modelData.official ? "Steam" : row.modelData.managed ? "Installed by Proton Manager" : "External build"
                                                    }
                                                    RowLayout {
                                                        Layout.preferredWidth: 170
                                                        Layout.minimumWidth: 170
                                                        Layout.maximumWidth: 170
                                                        spacing: Theme.spacingS
                                                        Item { Layout.fillWidth: true }
                                                        DankActionButton {
                                                            iconName: root.tab === "Download" ? "description" : "delete"
                                                            tooltipText: root.tab === "Download" ? "Release notes" : "Remove build"
                                                            circular: false
                                                            visible: root.tab === "Download" || (root.tab === "Installed" && row.modelData.managed && !row.active && !(root.isSteam && Object.values(root.selection?.games || {}).includes(row.modelData.path)))
                                                            enabled: !root.busy
                                                            onClicked: {
                                                                if (root.tab === "Download") {
                                                                    root.notesTitle = row.modelData.name;
                                                                    root.notesAreHtml = !!row.modelData.notesHtml;
                                                                    root.notes = row.modelData.notesHtml || row.modelData.notes || "No release notes available.";
                                                                }
                                                                else root.pendingRemoval = row.modelData.path;
                                                            }
                                                        }
                                                        Item {
                                                            visible: row.selected
                                                            Layout.minimumWidth: 122
                                                            Layout.preferredWidth: 122
                                                            Layout.maximumWidth: 122
                                                            implicitHeight: 30
                                                            Row {
                                                                anchors.centerIn: parent
                                                                spacing: Theme.spacingS
                                                                DankIcon { name: "check"; size: Theme.iconSizeSmall; weight: 700; color: Theme.success; anchors.verticalCenter: parent.verticalCenter }
                                                                StyledText { text: root.scope === "game" ? "Selected" : "Active"; font.pixelSize: Theme.fontSizeMedium; font.weight: Font.Bold; color: Theme.surfaceText; anchors.verticalCenter: parent.verticalCenter }
                                                            }
                                                        }
                                                        DankButton {
                                                            visible: !row.selected
                                                            // DankButton binds width to its text. Override that binding
                                                            // so label changes cannot resize a laid-out button.
                                                            implicitWidth: 122
                                                            width: implicitWidth
                                                            Layout.minimumWidth: 122
                                                            Layout.preferredWidth: 122
                                                            Layout.maximumWidth: 122
                                                            text: root.tab === "Games" ? "Choose" : root.tab === "Installed" ? (root.isSteam ? (root.scope === "game" ? "Use for game" : "Set as active") : "Files") : row.installed ? "Installed" : "Install"
                                                            enabled: !root.busy && !!root.targetPath && row.compatible && !row.selected && !row.installed
                                                            buttonHeight: 30; horizontalPadding: Theme.spacingS
                                                            backgroundColor: Theme.withAlpha(Theme.primary, 0.12)
                                                            textColor: Theme.primary
                                                            onClicked: {
                                                                if (root.tab === "Games") root.setScope("game", row.modelData.id, row.modelData.name);
                                                                else if (root.tab === "Installed") {
                                                                    if (root.isSteam) root.choose(row.modelData.path);
                                                                    else Qt.openUrlExternally("file://" + row.modelData.path.split("/").map(encodeURIComponent).join("/"));
                                                                }
                                                                else root.run("install", ["--tag", row.modelData.tag, "--asset", row.modelData.asset]);
                                                            }
                                                        }
                                                    }
                                                }
                                            }
                                            Column {
                                                anchors.centerIn: parent
                                                width: Math.min(380, parent.width - Theme.spacingL * 2)
                                                spacing: Theme.spacingM
                                                visible: list.count === 0
                                                DankIcon { anchors.horizontalCenter: parent.horizontalCenter; name: root.query ? "search_off" : root.tab === "Download" ? "download" : "sports_esports"; size: 44; color: Theme.surfaceVariantText; opacity: 0.6 }
                                                StyledText {
                                                    width: parent.width; horizontalAlignment: Text.AlignHCenter; font.pixelSize: Theme.fontSizeLarge; font.weight: Font.Medium
                                                    text: root.busy ? "Loading…" : root.releaseError && root.tab === "Download" ? "Could not load releases" : root.query ? "No matches" : !root.targetPath && root.tab !== "Download" ? "Connect a game launcher" : root.tab === "Games" ? "Your games will appear here" : root.tab === "Installed" ? "Choose your first Proton build" : "Find your next Proton build"
                                                }
                                                StyledText {
                                                    width: parent.width; horizontalAlignment: Text.AlignHCenter; wrapMode: Text.WordWrap; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText
                                                    text: root.query ? "Try another name or a numeric Steam App ID." : !root.targetPath && root.tab !== "Download" ? "Open Steam, Heroic, Lutris, Bottles or WineZGUI once, then refresh to discover its builds." : root.tab === "Games" ? "Install a game in Steam, or enter its App ID in search to set a version." : root.tab === "Installed" ? "Browse a runtime source and install a build for this launcher." : "Choose a source above to browse builds for this computer."
                                                }
                                                DankButton {
                                                    anchors.horizontalCenter: parent.horizontalCenter
                                                    visible: (!root.query || root.releaseError || (root.tab === "Download" && root.hasMoreReleases)) && !root.busy
                                                    text: !root.targetPath && root.tab !== "Download" ? "Refresh library" : root.tab === "Download" ? (root.releaseError ? "Retry" : root.releasePage > 0 && root.hasMoreReleases ? "Search older releases" : "Refresh releases") : "Browse builds"
                                                    iconName: !root.targetPath && root.tab !== "Download" ? "refresh" : "download"
                                                    onClicked: !root.targetPath && root.tab !== "Download" ? root.refresh() : root.tab === "Download" ? root.loadReleases(!root.releaseError && !(root.releasePage > 0 && root.hasMoreReleases)) : root.changeTab("Download")
                                                }
                                            }
                                        }
                                    }
                                }
                                Rectangle {
                                    visible: root.notes !== ""
                                    Layout.preferredWidth: Math.min(480, managerWindow.width * 0.45)
                                    Layout.fillHeight: true
                                    color: Theme.floatingWindowNestedSurface
                                    radius: Theme.cornerRadius
                                    border.color: Theme.outlineLight
                                    ColumnLayout {
                                        anchors.fill: parent; anchors.margins: Theme.spacingM; spacing: Theme.spacingM
                                        RowLayout {
                                            Layout.fillWidth: true
                                            StyledText { Layout.fillWidth: true; text: root.notesTitle; wrapMode: Text.WordWrap; font.weight: Font.Medium; font.pixelSize: Theme.fontSizeMedium }
                                            DankActionButton { iconName: "close"; tooltipText: "Close details"; circular: false; onClicked: root.notes = "" }
                                        }
                                        DankFlickable {
                                            id: notesScroll
                                            Layout.fillWidth: true; Layout.fillHeight: true
                                            clip: true; contentHeight: notesText.implicitHeight
                                            StyledText {
                                                id: notesText
                                                width: notesScroll.width
                                                text: root.notes
                                                textFormat: root.notesAreHtml ? Text.RichText : Text.MarkdownText
                                                wrapMode: Text.WrapAtWordBoundaryOrAnywhere
                                                elide: Text.ElideNone
                                                verticalAlignment: Text.AlignTop
                                                linkColor: Theme.primary
                                                font.pixelSize: Theme.fontSizeSmall
                                                color: Theme.surfaceVariantText
                                                onTextChanged: {
                                                    notesScroll.cancelFlick();
                                                    notesScroll.contentY = 0;
                                                }
                                                onLinkActivated: link => {
                                                    if (link.startsWith("https://")) Qt.openUrlExternally(link);
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            RowLayout {
                                visible: root.pendingRemoval !== ""
                                Layout.fillWidth: true; Layout.leftMargin: Theme.spacingL; Layout.rightMargin: Theme.spacingL; Layout.bottomMargin: Theme.spacingS
                                StyledText { Layout.fillWidth: true; text: "Remove " + root.pendingRemoval.split("/").pop() + "?"; maximumLineCount: 1; elide: Text.ElideRight; color: Theme.error }
                                DankButton { text: "Keep"; buttonHeight: 30; onClicked: root.pendingRemoval = "" }
                                DankButton { text: "Remove"; buttonHeight: 30; enabled: !root.busy; backgroundColor: Theme.error; textColor: Theme.surface; onClicked: { root.run("remove", ["--tool", root.pendingRemoval]); root.pendingRemoval = ""; } }
                            }
                            StyledText {
                                visible: root.inventory.warnings.length > 0
                                Layout.fillWidth: true; Layout.leftMargin: Theme.spacingL; Layout.rightMargin: Theme.spacingL; Layout.bottomMargin: Theme.spacingS
                                text: root.inventory.warnings.join("\n"); wrapMode: Text.WordWrap; maximumLineCount: 3; elide: Text.ElideRight; color: Theme.error; font.pixelSize: Theme.fontSizeSmall
                            }
                            Rectangle {
                                Layout.fillWidth: true; height: root.progress >= 0 ? 3 : 1; color: Theme.outlineLight
                                Rectangle { visible: root.progress >= 0; width: parent.width * Math.max(0, root.progress) / 100; height: parent.height; color: Theme.primary }
                            }
                            Item {
                                Layout.fillWidth: true
                                Layout.preferredHeight: Math.max(Math.round(Theme.fontSizeSmall * 2.7), footerContents.implicitHeight)
                                Layout.leftMargin: Theme.spacingL
                                Layout.rightMargin: Theme.spacingL
                                Layout.bottomMargin: Theme.spacingM

                                RowLayout {
                                    id: footerContents
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: Theme.spacingL

                                    RowLayout {
                                        Layout.fillWidth: true
                                        spacing: Theme.spacingXS
                                        DankIcon {
                                            name: root.failed ? "error_outline" : root.busy ? "sync" : "info"
                                            size: 14
                                            color: root.failed ? Theme.error : Theme.info
                                        }
                                        StyledText {
                                            visible: root.tab === "Games" && !root.busy && !root.failed && !!root.selection
                                            text: "Active:"
                                            font.pixelSize: Theme.fontSizeSmall
                                            color: Theme.surfaceVariantText
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            wrapMode: Text.WordWrap
                                            maximumLineCount: 2
                                            elide: Text.ElideRight
                                            font.pixelSize: Theme.fontSizeSmall
                                            readonly property bool showsActive: root.tab === "Games" && !root.busy && !root.failed && !!root.selection
                                            font.weight: showsActive ? Font.Bold : Font.Normal
                                            color: root.failed ? Theme.error : showsActive ? Theme.surfaceText : Theme.surfaceVariantText
                                            text: root.tab === "Games" && !root.busy && !root.failed ? (root.selection ? root.toolName(root.selection.default) : "No active build selected") : (root.message || (root.busy ? "Loading…" : !root.targetPath ? "Open a supported launcher, then refresh" : !root.isSteam ? "Choose installed builds in your launcher’s game settings" : root.selection ? "Ready · changes apply on the next game launch" : "Choose an active build to get started")) + (root.progress >= 0 ? " · " + root.progress + "%" : "")
                                        }
                                    }
                                    DankButton { visible: root.busy && root.action === "install"; text: "Cancel"; buttonHeight: 28; onClicked: worker.signal(15) }
                                    Row {
                                        visible: root.isSteam
                                        spacing: Theme.spacingXS
                                        StyledText { text: "Games:"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                                        StyledText { text: root.inventory.games.length; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold; color: Theme.surfaceText }
                                    }
                                    Row {
                                        spacing: Theme.spacingXS
                                        StyledText { text: "Builds:"; font.pixelSize: Theme.fontSizeSmall; color: Theme.surfaceVariantText }
                                        StyledText { text: root.inventory.tools.length; font.pixelSize: Theme.fontSizeSmall; font.weight: Font.Bold; color: Theme.surfaceText }
                                    }
                                }
                            }
                        }
                    }
                    FloatingWindowControls { id: windowControls; targetWindow: managerWindow }
                }
            }
        }
    }
}
