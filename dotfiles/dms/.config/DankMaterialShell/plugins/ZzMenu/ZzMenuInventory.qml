import QtQuick
import Quickshell
import Quickshell.Io

// The rows behind every ZZ menu surface. scripts/zz-menu-inventory merges
// the shipped menu.json with the user's overlay, evaluates the `when`
// guards, and expands the provider groups; this item runs it, keeps the
// result, and runs a row when a surface asks. The bar widget and the
// launcher each own one, so a surface never waits on the other.
Item {
    id: root

    property var pluginService: null

    readonly property string pluginId: "zzMenu"
    readonly property string pluginPath: pluginService ? String(pluginService.getPluginPath(pluginId) || "") : ""
    readonly property string scriptsDir: pluginPath ? pluginPath + "/scripts" : ""
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string overlayPath: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/zz-fedora/menu.json"

    // Groups and rows as the inventory listed them, every row carrying its
    // lowercased search text. `parent` links both into one tree.
    property var groups: []
    property var rows: []
    property double loadedAtMs: 0
    property bool dirty: true
    // Guards and provider lists change under the shell (a tool installed, a
    // seed added), so an inventory older than this is asked for again the
    // next time a surface opens.
    readonly property int staleAfterMs: 60000

    signal loaded()

    function refreshIfStale() {
        if (!scriptsDir || inventory.running)
            return;
        if (!dirty && Date.now() - loadedAtMs < staleAfterMs)
            return;
        dirty = false;
        inventory.running = true;
    }

    // A terminal row runs through zz-menu-run, which keeps the window open
    // for the output and any sudo prompt; everything else runs detached in
    // a login shell so PATH matches an interactive terminal.
    function run(row) {
        if (!row || !row.action || !scriptsDir)
            return;
        const action = String(row.action);
        if (row.terminal)
            Quickshell.execDetached([scriptsDir + "/zz-menu-run", action]);
        else
            Quickshell.execDetached(["bash", "-lc", action]);
    }

    function applyInventory(text) {
        loadedAtMs = Date.now();
        let parsed;
        try {
            parsed = JSON.parse(text);
        } catch (e) {
            console.warn("zzMenu: inventory output is not JSON:", e);
            return;
        }
        const nextGroups = [];
        const sourceGroups = Array.isArray(parsed.groups) ? parsed.groups : [];
        for (let i = 0; i < sourceGroups.length; i++) {
            const group = sourceGroups[i];
            const path = Array.isArray(group.path) ? group.path : [];
            const label = String(group.label || group.id || "");
            const description = String(group.description || "");
            nextGroups.push({
                id: String(group.id || ""),
                parent: String(group.parent || ""),
                label: label,
                icon: String(group.icon || "folder"),
                description: description,
                path: path,
                order: Number(group.order || 0),
                search: [label, description, path.join(" ")].join(" ").toLowerCase()
            });
        }
        const nextRows = [];
        const sourceRows = Array.isArray(parsed.rows) ? parsed.rows : [];
        for (let i = 0; i < sourceRows.length; i++) {
            const row = sourceRows[i];
            const path = Array.isArray(row.path) ? row.path : [];
            const keywords = Array.isArray(row.keywords) ? row.keywords : [];
            const description = String(row.description || "");
            const label = String(row.label || row.id || "");
            nextRows.push({
                id: String(row.id || ""),
                parent: String(row.parent || ""),
                group: String(row.group || ""),
                label: label,
                icon: String(row.icon || "terminal"),
                description: description,
                action: String(row.action || ""),
                terminal: !!row.terminal,
                keywords: keywords,
                path: path,
                order: Number(row.order || 0),
                pathText: path.join(" ").toLowerCase(),
                keywordText: keywords.join(" ").toLowerCase(),
                search: [label, description, path.join(" "), keywords.join(" "), String(row.action || "")].join(" ").toLowerCase()
            });
        }
        groups = nextGroups;
        rows = nextRows;
        loaded();
    }

    // Warm the rows as soon as the plugin path is known, so the first open
    // does not show an empty menu. Deferred one tick: the process command
    // is bound to the same path and must update before the process starts.
    onScriptsDirChanged: {
        if (scriptsDir)
            Qt.callLater(refreshIfStale);
    }

    Process {
        id: inventory
        running: false
        command: [root.scriptsDir + "/zz-menu-inventory"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyInventory(text)
        }

        // A run that lost a provider (a timeout, a failed zz call) is
        // asked for again on the next open instead of standing for a minute.
        onExited: function(exitCode) {
            if (exitCode !== 0) {
                console.warn("zzMenu: inventory exited with status", exitCode);
                root.dirty = true;
            }
        }
    }

    // Edits to either menu file take effect on the next open instead of
    // waiting out the staleness window.
    FileView {
        path: root.pluginPath ? root.pluginPath + "/menu.json" : ""
        watchChanges: true
        printErrors: false
        onFileChanged: root.dirty = true
    }

    FileView {
        path: root.overlayPath
        watchChanges: true
        printErrors: false
        onFileChanged: root.dirty = true
    }
}
