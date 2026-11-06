import QtQuick
import qs.Common

// A row of a GitHubPicker's list (its rowDelegate's root): highlighted
// while selected, selected under the pointer, and chosen with a click. A
// row the picker does not count as a choice (a section header) is neither.
// usable dims the pointer while a choice cannot be made.
Rectangle {
    id: pickerRow

    required property var modelData
    required property int index
    property var picker: null
    property bool usable: true
    readonly property bool choice: !!picker && picker.selectable(modelData)

    width: picker ? picker.listView.width : 0
    radius: Theme.cornerRadius
    color: choice && index === picker.selectedIndex ? Theme.withAlpha(Theme.primary, 0.16) : "transparent"

    MouseArea {
        anchors.fill: parent
        enabled: pickerRow.choice
        hoverEnabled: true
        cursorShape: pickerRow.usable ? Qt.PointingHandCursor : Qt.ArrowCursor
        onEntered: pickerRow.picker.selectedIndex = pickerRow.index
        onClicked: pickerRow.picker.choose(pickerRow.modelData)
    }
}
