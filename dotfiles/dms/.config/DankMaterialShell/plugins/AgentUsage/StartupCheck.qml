import QtQuick
import qs.Common

// The collectors are Python scripts with a fixed /usr/bin/python3 shebang,
// so the distribution interpreter is the one dependency worth gating on.
QtObject {
    function check(done) {
        Proc.runCommand("agentUsage.startupCheck", ["sh", "-c", "test -x /usr/bin/python3"], (stdout, exitCode) => {
            if (exitCode === 0) {
                done(null);
                return;
            }
            done({
                "title": "python3 is required",
                "details": "The usage collectors run with /usr/bin/python3. Install the python3 package and re-enable this plugin."
            });
        });
    }
}
