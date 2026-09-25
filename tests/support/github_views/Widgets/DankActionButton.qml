import QtQuick

// The shell's icon button: its properties, and a click to send.
Item {
    property real buttonSize: 32
    property string iconName: ""
    property real iconSize: 16
    property color iconColor: "white"
    property string tooltipText: ""

    signal clicked()

    width: buttonSize
    height: buttonSize
}
