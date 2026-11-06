import QtQuick
import qs.Common

// Everything the plugin shows or changes goes through the GitHub CLI, so
// the CLI must exist before the widget can load. notify-send (the other
// dependency) only carries the optional desktop notifications, so its
// absence does not stop the widget: the daemon checks for it and says so
// when a notification would have gone out. Being signed in is not checked
// here either: the popout explains a signed-out CLI and offers the fix.
QtObject {
    function check(done) {
        Proc.runCommand("github.startupCheck", ["sh", "-c", "command -v gh >/dev/null 2>&1"], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null);
                return;
            }
            done({
                "title": "The GitHub CLI is required",
                "details": "This widget reads and changes GitHub through gh. Install the gh package and re-enable this plugin."
            });
        });
    }
}
