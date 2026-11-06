import QtQuick
import qs.Common

// A grouped block on a page: the jobs of a run, the checks and reviews of
// a pull request, an issue's relationships.
Rectangle {
    default property alias content: cardColumn.data

    width: parent ? parent.width : 0
    implicitHeight: cardColumn.implicitHeight + Theme.spacingS * 2
    radius: Theme.cornerRadius
    color: Theme.withAlpha(Theme.surfaceText, 0.04)
    border.width: 1
    border.color: Theme.withAlpha(Theme.outlineVariant, 0.35)

    Column {
        id: cardColumn
        x: Theme.spacingXS
        y: Theme.spacingS
        width: parent.width - Theme.spacingXS * 2
        spacing: 0
    }
}
