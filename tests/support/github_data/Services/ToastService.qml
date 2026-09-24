pragma Singleton
import QtQuick
import Quickshell

// The shell's toasts, kept for the scenario to read (its `toasts`): each
// as [level, message, details].
Singleton {
    property var shown: []

    function showInfo(message, details) {
        shown.push(["info", message, details || ""]);
    }

    function showError(message, details) {
        shown.push(["error", message, details || ""]);
    }
}
