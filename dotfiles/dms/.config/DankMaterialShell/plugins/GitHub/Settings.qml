import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

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

    SliderSetting {
        settingKey: "refreshIntervalSec"
        label: "Refresh interval"
        description: "How often pull requests and issues are fetched in the background; opening the popout fetches them too unless they are under 20 seconds old. Even the lowest setting uses a small part of GitHub's hourly limit. Notifications are checked every minute regardless: free while nothing changed, with a full check every ten minutes."
        defaultValue: 300
        minimum: 60
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
