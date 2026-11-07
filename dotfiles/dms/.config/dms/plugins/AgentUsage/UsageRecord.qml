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

    // The text the current record was parsed from, so a reload that finds the
    // file unchanged does not hand every listener an identical new record.
    property string parsedText: ""

    FileView {
        id: agentFile
        path: root.path
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.parse(text())
        onLoadFailed: root.clear()
    }

    // The update rewrites records with an atomic replace, which swaps the
    // inode. Should inotify fail to rearm on the new one (watch quota, ENOSPC),
    // the FileView goes quiet, so UsageModel also reloads every record after
    // each update run.
    function reload() {
        agentFile.reload();
    }

    function clear() {
        root.parsedText = "";
        root.record = null;
    }

    function parse(content) {
        const text = String(content || "");
        if (root.record && text === root.parsedText)
            return;
        try {
            const parsed = JSON.parse(text);
            root.record = parsed && typeof parsed === "object" ? parsed : null;
            root.parsedText = root.record ? text : "";
        } catch (e) {
            console.warn("agentUsage", "Ignoring bad usage record", root.path, e);
            root.clear();
        }
    }
}
