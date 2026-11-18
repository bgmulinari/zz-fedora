import QtQuick
import qs.Common
import qs.Widgets

// Who gave a reaction, above the chip under the pointer (below it when
// the page has no room above), as github.com's hover card lists them: the
// page's (GitHubDetail, GitHubBrowse) reactorsShown beside its
// reactorsChip. It sits on the page itself, which it keeps within.
Rectangle {
    id: reactorsCard

    property var page: null
    readonly property var shown: page ? page.reactorsShown : null
    readonly property var chip: page ? page.reactorsChip : null
    readonly property point spot: shown && Qt.isQtObject(chip) && page ? chip.mapToItem(page, 0, 0) : Qt.point(0, 0)
    readonly property int more: shown ? shown.total - shown.people.length : 0
    visible: !!shown
    width: Math.min((page ? page.width : 0) - Theme.spacingS * 2, Math.max(180, reactorsColumn.implicitWidth + Theme.spacingM * 2))
    height: reactorsColumn.implicitHeight + Theme.spacingS * 2
    x: Math.max(Theme.spacingS, Math.min((page ? page.width : 0) - width - Theme.spacingS, spot.x))
    y: spot.y - height - Theme.spacingXS >= 0 ? spot.y - height - Theme.spacingXS : spot.y + (shown && Qt.isQtObject(chip) ? chip.height : 0) + Theme.spacingXS
    radius: Theme.cornerRadius
    color: Theme.surfaceContainerHigh
    border.width: 1
    border.color: Theme.withAlpha(Theme.outlineVariant, 0.8)

    Column {
        id: reactorsColumn
        x: Theme.spacingM
        y: Theme.spacingS
        spacing: Theme.spacingS

        Repeater {
            model: reactorsCard.shown ? reactorsCard.shown.people : []

            Row {
                id: reactor
                required property var modelData
                spacing: Theme.spacingS

                GitHubAvatar {
                    anchors.verticalCenter: parent.verticalCenter
                    login: reactor.modelData.login
                    size: 24
                    hovercard: false
                }

                Column {
                    anchors.verticalCenter: parent.verticalCenter

                    StyledText {
                        text: reactor.modelData.login
                        textFormat: Text.PlainText
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Font.DemiBold
                        color: Theme.surfaceText
                    }

                    StyledText {
                        visible: text !== ""
                        text: reactor.modelData.name
                        textFormat: Text.PlainText
                        font.pixelSize: Theme.fontSizeSmall - 1
                        color: Theme.surfaceVariantText
                    }
                }
            }
        }

        StyledText {
            visible: reactorsCard.more > 0
            text: "and " + reactorsCard.more + " more reacted with " + (reactorsCard.shown ? reactorsCard.shown.emoji : "")
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }
    }
}
