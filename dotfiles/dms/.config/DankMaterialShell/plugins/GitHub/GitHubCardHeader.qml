import QtQuick
import qs.Common
import qs.Widgets

// A card's heading line: a status glyph (an icon in iconColor, or an
// outcome or a glyph in its own color), a title, and a note on the right.
Item {
    id: cardHeader

    property string icon: ""
    property color iconColor: Theme.surfaceVariantText
    property string outcome: ""
    property var glyph: null
    property string title: ""
    property string note: ""

    width: parent ? parent.width : 0
    height: 32

    GitHubStatusIcon {
        id: headerIcon
        anchors.left: parent.left
        anchors.leftMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        outcome: cardHeader.outcome
        glyph: cardHeader.glyph
        icon: cardHeader.icon
        size: Theme.iconSizeSmall + 2
        color: shown ? toneColor : cardHeader.iconColor
    }

    StyledText {
        id: headerTitle
        anchors.left: headerIcon.right
        anchors.leftMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        text: cardHeader.title
        textFormat: Text.PlainText
        font.pixelSize: Theme.fontSizeMedium
        font.weight: Font.DemiBold
        color: Theme.surfaceText
    }

    StyledText {
        anchors.left: headerTitle.right
        anchors.leftMargin: Theme.spacingS
        anchors.right: parent.right
        anchors.rightMargin: Theme.spacingS
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        text: cardHeader.note
        textFormat: Text.PlainText
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        elide: Text.ElideRight
    }
}
