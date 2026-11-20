import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins
import qs.DCommon.Widgets
import "GitHubLogic.js" as Logic

PluginSettings {
    pluginId: "github"

    StyledText {
        width: parent.width
        text: "The widget reads and changes GitHub only through the GitHub CLI. Sign in with gh auth login; the popout shows the account gh uses under its title."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    SelectionSetting {
        settingKey: "barCount"
        label: "Count in the bar"
        description: "What the number beside the GitHub mark counts"
        options: [
            {
                "label": "Review requests",
                "value": "reviews"
            },
            {
                "label": "Review requests and assignments",
                "value": "reviewsAndAssigned"
            },
            {
                "label": "Unread notifications",
                "value": "notifications"
            },
            {
                "label": "Nothing",
                "value": "off"
            }
        ]
        defaultValue: "reviews"
    }

    ToggleSetting {
        settingKey: "notificationDot"
        label: "Unread dot"
        description: "A dot on the GitHub mark while notifications are unread, like the one on the notification bell"
        defaultValue: true
    }

    SelectionSetting {
        settingKey: "desktopNotifications"
        label: "Desktop notifications"
        description: "Which new GitHub notifications also appear as desktop notifications; clicking one opens it here"
        options: [
            {
                "label": "Assignments, review requests, and mentions",
                "value": "direct"
            },
            {
                "label": "Every new notification",
                "value": "all"
            },
            {
                "label": "None",
                "value": "off"
            }
        ]
        defaultValue: "direct"
    }

    // An automation is picked, not typed: why the notification came, what
    // it is about, optionally where, and the command to run.
    ListSetting {
        id: automations

        settingKey: "automations"
        label: "Automations"
        description: "Run a command of yours when a new notification comes in: pick why it came and what it is about, optionally a repository (owner/name, or an owner for all of theirs), and the command. It runs once per new notification, in your home directory, with the notification in GITHUB_NOTIFICATION_* variables (REASON, TYPE, REPO, NUMBER, TITLE, URL, ID); the plugin's README lists them."
        defaultValue: []

        property string reason: "review_requested"
        property string type: "PullRequest"

        function add() {
            const command = commandField.text.trim();
            const repo = repoField.text.trim();
            if (command === "" || !Logic.automationRepoValid(repo))
                return;
            addItem({
                "reason": reason,
                "type": type,
                "repo": repo,
                "command": command
            });
            repoField.text = "";
            commandField.text = "";
        }

        inputs: [
            Flow {
                width: parent.width
                spacing: Theme.spacingS

                Column {
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "When"
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.fontWeightMedium
                        color: Theme.surfaceText
                    }

                    DDropdown {
                        dropdownWidth: 200
                        options: Logic.AUTOMATION_REASONS.map(choice => choice[1])
                        optionValues: Logic.AUTOMATION_REASONS.map(choice => choice[0])
                        currentValue: automations.reason
                        onValueChanged: value => automations.reason = value
                    }
                }

                Column {
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "On"
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.fontWeightMedium
                        color: Theme.surfaceText
                    }

                    DDropdown {
                        dropdownWidth: 160
                        options: Logic.AUTOMATION_TYPES.map(choice => choice[1])
                        optionValues: Logic.AUTOMATION_TYPES.map(choice => choice[0])
                        currentValue: automations.type
                        onValueChanged: value => automations.type = value
                    }
                }

                Column {
                    spacing: Theme.spacingXS

                    StyledText {
                        text: "In repository"
                        font.pixelSize: Theme.fontSizeSmall
                        font.weight: Theme.fontWeightMedium
                        color: Theme.surfaceText
                    }

                    DTextField {
                        id: repoField
                        width: 180
                        placeholderText: "Any (or owner/name)"
                        isError: !Logic.automationRepoValid(text)
                        Keys.onReturnPressed: automations.add()
                    }
                }
            },
            Column {
                width: parent.width
                spacing: Theme.spacingXS

                StyledText {
                    text: "Run"
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Theme.fontWeightMedium
                    color: Theme.surfaceText
                }

                Row {
                    width: parent.width
                    spacing: Theme.spacingS

                    DTextField {
                        id: commandField
                        width: parent.width - addButton.width - parent.spacing
                        placeholderText: "~/bin/on-review-requested.sh"
                        Keys.onReturnPressed: automations.add()
                    }

                    DButton {
                        id: addButton
                        anchors.verticalCenter: commandField.verticalCenter
                        width: 50
                        height: 36
                        text: "Add"
                        enabled: commandField.text.trim() !== "" && !repoField.isError
                        onClicked: automations.add()
                    }
                }
            }
        ]

        delegate: Component {
            StyledRect {
                id: automationRow

                required property int index
                required property var modelData

                width: parent.width
                height: 52
                radius: Theme.cornerRadius
                color: Theme.chipSurface
                border.width: 0

                Column {
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingM
                    anchors.right: removeButton.left
                    anchors.rightMargin: Theme.spacingM
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    StyledText {
                        width: parent.width
                        text: Logic.automationSummary(automationRow.modelData || {})
                        color: Theme.surfaceText
                        font.pixelSize: Theme.fontSizeMedium
                        elide: Text.ElideRight
                    }

                    StyledText {
                        width: parent.width
                        text: String((automationRow.modelData && automationRow.modelData.command) || "")
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        font.family: Theme.monoFontFamily
                        elide: Text.ElideMiddle
                    }
                }

                ListSettingRemoveButton {
                    id: removeButton
                    onClicked: automations.removeItem(automationRow.index)
                }
            }
        }
    }

    SliderSetting {
        settingKey: "refreshIntervalSec"
        label: "Refresh interval"
        description: "How often pull requests and issues are fetched in the background; opening the popout fetches them too unless they are under 20 seconds old. Even the lowest setting uses a small part of GitHub's hourly limit. Notifications are checked every minute regardless: free while nothing changed, with a full check every ten minutes."
        defaultValue: 300
        minimum: 60
        maximum: 1800
        unit: "s"
    }

    SliderSetting {
        settingKey: "resumeSeconds"
        label: "Keep my place"
        description: "Opening the popout from the bar within this long of dismissing it shows what it showed, the issue or pull request included; after that it starts over at the list. 0 always starts over."
        defaultValue: 300
        minimum: 0
        maximum: 1800
        unit: "s"
    }

    ListSettingWithInput {
        settingKey: "repositories"
        label: "Actions repositories"
        description: "Repositories whose workflow runs the Actions tab lists. Leave empty to follow the five most recently pushed repositories you own or work in."
        defaultValue: []
        fields: [
            {
                "id": "repo",
                "label": "Repository",
                "placeholder": "owner/name",
                "width": 280,
                "required": true
            }
        ]
    }
}
