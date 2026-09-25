import QtQuick
import Quickshell
import "scenario.js" as Scenario

// Runs one scenario against the GitHub plugin's views (copied beside this
// file) with the shell's theme and widgets stood in for (Common, Widgets):
// scenario.js is the test's run(root), root an item to make views in. What
// run returns prints as "RESULT <json>", and the shell quits.
ShellRoot {
    Item {
        id: root
    }

    Component.onCompleted: {
        let result;
        try {
            result = Scenario.run(root);
        } catch (e) {
            result = {
                "error": String(e),
                "stack": String(e.stack || "")
            };
        }
        console.warn("RESULT " + JSON.stringify(result));
        Qt.callLater(Qt.quit);
    }
}
