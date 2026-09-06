import QtQuick
import Quickshell
import Quickshell.Io

// The display side of agent usage. All extraction lives behind
// scripts/update-usage, which writes one JSON record per agent into the
// usage directory; this file only discovers those records, watches them for
// changes, and optionally merges snapshots synced from other machines.
Item {
    id: root
    visible: false

    // The plugin's saved settings (pluginData), read through setting().
    property var settings: ({})
    // Directory holding update-usage and the collectors; empty until the
    // plugin path is known, and nothing runs before then.
    property string scriptsDir: ""

    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string usageDir: (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/zz-fedora/agent-usage"

    // ------------------------------------------------------------- discovery

    property var agentIds: []
    property var agents: []
    property int dataRevision: 0

    Process {
        id: listProcess
        running: false
        command: ["find", root.usageDir, "-maxdepth", "1", "-name", "*.json", "-printf", "%f\n"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyAgentListing(text)
        }
    }

    function rescanAgents() {
        if (!listProcess.running)
            listProcess.running = true;
    }

    function applyAgentListing(output) {
        const ids = [];
        const lines = String(output || "").split("\n");
        for (let i = 0; i < lines.length; i++) {
            const name = lines[i].trim();
            if (name.slice(-5) === ".json")
                ids.push(name.slice(0, -5));
        }
        ids.sort();
        // Same list, same objects: reassigning the model would tear down
        // every FileView just to build identical ones.
        if (JSON.stringify(ids) !== JSON.stringify(agentIds))
            agentIds = ids;
    }

    Instantiator {
        id: agentInstantiator
        model: root.agentIds

        delegate: UsageRecord {
            required property var modelData
            agentId: modelData
            path: root.usageDir + "/" + modelData + ".json"
            onRecordChanged: root.recordsChanged()
        }

        onObjectAdded: (index, object) => root.rebuildAgents()
        onObjectRemoved: (index, object) => root.rebuildAgents()
    }

    function rebuildAgents() {
        const result = [];
        for (let i = 0; i < agentInstantiator.count; i++) {
            const agent = agentInstantiator.objectAt(i);
            if (agent)
                result.push(agent);
        }
        agents = result;
        recordsChanged();
    }

    function recordsChanged() {
        dataRevision++;
        scheduleLimitsRetry();
        scheduleSync();
    }

    // A collector that could not reach its limits endpoint at all (typically
    // the seconds after login before the network is up) writes retryAdvised
    // into its record. Honor it with one sooner try per refresh cycle
    // instead of waiting out the full interval. The retry itself rewrites
    // the record, and re-arming on that write would turn an offline stretch
    // into a probe every 30 seconds, so the next try waits for the periodic
    // refresh (or a forced one). Only the advising agents rerun.
    property var retryAgentIds: []
    property bool limitsRetrySpent: false

    Timer {
        id: limitsRetry
        interval: 30000
        repeat: false
        onTriggered: {
            root.limitsRetrySpent = true;
            root.runUpdate("limits", root.retryAgentIds);
        }
    }

    function scheduleLimitsRetry() {
        const advising = [];
        for (let i = 0; i < agents.length; i++) {
            const record = agents[i] ? agents[i].record : null;
            if (record && record.retryAdvised === true && providerEnabled(String(record.id || "")))
                advising.push(String(record.id));
        }
        retryAgentIds = advising;
        if (advising.length === 0)
            limitsRetry.stop();
        else if (!limitsRetrySpent)
            limitsRetry.restart();
    }

    Component.onCompleted: {
        rescanAgents();
        if (syncConfigured())
            scheduleSync();
    }

    // -------------------------------------------------------------- refresh

    property int refreshIntervalSec: Math.max(30, Number(setting("refreshIntervalSec", 900)) || 900)
    property string pendingUpdateKind: ""

    Timer {
        interval: root.refreshIntervalSec * 1000
        running: root.scriptsDir !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshAll(false)
    }

    Process {
        id: updateProcess
        running: false
        onExited: {
            root.rescanAgents();
            if (root.pendingUpdateKind !== "") {
                const kind = root.pendingUpdateKind;
                root.pendingUpdateKind = "";
                root.runUpdate(kind);
            }
        }

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (text.trim() !== "")
                console.warn("agentUsage", text.trim())
        }
    }

    // The collectors shipped in scripts/; each has a matching toggle in
    // Settings.qml. A switched-off agent is skipped at the source rather
    // than hidden after a scan.
    readonly property var collectorIds: ["claude", "codex"]

    function updateCommand(kind, agentIds) {
        const command = [scriptsDir + "/update-usage"];
        if (kind === "force")
            command.push("--force");
        if (kind === "limits")
            command.push("--limits-only");
        for (let k = 0; k < collectorIds.length; k++) {
            if (!providerEnabled(collectorIds[k]))
                command.push("--except", collectorIds[k]);
        }
        if (agentIds) {
            for (let i = 0; i < agentIds.length; i++)
                command.push(agentIds[i]);
        }
        return command;
    }

    function runUpdate(kind, agentIds) {
        if (scriptsDir === "")
            return;
        if (updateProcess.running) {
            // Collapse queued requests to one rerun; a forced refresh
            // outranks the cheaper kinds it might have been queued behind.
            if (kind === "force" || root.pendingUpdateKind === "")
                root.pendingUpdateKind = kind;
            return;
        }
        updateProcess.command = updateCommand(kind, agentIds);
        updateProcess.running = true;
    }

    function refreshAll(force) {
        limitsRetrySpent = false;
        runUpdate(force === true ? "force" : "normal");
    }

    // Opening the popout wants the numbers that go stale on the wire, not
    // another walk over every transcript on disk; the collectors reuse
    // their recent scans in this mode.
    function refreshLimits() {
        runUpdate("limits");
    }

    // ------------------------------------------------------------- providers

    // An agent earns a place in the bar and the popout by being switched on
    // in settings and having actually produced numbers, locally or on a
    // synced device. With nothing to show, the widget leaves the bar.
    readonly property var enabledProviders: {
        const rev = dataRevision;
        const syncRev = syncRevision;
        const result = [];
        const localIds = {};
        for (let i = 0; i < agents.length; i++) {
            const record = agents[i] ? agents[i].record : null;
            if (!record || !record.id)
                continue;
            const id = String(record.id);
            localIds[id] = true;
            if (!providerEnabled(id))
                continue;
            const display = displayProvider(record);
            if (providerHasData(display))
                result.push(display);
        }
        // An agent that only ever ran on another machine has no local
        // record, but its synced numbers still deserve a tab. Rate limits
        // stay blank: they are per-account and never travel.
        const syncedProviders = syncConfigured() && aggregateData && aggregateData.providers ? aggregateData.providers : {};
        for (const syncedId in syncedProviders) {
            if (localIds[syncedId] || !providerEnabled(syncedId))
                continue;
            const stats = syncedProviders[syncedId] || {};
            const syncedDisplay = displayProvider({
                id: syncedId,
                name: stats.providerName || syncedId
            });
            if (providerHasData(syncedDisplay))
                result.push(syncedDisplay);
        }
        return result;
    }

    // Settings keep one flat boolean per agent (claudeEnabled, ...); an
    // agent without a key is enabled.
    function providerEnabled(id) {
        const value = settings ? settings[id + "Enabled"] : undefined;
        return value !== false;
    }

    // All-time keeps a quiet day from hiding an agent; today's counts admit
    // a machine whose only source is history.jsonl, which knows nothing older.
    function providerHasData(p) {
        return numberValue(p.totalPrompts) > 0 || numberValue(p.totalSessions) > 0
            || numberValue(p.activeDays) > 0 || numberValue(p.todayPrompts) > 0
            || numberValue(p.todaySessions) > 0 || (p.limits && p.limits.length > 0);
    }

    // What the widget draws for one agent: the record's own limits and
    // status (per-account, never merged) over whichever stats are widest,
    // the synced aggregate when there is one and the local record otherwise.
    function displayProvider(record) {
        const stats = syncedStatsFor(String(record.id));
        const source = stats || record;

        return {
            providerId: String(record.id),
            providerName: String(record.name || record.id),
            usageStatusText: String(record.usageStatusText || ""),
            authHelpText: String(record.authHelpText || ""),
            limits: Array.isArray(record.limits) ? record.limits : [],
            tierLabel: String(record.tierLabel || ""),
            todayPrompts: numberValue(source.todayPrompts),
            todaySessions: numberValue(source.todaySessions),
            recentDays: source.recentDays || [],
            totalPrompts: numberValue(source.totalPrompts),
            totalSessions: numberValue(source.totalSessions),
            activeDays: numberValue(source.activeDays),
            modelUsage: source.modelUsage || ({}),
            syncEnabled: !!stats,
            syncDeviceCount: stats ? numberValue(stats.deviceCount) : 0
        };
    }

    function setting(name, fallback) {
        const value = settings ? settings[name] : undefined;
        return value === undefined || value === null ? fallback : value;
    }

    // ------------------------------------------------------------------ sync

    property bool syncEnabled: setting("syncEnabled", false) === true
    property string syncDir: String(setting("syncDir", ""))
    property string syncFileName: String(setting("syncFileName", ""))
    property string syncDeviceId: String(setting("syncDeviceId", ""))
    property string detectedHostname: ""
    readonly property string syncEffectiveDir: expandPath(syncDir)
    readonly property string syncEffectiveFileName: safeSnapshotFileName(syncFileName, syncDeviceId)
    readonly property string syncEffectiveDeviceId: safeDeviceId(syncDeviceId || syncEffectiveFileName.replace(/\.json$/i, ""))
    readonly property string syncSnapshotPath: syncConfigured() ? syncEffectiveDir + "/" + syncEffectiveFileName : ""
    property var aggregateData: ({})
    property int syncRevision: 0
    readonly property bool syncRunning: syncMkdirProcess.running || syncScanProcess.running
    property bool syncRequestedWhileRunning: false
    property string syncStatusText: ""
    // The last snapshot published, so an unchanged one is not rewritten:
    // every rewrite is a file change for every device sharing the folder.
    property string lastSnapshotKey: ""

    onSyncEnabledChanged: syncSettingsChanged()
    onSyncDirChanged: syncSettingsChanged()
    onSyncFileNameChanged: if (syncConfigured())
        scheduleSync()
    onSyncDeviceIdChanged: if (syncConfigured())
        scheduleSync()

    Timer {
        id: syncDebounce
        interval: 1000
        repeat: false
        onTriggered: root.runSync()
    }

    Process {
        id: syncMkdirProcess
        running: false
        onExited: function (exitCode) {
            if (exitCode !== 0) {
                if (root.syncConfigured())
                    root.syncStatusText = "Usage sync mkdir failed";
                root.finishSyncRun();
                return;
            }
            root.writeSyncSnapshot();
        }
    }

    Process {
        id: syncScanProcess
        running: false
        onExited: function (exitCode) {
            if (exitCode !== 0 && root.syncConfigured())
                root.syncStatusText = "Usage sync scan failed";
            root.finishSyncRun();
        }

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.parseSyncScanOutput(text)
        }

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (text.trim() !== "")
                console.warn("agentUsage/sync", text.trim())
        }
    }

    FileView {
        id: syncSnapshotFile
        path: root.syncSnapshotPath
        watchChanges: false
        atomicWrites: true
        printErrors: false
        // Writes are asynchronous: scanning the folder before this one lands
        // would merge a set of snapshots that lacks this device.
        onSaved: root.startSyncScan()
        onSaveFailed: error => {
            console.warn("agentUsage/sync", "Could not write usage snapshot", root.syncSnapshotPath, error);
            root.lastSnapshotKey = "";
            root.startSyncScan();
        }
    }

    FileView {
        id: hostnameFile
        path: "/etc/hostname"
        watchChanges: false
        printErrors: false
        onLoaded: root.detectedHostname = String(text() || "").trim()
    }

    function syncConfigured() {
        return root.syncEnabled === true && String(root.syncDir || "").trim() !== "";
    }

    function syncSettingsChanged() {
        if (syncConfigured()) {
            scheduleSync();
        } else {
            syncDebounce.stop();
            syncRequestedWhileRunning = false;
            aggregateData = ({});
            syncStatusText = "";
            syncRevision++;
        }
    }

    function scheduleSync() {
        if (!syncConfigured())
            return;
        syncDebounce.restart();
    }

    function runSync() {
        if (!syncConfigured())
            return;
        if (root.syncRunning) {
            syncRequestedWhileRunning = true;
            return;
        }

        syncRequestedWhileRunning = false;
        syncStatusText = "";
        syncMkdirProcess.command = ["mkdir", "-p", root.syncEffectiveDir];
        syncMkdirProcess.running = true;
    }

    function writeSyncSnapshot() {
        if (!syncConfigured()) {
            finishSyncRun();
            return;
        }
        const snapshot = localSnapshot();
        const key = syncSnapshotPath + "\n" + JSON.stringify(snapshot.providers);
        if (key === lastSnapshotKey) {
            startSyncScan();
            return;
        }
        lastSnapshotKey = key;
        syncSnapshotFile.setText(JSON.stringify(snapshot, null, 2) + "\n");
    }

    function startSyncScan() {
        if (!syncConfigured()) {
            finishSyncRun();
            return;
        }
        const script = "dir=$0; [[ -d \"$dir\" ]] || exit 0; shopt -s nullglob; for f in \"$dir\"/*.json; do [[ -f \"$f\" ]] || continue; printf '===%s===\\n' \"$f\"; cat \"$f\"; printf '\\n=== EOM ===\\n'; done";
        syncScanProcess.command = ["bash", "-c", script, root.syncEffectiveDir];
        syncScanProcess.running = true;
    }

    function finishSyncRun() {
        if (syncRequestedWhileRunning && syncConfigured()) {
            syncRequestedWhileRunning = false;
            scheduleSync();
        }
    }

    function expandPath(path) {
        const value = String(path || "").trim();
        if (value === "")
            return "";
        if (value === "~")
            return home;
        if (value.indexOf("~/") === 0)
            return home + value.substring(1);
        if (value.indexOf("$HOME/") === 0)
            return home + value.substring(5);
        if (value.charAt(0) !== "/")
            return home + "/" + value;
        return value;
    }

    function safeDeviceId(raw) {
        let value = String(raw || "").trim();
        if (value === "")
            value = Quickshell.env("HOSTNAME") || root.detectedHostname || Quickshell.env("HOST") || Quickshell.env("USER") || "device";
        value = value.replace(/[^A-Za-z0-9_.-]+/g, "-").replace(/^[._-]+|[._-]+$/g, "");
        if (value === "")
            value = "device";
        return value.length > 80 ? value.substring(0, 80) : value;
    }

    function safeSnapshotFileName(rawFileName, rawDeviceId) {
        let value = String(rawFileName || "").trim();
        if (value === "")
            value = safeDeviceId(rawDeviceId) + ".json";
        value = value.split("/").pop().replace(/[^A-Za-z0-9_.-]+/g, "-").replace(/^[._-]+|[._-]+$/g, "");
        if (value === "")
            value = safeDeviceId(rawDeviceId) + ".json";
        if (!/\.json$/i.test(value))
            value += ".json";
        return value.length > 100 ? value.substring(0, 95) + ".json" : value;
    }

    function parseSyncScanOutput(output) {
        const lines = String(output || "").split("\n");
        const snapshots = [];
        let currentPath = "";
        let currentJson = [];

        function flush() {
            if (currentPath === "")
                return;
            const raw = currentJson.join("\n").trim();
            try {
                const parsed = JSON.parse(raw);
                if (parsed && parsed.providers)
                    snapshots.push(parsed);
            } catch (e) {
                console.warn("agentUsage/sync", "Ignoring bad snapshot", currentPath, e);
            }
            currentPath = "";
            currentJson = [];
        }

        for (let i = 0; i < lines.length; i++) {
            const line = lines[i];
            const start = line.match(/^===(.+)===$/);
            if (start && line !== "=== EOM ===") {
                flush();
                currentPath = start[1];
                currentJson = [];
                continue;
            }
            if (line === "=== EOM ===") {
                flush();
                continue;
            }
            if (currentPath !== "")
                currentJson.push(line);
        }
        flush();

        aggregateData = aggregateSnapshots(snapshots);
        syncStatusText = "";
        syncRevision++;
    }

    function cloneValue(value, fallback) {
        if (value === undefined || value === null)
            return fallback;
        try {
            return JSON.parse(JSON.stringify(value));
        } catch (e) {
            return fallback;
        }
    }

    function numberValue(value) {
        const n = Number(value || 0);
        return isFinite(n) ? Math.round(n) : 0;
    }

    function dateString(date) {
        const y = date.getFullYear();
        const m = String(date.getMonth() + 1).padStart(2, "0");
        const d = String(date.getDate()).padStart(2, "0");
        return y + "-" + m + "-" + d;
    }

    function recentDateStrings() {
        const result = [];
        for (let offset = 6; offset >= 0; offset--) {
            const date = new Date();
            date.setDate(date.getDate() - offset);
            result.push(dateString(date));
        }
        return result;
    }

    function emptyTokenBucket() {
        return {
            inputTokens: 0,
            outputTokens: 0,
            cacheReadInputTokens: 0,
            cacheCreationInputTokens: 0
        };
    }

    function addObjectNumbers(target, source) {
        for (const key in source || {})
            target[key] = numberValue(target[key]) + numberValue(source[key]);
    }

    // Every snapshot is one device's own scan, so counts add up across
    // machines; only the active days overlap in time and are unioned.
    function aggregateSnapshots(snapshots) {
        const dates = recentDateStrings();
        const providers = {};

        function providerAcc(id) {
            if (providers[id])
                return providers[id];
            const recentByDay = {};
            for (let d = 0; d < dates.length; d++)
                recentByDay[dates[d]] = 0;
            providers[id] = {
                providerId: id,
                providerName: "",
                todayPrompts: 0,
                todaySessions: 0,
                recentByDay: recentByDay,
                totalPrompts: 0,
                totalSessions: 0,
                activeDays: 0,
                activeDates: ({}),
                modelUsage: ({}),
                devices: ({})
            };
            return providers[id];
        }

        for (let i = 0; i < snapshots.length; i++) {
            const snapshot = snapshots[i];
            const device = safeDeviceId(snapshot.deviceId || "device");
            const snapshotProviders = snapshot.providers || {};
            for (const providerId in snapshotProviders) {
                const stats = snapshotProviders[providerId] || {};
                const acc = providerAcc(String(providerId));
                acc.devices[device] = true;
                if (stats.providerName && acc.providerName === "")
                    acc.providerName = String(stats.providerName);
                acc.todayPrompts += numberValue(stats.todayPrompts);
                acc.todaySessions += numberValue(stats.todaySessions);
                acc.totalPrompts += numberValue(stats.totalPrompts);
                acc.totalSessions += numberValue(stats.totalSessions);
                const activeDates = Array.isArray(stats.activeDates) ? stats.activeDates : [];
                for (let ad = 0; ad < activeDates.length; ad++)
                    acc.activeDates[String(activeDates[ad])] = true;
                acc.activeDays = Math.max(acc.activeDays, numberValue(stats.activeDays));

                const recent = Array.isArray(stats.recentDays) ? stats.recentDays : [];
                for (let r = 0; r < recent.length; r++) {
                    const day = recent[r] || {};
                    const date = String(day.date || "");
                    if (acc.recentByDay[date] !== undefined)
                        acc.recentByDay[date] += numberValue(day.messageCount);
                }

                const usage = stats.modelUsage || {};
                for (const modelId in usage) {
                    if (!acc.modelUsage[modelId])
                        acc.modelUsage[modelId] = emptyTokenBucket();
                    addObjectNumbers(acc.modelUsage[modelId], usage[modelId]);
                }
            }
        }

        const outProviders = {};
        for (const id in providers) {
            const acc = providers[id];
            const recentDays = [];
            for (let di = 0; di < dates.length; di++)
                recentDays.push({
                    date: dates[di],
                    messageCount: acc.recentByDay[dates[di]] || 0
                });
            outProviders[id] = {
                providerId: acc.providerId,
                providerName: acc.providerName,
                todayPrompts: acc.todayPrompts,
                todaySessions: acc.todaySessions,
                recentDays: recentDays,
                totalPrompts: acc.totalPrompts,
                totalSessions: acc.totalSessions,
                activeDays: Math.max(acc.activeDays, Object.keys(acc.activeDates).length),
                modelUsage: acc.modelUsage,
                deviceCount: Object.keys(acc.devices).length
            };
        }

        return {
            schemaVersion: 1,
            providers: outProviders
        };
    }

    function providerSnapshot(record) {
        return {
            providerId: String(record.id),
            providerName: String(record.name || record.id),
            todayPrompts: numberValue(record.todayPrompts),
            todaySessions: numberValue(record.todaySessions),
            recentDays: cloneValue(record.recentDays, []),
            totalPrompts: numberValue(record.totalPrompts),
            totalSessions: numberValue(record.totalSessions),
            activeDays: numberValue(record.activeDays),
            activeDates: cloneValue(record.activeDates, []),
            modelUsage: cloneValue(record.modelUsage, ({}))
        };
    }

    function localSnapshot() {
        const providerMap = {};
        for (let i = 0; i < agents.length; i++) {
            const record = agents[i] ? agents[i].record : null;
            if (!record || !record.id)
                continue;
            if (!providerEnabled(String(record.id)))
                continue;
            providerMap[String(record.id)] = providerSnapshot(record);
        }
        return {
            schemaVersion: 1,
            deviceId: syncEffectiveDeviceId,
            updatedAt: new Date().toISOString(),
            providers: providerMap
        };
    }

    function syncedStatsFor(providerId) {
        const rev = syncRevision;
        if (!syncConfigured() || !aggregateData || !aggregateData.providers)
            return null;
        return aggregateData.providers[providerId] || null;
    }

    // ---------------------------------------------------------------- format

    function formatTokenCount(n) {
        if (n === undefined || n === null)
            return "0";
        if (n >= 1e9)
            return (n / 1e9).toFixed(1) + "B";
        if (n >= 1e6)
            return (n / 1e6).toFixed(1) + "M";
        if (n >= 1e3)
            return (n / 1e3).toFixed(1) + "K";
        return String(n);
    }

    function modelWordCase(word) {
        if (word === "gpt")
            return "GPT";
        if (word === "deepseek")
            return "DeepSeek";
        return word.charAt(0).toUpperCase() + word.slice(1);
    }

    // Model ids arrive hyphenated with the version split across segments
    // (`claude-opus-4-8`, `gpt-5.6-sol`). Rejoin the numeric run into one
    // version and title-case the words around it.
    function friendlyModelName(id) {
        if (!id)
            return "Unknown";
        const name = String(id).replace(/^claude-/, "").replace(/-\d{8}$/, "");
        const parts = name.split("-");
        const words = [];
        let version = [];
        for (let i = 0; i < parts.length; i++) {
            const part = parts[i];
            if (part === "")
                continue;
            if (/^\d/.test(part)) {
                version.push(part);
                continue;
            }
            if (version.length > 0) {
                words.push(version.join("."));
                version = [];
            }
            words.push(modelWordCase(part));
        }
        if (version.length > 0)
            words.push(version.join("."));
        return words.length > 0 ? words.join(" ") : "Unknown";
    }
}
