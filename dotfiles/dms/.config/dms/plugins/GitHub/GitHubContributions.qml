import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "GitHubLogic.js" as Logic

// A person's contributions over the last year as github.com's calendar
// draws them: a column a week, a square a day in the shade of its
// quartile (the shell's success color), the months over the columns and
// Mon, Wed, Fri beside the rows. Resting the pointer on a day says how
// many it had where the legend is.
Column {
    id: calendar

    // Logic.ownerOf's contributions: { total, weeks: [[{ date, count, level }]] }.
    property var contributions: null
    readonly property var weeks: contributions ? contributions.weeks : []
    readonly property real gap: 2
    readonly property real labelWidth: 26
    readonly property real cell: Math.max(5, Math.min(14, Math.floor((width - labelWidth - gap * (Math.max(1, weeks.length) - 1)) / Math.max(1, weeks.length))))
    property var hovered: null

    width: parent ? parent.width : 0
    spacing: Theme.spacingS

    function shade(level) {
        return level <= 0 ? Theme.withAlpha(Theme.surfaceText, 0.08) : Theme.withAlpha(Theme.success, [0, 0.35, 0.55, 0.78, 1][Math.min(4, level)]);
    }

    StyledText {
        text: calendar.contributions ? Logic.plural(calendar.contributions.total, "contribution") + " in the last year" : ""
        font.pixelSize: Theme.fontSizeMedium
        color: Theme.surfaceText
    }

    Rectangle {
        width: parent.width
        height: grid.height + Theme.spacingM * 2
        radius: Theme.cornerRadius
        color: "transparent"
        border.width: 1
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.45)

        Column {
            id: grid
            x: Math.max(Theme.spacingS, Math.round((parent.width - calendar.labelWidth - calendar.weeks.length * (calendar.cell + calendar.gap)) / 2))
            y: Theme.spacingM
            spacing: calendar.gap + 2

            Item {
                width: calendar.labelWidth + calendar.weeks.length * (calendar.cell + calendar.gap)
                height: Theme.fontSizeSmall

                Repeater {
                    model: Logic.contributionMonths(calendar.weeks)

                    StyledText {
                        required property var modelData
                        x: calendar.labelWidth + modelData.week * (calendar.cell + calendar.gap)
                        text: modelData.label
                        font.pixelSize: Theme.fontSizeSmall - 2
                        color: Theme.surfaceVariantText
                    }
                }
            }

            Row {
                spacing: 0

                Item {
                    width: calendar.labelWidth
                    height: 7 * (calendar.cell + calendar.gap)

                    Repeater {
                        model: [[1, "Mon"], [3, "Wed"], [5, "Fri"]]

                        StyledText {
                            required property var modelData
                            y: modelData[0] * (calendar.cell + calendar.gap) + (calendar.cell - implicitHeight) / 2
                            text: modelData[1]
                            font.pixelSize: Theme.fontSizeSmall - 2
                            color: Theme.surfaceVariantText
                        }
                    }
                }

                Repeater {
                    model: calendar.weeks

                    Item {
                        id: week
                        required property var modelData
                        width: calendar.cell + calendar.gap
                        height: 7 * (calendar.cell + calendar.gap)

                        Repeater {
                            model: week.modelData

                            Rectangle {
                                required property var modelData
                                // The weekday it fell on: the first week can
                                // start after Sunday.
                                y: new Date(modelData.date + "T00:00:00Z").getUTCDay() * (calendar.cell + calendar.gap)
                                width: calendar.cell
                                height: calendar.cell
                                radius: Math.max(1, calendar.cell / 5)
                                color: calendar.shade(modelData.level)
                                border.width: calendar.hovered === modelData ? 1 : 0
                                border.color: Theme.surfaceText

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onContainsMouseChanged: {
                                        if (containsMouse)
                                            calendar.hovered = parent.modelData;
                                        else if (calendar.hovered === parent.modelData)
                                            calendar.hovered = null;
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // The day under the pointer, or the legend.
    Item {
        width: parent.width
        height: 18

        StyledText {
            visible: !!calendar.hovered
            anchors.verticalCenter: parent.verticalCenter
            text: calendar.hovered ? (calendar.hovered.count === 0 ? "No contributions" : Logic.plural(calendar.hovered.count, "contribution")) + " on " + Logic.dayLabel(calendar.hovered.date + "T12:00:00") : ""
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceText
        }

        Row {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                rightPadding: 2
                text: "Less"
                font.pixelSize: Theme.fontSizeSmall - 1
                color: Theme.surfaceVariantText
            }

            Repeater {
                model: 5

                Rectangle {
                    required property int index
                    anchors.verticalCenter: parent.verticalCenter
                    width: 10
                    height: 10
                    radius: 2
                    color: calendar.shade(index)
                }
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: 2
                text: "More"
                font.pixelSize: Theme.fontSizeSmall - 1
                color: Theme.surfaceVariantText
            }
        }
    }
}
