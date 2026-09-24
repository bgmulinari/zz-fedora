pragma Singleton
import QtQuick
import Quickshell

// The shell's process helper, as far as the data layer uses it.
Singleton {
    readonly property string dmsBin: "true"
}
