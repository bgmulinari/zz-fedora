import QtQuick
import qs.Common

// The rows come from a /usr/bin/python3 script, the search is fzf, and a
// picked row runs through `niri msg action`, so all three must exist
// before the list can do anything useful.
QtObject {
    function check(done) {
        const probe = "test -x /usr/bin/python3 || exit 10; command -v niri >/dev/null 2>&1 || exit 11; "
            + "command -v fzf >/dev/null 2>&1 || exit 12";
        Proc.runCommand("zzKeybindings.startupCheck", ["sh", "-c", probe], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null);
                return;
            }
            if (exitCode === 10) {
                done({
                    "title": "python3 is required",
                    "details": "The keyboard shortcut list is built with /usr/bin/python3. Install the python3 package and re-enable this plugin."
                });
                return;
            }
            if (exitCode === 12) {
                done({
                    "title": "fzf is required",
                    "details": "The keyboard shortcut search runs through fzf. Install the fzf package and re-enable this plugin."
                });
                return;
            }
            done({
                "title": "Niri is required",
                "details": "The keyboard shortcut list reads and runs Niri binds. It only works in a Niri session."
            });
        });
    }
}
