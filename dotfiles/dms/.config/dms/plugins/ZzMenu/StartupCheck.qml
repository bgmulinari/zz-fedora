import QtQuick
import qs.Common

// The inventory script runs with /usr/bin/python3 and every row opens a
// terminal, so both must exist before the menu can do anything useful.
QtObject {
    function check(done) {
        const probe = "test -x /usr/bin/python3 || exit 10; "
            + "command -v xdg-terminal-exec >/dev/null 2>&1 || command -v ghostty >/dev/null 2>&1 || exit 11";
        Proc.runCommand("zzMenu.startupCheck", ["sh", "-c", probe], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null);
                return;
            }
            if (exitCode === 10) {
                done({
                    "title": "python3 is required",
                    "details": "The ZZ menu resolves its rows with /usr/bin/python3. Install the python3 package and re-enable this plugin."
                });
                return;
            }
            done({
                "title": "A terminal is required",
                "details": "ZZ menu rows run in a terminal window. Install xdg-terminal-exec or ghostty and re-enable this plugin."
            });
        });
    }
}
