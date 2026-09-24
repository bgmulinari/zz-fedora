import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import qs.Widgets
import qs.Modules.Plugins
import "GitHubLogic.js" as Logic

// The plugin's one background instance, whatever the number of bars: it
// owns the GitHub data (GitHubData) and its background polls (the lists or
// the bar's counts, and the notifications; a panel on screen polls what it
// shows), raises the desktop notifications, and keeps the pop-out windows,
// so a second monitor adds a mark, not a second set of requests. Each bar's widget (GitHubWidget)
// reads this through pluginService.pluginDaemonInstances.
PluginComponent {
    id: daemon

    property var popoutService: null

    readonly property string pluginPath: pluginService && pluginId ? String(pluginService.getPluginPath(pluginId) || "") : ""
    readonly property int refreshSeconds: Math.max(60, Number(pluginData.refreshIntervalSec || 300))
    readonly property GitHubData github: githubData

    GitHubData {
        id: githubData
        pluginDir: daemon.pluginPath
        settings: daemon.pluginData
    }

    // ---------------------------------------------------------------- state
    //
    // Plugin state (github_state.json), shared by every bar: the popout and
    // window sizes, the popout's scope, the recent repositories, and what
    // was announced.

    // Bumped whenever the plugin state changes, so readers read it again.
    property int stateRevision: 0

    Connections {
        target: daemon.pluginService
        function onPluginStateChanged(changedId) {
            if (changedId === daemon.pluginId)
                daemon.stateRevision++;
        }
    }

    function loadState(key, fallback) {
        return pluginService && pluginId ? pluginService.loadPluginState(pluginId, key, fallback) : fallback;
    }

    function saveState(key, value) {
        if (pluginService && pluginId)
            pluginService.savePluginState(pluginId, key, value);
    }

    function stateNumber(key) {
        stateRevision;
        return Number(loadState(key, 0)) || 0;
    }

    // The popout's size, until a drag gives it another; a window starts at
    // the size the last one closed with, or at the popout's.
    readonly property int popoutWidth: stateNumber("popoutWidth") || 480
    readonly property int popoutHeight: stateNumber("popoutHeight") || 640

    // The repositories opened lately, newest first, for the scope picker,
    // and the popout's own scope; a window keeps the scope it opened with.
    readonly property int recentKept: 6
    readonly property var recentRepos: {
        stateRevision;
        const saved = loadState("recentRepos", []);
        return Array.isArray(saved) ? saved.filter(repo => Logic.isRepo(repo)) : [];
    }
    readonly property string popoutScope: {
        stateRevision;
        const saved = loadState("scope", "");
        return Logic.isRepo(saved) ? String(saved) : "";
    }

    function rememberRepo(repo) {
        if (recentRepos[0] !== repo)
            saveState("recentRepos", [repo].concat(recentRepos.filter(other => other !== repo)).slice(0, recentKept));
    }

    // ---------------------------------------------------------------- polls

    // The lists on the refresh interval: in full while a popout or window
    // shows them, and otherwise only the counts the bar shows, which also
    // say which account gh is on (a switch or a new sign-in shows then).
    Timer {
        interval: daemon.refreshSeconds * 1000
        running: daemon.pluginPath !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            if (githubData.watched)
                githubData.refreshInbox();
            else
                githubData.refreshBadge();
        }
    }

    // Notifications are what the dot and the desktop notifications report,
    // so they refresh on their own clock: as often as GitHub's
    // X-Poll-Interval allows (a minute). The polls are conditional, and an
    // unchanged inbox answers 304, which costs no rate limit.
    Timer {
        interval: Math.max(60, githubData.notificationPollSeconds) * 1000
        running: daemon.pluginPath !== ""
        repeat: true
        triggeredOnStart: true
        onTriggered: githubData.refreshNotifications({
            "conditional": true
        })
    }

    // --------------------------------------------------- desktop notifications
    //
    // A thread GitHub reports that is news (Logic.announce: changed since
    // seen, or newer than anything seen) becomes a desktop notification,
    // when its reason is one the settings ask for. What was seen is plugin
    // state kept per account across restarts, so nothing is announced twice,
    // and the first look only records, so enabling this does not replay the
    // inbox. A click opens the thread in the popout of the focused screen.
    readonly property string desktopNotifications: String(pluginData.desktopNotifications || "direct")
    readonly property var directReasons: ["assign", "review_requested", "mention", "team_mention", "approval_requested"]
    // More at once than this become one summary.
    readonly property int announceLimit: 3
    // notify-send waits for the click until the notification closes (a
    // popup that times out closes it); this bounds a wait that never ends.
    readonly property int clickWaitMs: 1800000
    // Whether notify-send (libnotify) is there; unknown until checked.
    property bool canNotify: true
    property bool toldNoNotify: false

    Component.onCompleted: {
        Proc.runCommand("github.notifySend", ["sh", "-c", "command -v notify-send >/dev/null 2>&1"], (out, code) => {
            daemon.canNotify = code === 0;
        });
    }

    // The record is per account, so the first look waits for both the
    // login and an answer about the inbox for it, whichever comes last.
    Connections {
        target: githubData
        function onNotificationsChanged() {
            daemon.announceNew();
        }
        function onNotificationsReadyChanged() {
            daemon.announceNew();
        }
    }

    function announceNew() {
        if (!pluginService || !pluginId || !githubData.notificationsReady)
            return;
        const saved = loadState("announced", null);
        const result = Logic.announce(saved, githubData.login, githubData.notifications);
        if (!githubData.sameJson(saved, result.state))
            saveState("announced", result.state);
        if (desktopNotifications === "off")
            return;
        const wanted = result.fresh.filter(thread => desktopNotifications === "all" || directReasons.indexOf(thread.reason) >= 0);
        if (wanted.length === 0)
            return;
        if (!canNotify) {
            if (!toldNoNotify)
                ToastService.showWarning("GitHub", "Desktop notifications need notify-send (the libnotify package).");
            toldNoNotify = true;
            return;
        }
        if (wanted.length > announceLimit) {
            notify(wanted.length + " new GitHub notifications", wanted.slice(0, announceLimit).map(thread => "• " + thread.title).join("\n") + "\n…", null);
            return;
        }
        for (const thread of wanted)
            notify((thread.number > 0 ? "#" + thread.number + " " : "") + thread.title, (Logic.REASONS[thread.reason] || thread.reason) + " · " + thread.repo, thread);
    }

    // Titles are anyone's words: "--" keeps one that starts with a dash
    // from reading as an option, and the body, which notification servers
    // read as markup, is escaped.
    function notify(summary, body, thread) {
        notifier.createObject(daemon, {
            command: ["notify-send", "--app-name=GitHub", "--icon=" + pluginPath + "/notification-icon.svg", "--action=open=Open", "--", summary, Logic.escapeHtml(body)],
            thread: thread
        });
    }

    // The widget on the focused screen opens the thread (or the inbox, for a
    // summary) in its popout.
    function openThread(thread) {
        const widget = BarWidgetService.getWidgetOnFocusedScreen(pluginId);
        if (widget && typeof widget.openThread === "function")
            widget.openThread(thread);
    }

    // notify-send with an action waits for the click and prints its name;
    // the shell invokes the first action for a click on the body too.
    Component {
        id: notifier

        Process {
            id: notification

            property var thread: null

            running: true
            stdout: StdioCollector {
                onStreamFinished: {
                    if (text.trim() === "open")
                        daemon.openThread(notification.thread);
                }
            }
            onExited: Qt.callLater(() => notification.destroy())

            property Timer giveUp: Timer {
                interval: daemon.clickWaitMs
                running: true
                onTriggered: notification.running = false
            }
        }
    }

    // -------------------------------------------------------------- windows
    //
    // Every pop-out is a window of its own, independent of the popouts and
    // of each other, and of the bar it came from: each stays until it is
    // closed. They are DMS windows (app id com.danklinux.dms, which opens
    // floating), titled after what they show. windows: [{ id, state }], the
    // page each one starts on.
    property var windows: []
    property int nextWindowId: 1
    readonly property var windowIds: windows.map(entry => entry.id)

    function openWindow(state) {
        windows = windows.concat([
            {
                "id": nextWindowId++,
                "state": state
            }
        ]);
    }

    // The window asking to close is still handling its signal, so it goes
    // away on the next turn of the event loop.
    function closeWindow(id, win) {
        if (win) {
            saveState("windowWidth", win.width);
            saveState("windowHeight", win.height);
        }
        Qt.callLater(() => {
            windows = windows.filter(entry => entry.id !== id);
        });
    }

    function windowState(id) {
        const entry = windows.find(other => other.id === id);
        return entry ? entry.state : null;
    }

    Variants {
        model: daemon.windowIds

        DankFloatingWindow {
            id: githubWindow

            required property var modelData

            title: windowPanel.windowTitle
            visible: true
            minimumSize: Qt.size(400, 360)
            implicitWidth: daemon.stateNumber("windowWidth") || daemon.popoutWidth
            implicitHeight: daemon.stateNumber("windowHeight") || daemon.popoutHeight + Theme.spacingL * 2

            onClosed: daemon.closeWindow(modelData, githubWindow)

            GitHubPanel {
                id: windowPanel
                anchors.fill: parent
                anchors.margins: Theme.spacingM
                github: githubData
                windowed: true
                hostWindow: githubWindow
                recentRepos: daemon.recentRepos
                onRepoOpened: repo => daemon.rememberRepo(repo)
                onCloseRequested: daemon.closeWindow(githubWindow.modelData, githubWindow)
                Component.onCompleted: restore(daemon.windowState(githubWindow.modelData))
            }

            FloatingWindowControls {
                targetWindow: githubWindow
            }
        }
    }

    // ------------------------------------------------------------- settings

    // The plugin's own section of the DMS settings: the Plugins page with
    // GitHub expanded. The settings window loads on first use; the section
    // is asked for once it is there (the page itself waits for its tab).
    property bool settingsWanted: false

    function openSettings() {
        if (!popoutService)
            return;
        popoutService.openSettingsWithTab("plugins");
        settingsWanted = true;
        showPluginSettings();
    }

    function showPluginSettings() {
        const modal = popoutService ? popoutService.settingsModal : null;
        if (!settingsWanted || !modal || typeof modal.openPluginSettings !== "function")
            return;
        settingsWanted = false;
        modal.openPluginSettings(pluginId);
    }

    Connections {
        target: daemon.popoutService
        function onSettingsModalChanged() {
            daemon.showPluginSettings();
        }
    }
}
