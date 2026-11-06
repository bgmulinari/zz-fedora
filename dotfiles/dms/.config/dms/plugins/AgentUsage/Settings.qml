import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "agentUsage"

    StyledText {
        width: parent.width
        text: "Subscriptions"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
    }

    StyledText {
        width: parent.width
        text: "An agent appears in the bar once it is enabled here and has recorded usage on this machine or a synced one."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "claudeEnabled"
        label: "Claude Code"
        description: "Session and weekly limits from the signed-in CLI, plus local transcript stats"
        defaultValue: true
    }

    ToggleSetting {
        settingKey: "codexEnabled"
        label: "Codex"
        description: "Rate limits from the Codex app server, plus local session stats"
        defaultValue: true
    }

    SliderSetting {
        settingKey: "refreshIntervalSec"
        label: "Refresh interval"
        description: "How often the usage records regenerate"
        defaultValue: 900
        minimum: 30
        maximum: 3600
        unit: "s"
    }

    StyledText {
        width: parent.width
        text: "Multi-device aggregation"
        font.pixelSize: Theme.fontSizeLarge
        font.weight: Font.Bold
        color: Theme.surfaceText
        topPadding: Theme.spacingL
    }

    StyledText {
        width: parent.width
        text: "Write this machine's usage snapshot into a folder synced between your machines and merge the snapshots found there. Rate limits stay per-account and are never merged."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    ToggleSetting {
        settingKey: "syncEnabled"
        label: "Merge synced snapshots"
        defaultValue: false
    }

    StringSetting {
        settingKey: "syncDir"
        label: "Sync folder"
        description: "A folder synced by Syncthing, Dropbox, rsync, or similar"
        placeholder: "~/Sync/agent-usage"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "syncFileName"
        label: "Snapshot file name"
        description: "Optional. Defaults to <hostname>.json; use a different name on each machine"
        placeholder: "laptop.json"
        defaultValue: ""
    }

    StringSetting {
        settingKey: "syncDeviceId"
        label: "Device id"
        description: "Optional stable device name used inside synced snapshots"
        placeholder: "laptop"
        defaultValue: ""
    }
}
