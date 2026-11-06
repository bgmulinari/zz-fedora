import QtQuick
import qs.Common
import qs.Widgets

// A page's state as a pill in its color (Open, Draft, Merged, Closed, a
// run's outcome), from the page (GitHubDetail).
Rectangle {
    id: badge

    property var page: null

    height: 20
    width: badgeRow.implicitWidth + Theme.spacingS + Theme.spacingXS
    radius: height / 2
    color: Theme.withAlpha(glyph.color, 0.16)

    Row {
        id: badgeRow
        anchors.centerIn: parent
        spacing: 3

        GitHubStatusIcon {
            id: glyph
            anchors.verticalCenter: parent.verticalCenter
            item: badge.page ? badge.page.current : null
            itemState: badge.page ? badge.page.itemState : ""
            size: Theme.iconSizeSmall - 2
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            text: badge.page ? badge.page.stateText : ""
            font.pixelSize: Theme.fontSizeSmall - 1
            font.weight: Font.DemiBold
            color: glyph.color
        }
    }
}
