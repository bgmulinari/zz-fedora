import QtQuick
import qs.Common
import "GitHubLogic.js" as Logic

// The five blocks github.com draws after a count of changes
// (Logic.diffstatBlocks): green for additions, red for deletions.
Row {
    id: diffstat

    property int additions: 0
    property int deletions: 0

    spacing: 1

    Repeater {
        model: Logic.diffstatBlocks(diffstat.additions, diffstat.deletions)

        Rectangle {
            required property string modelData
            width: 8
            height: 8
            radius: 1.5
            color: modelData === "add" ? Theme.success : (modelData === "del" ? Theme.error : Theme.withAlpha(Theme.surfaceText, 0.18))
        }
    }
}
