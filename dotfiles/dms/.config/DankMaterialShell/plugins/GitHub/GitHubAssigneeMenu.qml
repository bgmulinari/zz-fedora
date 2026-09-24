import QtQuick
import qs.Common
import qs.Widgets

// The assignee picker behind the pen beside "Assigned to", like
// github.com's Assignees menu: the people assigned, checked, then whoever
// else can be assigned in the repository, narrowed on GitHub as a name is
// typed. Each click assigns or unassigns at once, and the picker stays
// open for the next one.
GitHubPicker {
    id: menu

    property var github: null
    // The pull request or issue whose assignees these are.
    property var item: null
    // The logins assigned now.
    property var assigned: []
    // A change is on its way; the rows wait for it.
    property bool changing: false

    signal toggled(string login, bool on)

    // Whoever can be assigned and matches the words, as GitHub answers.
    readonly property var people: found || []

    title: "Assign up to 10 people"
    busy: searching || changing
    placeholder: "Filter people"
    emptyText: searching ? "Loading…" : "No one matches."
    maxWidth: 300
    maxHeight: 360
    searchDelay: 300
    entries: computeEntries()
    search: (words, done) => {
        if (github && item)
            github.loadAssignable(item.repo, words, done, menu);
        else
            done([]);
    }

    // The assigned first (those matching the words, while some are
    // typed), then the rest GitHub offers.
    function computeEntries() {
        const lower = text.trim().toLowerCase();
        const out = [];
        const seen = {};
        for (const login of assigned) {
            if (lower !== "" && login.toLowerCase().indexOf(lower) < 0)
                continue;
            const person = people.find(other => other.login === login);
            out.push({
                "login": login,
                "name": person ? person.name : "",
                "on": true
            });
            seen[login] = true;
        }
        for (const person of people)
            if (!seen[person.login])
                out.push({
                    "login": person.login,
                    "name": person.name,
                    "on": false
                });
        return out;
    }

    onChosen: entry => {
        if (!changing)
            toggled(entry.login, !entry.on);
    }

    rowDelegate: GitHubPickerRow {
        id: entry

        picker: menu
        usable: !menu.changing
        height: 34
        opacity: menu.changing ? 0.6 : 1

        DankIcon {
            id: box
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            name: entry.modelData.on ? "check_box" : "check_box_outline_blank"
            size: 18
            color: entry.modelData.on ? Theme.primary : Theme.surfaceVariantText
        }

        StyledText {
            id: login
            anchors.left: box.right
            anchors.leftMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            text: entry.modelData.login + (menu.github && entry.modelData.login === menu.github.login ? " (you)" : "")
            textFormat: Text.PlainText
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.DemiBold
            color: Theme.surfaceText
        }

        StyledText {
            anchors.left: login.right
            anchors.leftMargin: Theme.spacingS
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            text: entry.modelData.name
            textFormat: Text.PlainText
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            elide: Text.ElideRight
        }
    }
}
