import QtQuick
import Quickshell
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import "GitHubLogic.js" as Logic

// The bar surface, one per bar: the GitHub mark, with a dot while
// notifications are unread (as on the DMS notification bell) and the
// number of pull requests waiting for your review beside it, a popout
// (GitHubPanel) that lists notifications, pull requests, issues, and
// Actions runs and acts on them through gh, and a right-click menu. The
// data, the polls, and the windows belong to the plugin's daemon
// (GitHubDaemon), shared by every bar.
// `dms ipc call widget openWith github <inbox|issues|prs|actions>` opens the
// popout at a tab; `widget toggle github` is the click. The popout resizes
// from its free edges; its size is plugin state (github_state.json), not
// settings.
PluginComponent {
    id: root

    layerNamespacePlugin: "github"

    // The daemon spawns a moment after the plugin loads.
    readonly property var hub: pluginService && pluginId ? (pluginService.pluginDaemonInstances[pluginId] || null) : null
    readonly property var github: hub ? hub.github : null

    readonly property string barCount: String(pluginData.barCount || "reviews")
    readonly property bool unreadDot: pluginData.notificationDot !== false
    readonly property int resumeSeconds: pluginData.resumeSeconds === undefined ? 300 : Number(pluginData.resumeSeconds)

    // The tab the next open starts at; "" keeps the one last shown.
    property string initialTab: ""
    // The popout host keeps its panel loaded between opens, so "open" means
    // the popout is showing, not that the panel exists.
    property var panelItem: null
    readonly property bool popoutShowing: panelItem !== null && !!panelItem.parentPopout && panelItem.parentPopout.shouldBeVisible
    // A thread to open once the popout is up (a desktop notification's
    // click).
    property var pendingThread: null

    // ---------------------------------------------------------------- sizes
    // The size a drag is making, before it is saved; 0 when none is.
    property real dragWidth: 0
    property real dragHeight: 0
    readonly property real panelWidth: dragWidth || (hub ? hub.popoutWidth : 480)
    readonly property real panelHeight: dragHeight || (hub ? hub.popoutHeight : 640)

    function savePopoutSize(width, height) {
        if (hub) {
            hub.saveState("popoutWidth", width);
            hub.saveState("popoutHeight", height);
        }
        dragWidth = 0;
        dragHeight = 0;
    }

    function resetPopoutSize() {
        if (hub) {
            hub.saveState("popoutWidth", 0);
            hub.saveState("popoutHeight", 0);
        }
    }

    // ---------------------------------------------------------------- badge

    readonly property int badgeCount: {
        const g = github;
        if (!g || g.authState !== "ok" || barCount === "off")
            return 0;
        if (barCount === "notifications")
            return g.unreadNotifications.length;
        let count = g.total("prReview");
        // Assigned pull requests that also ask for a review count once.
        if (barCount === "reviewsAndAssigned")
            count += g.total("issueAssigned") + Number(g.counted.prAssignedOnly || 0);
        return count;
    }
    readonly property string badgeText: github ? github.countText(badgeCount, barCount === "notifications" ? "inbox" : "") : ""
    // The dot says "unread", which a count of notifications already says.
    readonly property bool showDot: unreadDot && barCount !== "notifications" && !!github && github.authState === "ok" && github.unreadNotifications.length > 0
    readonly property color markColor: !github || github.authState === "signedOut" || github.authState === "error" ? Theme.widgetInactiveIconColor : Theme.widgetIconColor

    // ------------------------------------------------------------- opening

    function openWithMode(mode) {
        const tab = Logic.TABS.some(t => t.id === String(mode)) ? String(mode) : "";
        if (popoutShowing) {
            if (tab !== "")
                panelItem.showTab(tab);
            return;
        }
        initialTab = tab;
        triggerPopout();
    }

    function toggleWithMode(mode) {
        if (popoutShowing)
            closePopout();
        else
            openWithMode(mode);
    }

    // Opens the popout on a thread, or on the inbox for a summary (the
    // daemon calls this for a desktop notification's click).
    function openThread(thread) {
        if (popoutShowing) {
            panelItem.showInbox();
            if (thread)
                panelItem.activate(thread);
            return;
        }
        pendingThread = thread;
        openWithMode("inbox");
    }

    function openWindow(state) {
        closePopout();
        if (hub)
            hub.openWindow(state);
    }

    // Right click: the menu, next to the mark on whichever bar edge it is.
    pillRightClickAction: (x, y, width, section, screen) => {
        const vertical = root.axis ? root.axis.isVertical : false;
        const edge = root.axis ? root.axis.edge : "top";
        menu.entries = root.menuEntries();
        if (vertical)
            menu.showAt(x, y + width / 2, true, edge, screen);
        else
            menu.showAt(x + width / 2, y, false, edge, screen);
    }

    GitHubMenu {
        id: menu
    }

    // The tabs with the counts they show, a window, refresh, github.com,
    // and the plugin's settings.
    function menuEntries() {
        const g = github;
        const signedIn = !!g && g.authState === "ok";
        const entries = [];
        if (signedIn) {
            for (const tab of Logic.TABS) {
                const count = g.tabCount("", tab.id);
                entries.push({
                    "icon": tab.icon,
                    "label": tab.label,
                    "detail": g.countText(count, tab.id),
                    "action": () => root.openWithMode(tab.id)
                });
            }
            entries.push({
                "separator": true
            }, {
                "icon": "pip_exit",
                "label": "Open in a window",
                "action": () => root.openWindow({
                        "tab": "inbox"
                    })
            });
        }
        entries.push({
            "icon": "refresh",
            "label": "Refresh",
            "action": () => root.github && root.github.refreshInbox({
                        "reset": true
                    })
        }, {
            "icon": "open_in_new",
            "label": "Open github.com",
            "action": () => Qt.openUrlExternally(signedIn ? "https://github.com/notifications" : "https://github.com")
        }, {
            "separator": true
        }, {
            "icon": "settings",
            "label": "Settings",
            "action": () => {
                root.closePopout();
                if (root.hub)
                    root.hub.openSettings();
            }
        });
        return entries;
    }

    popoutWidth: panelWidth

    // The popout waits for the daemon (it spawns a moment after the plugin
    // loads), so the panel always has its data; a click before does
    // nothing.
    popoutContent: github ? panelComponent : null

    Component {
        id: panelComponent

        GitHubPanel {
            implicitHeight: root.panelHeight
            github: root.github
            initialTab: root.initialTab
            resumeSeconds: root.resumeSeconds
            startScope: root.hub.popoutScope
            recentRepos: root.hub.recentRepos
            onRepoOpened: repo => root.hub.rememberRepo(repo)
            onScopeChosen: scope => root.hub.saveState("scope", scope)
            onOpened: {
                root.initialTab = "";
                if (root.pendingThread) {
                    activate(root.pendingThread);
                    root.pendingThread = null;
                }
            }
            onPopOutRequested: state => root.openWindow(state)
            onResizing: (width, height) => {
                root.dragWidth = width;
                root.dragHeight = height;
            }
            onResized: (width, height) => root.savePopoutSize(width, height)
            onResizeReset: root.resetPopoutSize()
            Component.onCompleted: root.panelItem = this
            Component.onDestruction: {
                if (root.panelItem === this)
                    root.panelItem = null;
            }
        }
    }

    // The DMS notification bell's unread dot, on the mark's corner.
    component UnreadDot: Rectangle {
        width: 6
        height: 6
        radius: 3
        color: Theme.error
        anchors.right: parent.right
        anchors.top: parent.top
        visible: root.showDot
    }

    // Bare content, not a boxed pill: BasePill already draws the background
    // and padding the bar settings ask for.
    // The mark and the count beside it on a horizontal bar, under it on a
    // vertical one.
    component PillBody: Grid {
        property bool vertical: false
        columns: vertical ? 1 : 2
        columnSpacing: Theme.spacingXS
        rowSpacing: 1
        horizontalItemAlignment: Grid.AlignHCenter
        verticalItemAlignment: Grid.AlignVCenter

        GitHubMark {
            size: root.iconSize
            color: root.markColor

            UnreadDot {}
        }

        StyledText {
            visible: root.badgeCount > 0
            text: root.badgeText
            font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
            color: Theme.widgetTextColor
        }
    }

    horizontalBarPill: Component {
        PillBody {}
    }

    verticalBarPill: Component {
        PillBody {
            vertical: true
        }
    }
}
