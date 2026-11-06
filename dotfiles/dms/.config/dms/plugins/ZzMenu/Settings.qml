import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

PluginSettings {
    pluginId: "zzMenu"

    StyledText {
        width: parent.width
        text: "Type the trigger in the launcher to list every zz command; keep typing to search them. Add or override rows in ~/.config/zz-fedora/menu.json."
        font.pixelSize: Theme.fontSizeSmall
        color: Theme.surfaceVariantText
        wrapMode: Text.WordWrap
    }

    StringSetting {
        settingKey: "trigger"
        label: "Trigger"
        description: "Prefix that searches the ZZ menu rows from the app launcher; the bar button and Super+Z open the menu itself"
        placeholder: "zz"
        defaultValue: "zz"
    }

    ToggleSetting {
        settingKey: "noTrigger"
        label: "Always visible"
        description: "List the zz commands alongside applications without a trigger"
        defaultValue: false
    }
}
