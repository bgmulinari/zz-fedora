import QtQuick
import qs.Common

QtObject {
    readonly property string commandId: "protonManager.check." + Math.random().toString(36).slice(2)
    Component.onDestruction: Proc.release(commandId)
    function check(done) {
        Proc.runCommand(commandId, ["/usr/bin/python3", "-c", "import tarfile; assert hasattr(tarfile, 'data_filter')"], (stdout, exitCode) => {
            done(exitCode === 0 ? null : {title: "Python 3 with safe archive extraction is required", details: "Install the system python3 package, then enable Proton Manager again."});
        });
    }
}
