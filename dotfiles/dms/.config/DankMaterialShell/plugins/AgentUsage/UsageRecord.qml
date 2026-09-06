import QtQuick
import Quickshell.Io

// One agent's usage record, read straight off the JSON file that
// scripts/update-usage maintains. The widget never learns how the numbers
// were made: a record that appears in the usage directory is an agent,
// whoever wrote it.
Item {
    id: root
    visible: false

    property string agentId: ""
    property string path: ""
    property var record: null

    FileView {
        path: root.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.parse(text())
        onLoadFailed: root.record = null
    }

    function parse(content) {
        try {
            const parsed = JSON.parse(String(content || ""));
            root.record = parsed && typeof parsed === "object" ? parsed : null;
        } catch (e) {
            console.warn("agentUsage", "Ignoring bad usage record", root.path, e);
            root.record = null;
        }
    }
}
