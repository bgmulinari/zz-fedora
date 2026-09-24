import QtQuick
import Quickshell
import qs.Services
import "scenario.js" as Scenario

// Runs one scenario against the GitHub plugin's data layer (GitHubData, copied
// beside this file) with gh scripted: scenario.js is harness.js followed by
// the test's run(data, toasts), toasts being the toasts raised so far. What
// run returns prints as "RESULT <json>", and the shell quits.
ShellRoot {
    GitHubData {
        id: data
        pluginDir: "/plugin"
    }

    Component.onCompleted: {
        let result;
        try {
            result = Scenario.run(data, ToastService.shown);
        } catch (e) {
            result = {
                "error": String(e),
                "stack": String(e.stack || "")
            };
        }
        console.warn("RESULT " + JSON.stringify(result));
        // Quickshell listens for quit only once the root is complete.
        Qt.callLater(Qt.quit);
    }
}
