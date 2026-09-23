import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Modals.Common
import qs.Modules.Plugins

// The keybinding list: a centered modal, like the launcher, listing every
// Niri bind as keycaps and a name, searchable, and running the bind a row
// stands for when it is picked. There is no bar button; the keybind opens
// it through the plugin IPC (`dms ipc call plugins toggle zzKeybindings`),
// which calls toggle() here. scripts/zz-keybindings builds the rows from
// `dms keybinds show niri` on every open, so an edited bind shows at once.
PluginComponent {
    id: root

    readonly property string ownId: pluginId || "zzKeybindings"
    readonly property string pluginPath: pluginService ? String(pluginService.getPluginPath(ownId) || "") : ""

    // Rows as the script printed them: chord, caps, label, action, command,
    // search. The last good list stays up while a reload runs, so a reopen
    // shows rows at once.
    property var rows: []
    property string error: ""
    property bool loading: lister.running

    // What a picked row runs once the modal is gone.
    property var pendingCommand: []

    function toggle() {
        if (modal.shouldBeVisible)
            modal.close();
        else
            open();
    }

    function open() {
        refresh();
        modal.open();
    }

    function close() {
        modal.close();
    }

    function refresh() {
        if (!pluginPath || lister.running)
            return;
        lister.running = true;
    }

    // Close first and run after the modal has let go of the keyboard: the
    // bind acts on the window that had focus before the list opened, and a
    // bind that opens another shell surface must not race this one closing.
    // The row for this list's own keybind only closes it.
    function run(row) {
        if (!row || !Array.isArray(row.command) || row.command.length === 0)
            return;
        modal.close();
        if (String(row.action || "").indexOf(ownId) >= 0)
            return;
        pendingCommand = row.command;
        dispatch.restart();
    }

    // Binds are edited in Settings > Keyboard Shortcuts, which writes them
    // back to ~/.config/niri/dms/binds.kdl.
    function editBinds() {
        modal.close();
        Quickshell.execDetached(["dms", "ipc", "call", "settings", "openWith", "keybinds"]);
    }

    function applyRows(text) {
        let parsed;
        try {
            parsed = JSON.parse(text);
        } catch (e) {
            error = "The keybinding list could not be read.";
            console.warn("zzKeybindings: script output is not JSON:", e);
            return;
        }
        error = parsed.error ? String(parsed.error) : "";
        if (Array.isArray(parsed.rows) && (parsed.rows.length > 0 || !parsed.error))
            rows = parsed.rows;
    }

    Timer {
        id: dispatch
        interval: Theme.modalAnimationDuration + 60
        onTriggered: {
            if (root.pendingCommand.length > 0)
                Quickshell.execDetached(root.pendingCommand);
            root.pendingCommand = [];
        }
    }

    Process {
        id: lister
        running: false
        command: [root.pluginPath + "/scripts/zz-keybindings"]

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applyRows(text)
        }
    }

    // Warm the rows once the plugin path is known, so the first open is not
    // empty. Deferred one tick: the process command binds to the same path.
    onPluginPathChanged: {
        if (pluginPath)
            Qt.callLater(refresh);
    }

    DankModal {
        id: modal
        layerNamespace: "dms:plugins:zz-keybindings"
        modalWidth: 780
        modalHeight: Math.min(720, Math.round(screenHeight * 0.8))

        content: Component {
            ZzKeybindingsPanel {
                host: root
                parentPopout: modal
            }
        }
    }
}
