import QtQuick
import qs.Common
import qs.Widgets
import "GitHubLogic.js" as Logic

// The picker under the header's scope button: the lists involving the
// viewer, or everything in one repository. It offers the repositories
// opened lately, the viewer's own (the Actions ones from the settings and
// the ones pushed to last), and, as a name is typed, GitHub's repositories
// by that name; an owner/name typed in full opens as it is.
GitHubPicker {
    id: menu

    property var github: null
    // The scope on screen: "" or "owner/name".
    property string scope: ""
    property var recentRepos: []

    signal picked(string repo)

    placeholder: "Search, or type owner/name"
    emptyText: "No repository matches. Type owner/name to open one."
    selectable: entry => entry.kind !== "header"
    entries: computeEntries()
    // GitHub's repositories by the typed name, from two letters on.
    search: (words, done) => {
        if (words.length < 2 || !github)
            done([]);
        else
            github.searchRepos(words, repos => done(repos || []), menu);
    }

    function showAt(anchor) {
        show(anchor);
        const current = entries.findIndex(entry => entry.kind !== "header" && (entry.repo || "") === scope);
        if (current >= 0)
            select(current);
    }

    function computeEntries() {
        const words = text.trim();
        const lower = words.toLowerCase();
        const out = [];
        const seen = {};
        const g = github;
        const found = foundFor === words && menu.found ? menu.found : [];
        if (words === "")
            out.push({
                "kind": "me",
                "repo": "",
                "label": "Involving you",
                "icon": "person"
            });
        // A full owner/name opens as typed, even when no list has it.
        if (g && Logic.isRepo(words) && !(g.pushedRepos.concat(g.watchedRepos, recentRepos, found).some(repo => repo.toLowerCase() === lower))) {
            out.push({
                "kind": "repo",
                "repo": words,
                "label": words,
                "icon": "book",
                "detail": "Open"
            });
            seen[lower] = true;
        }
        const section = (title, repos, filtered, busy) => {
            const items = [];
            for (const repo of repos) {
                const name = repo.toLowerCase();
                if (!seen[name] && (!filtered || lower === "" || name.indexOf(lower) >= 0)) {
                    seen[name] = true;
                    items.push(repo);
                }
            }
            if (items.length === 0 && !busy)
                return;
            out.push({
                "kind": "header",
                "label": title,
                "busy": !!busy
            });
            for (const repo of items)
                out.push({
                    "kind": "repo",
                    "repo": repo,
                    "label": repo,
                    "icon": "book"
                });
        };
        section("Recent", recentRepos, true, false);
        if (g)
            section("Your repositories", g.watchedRepos.concat(g.pushedRepos), true, false);
        if (words.length >= 2)
            section("On GitHub", found, false, searching);
        return out;
    }

    onChosen: entry => {
        close();
        picked(entry.repo);
    }

    rowDelegate: GitHubPickerRow {
        id: entry

        readonly property bool header: modelData.kind === "header"
        readonly property bool current: !header && (modelData.repo || "") === menu.scope

        picker: menu
        height: header ? 26 : 32

        Row {
            visible: entry.header
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingS
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 4
            spacing: Theme.spacingXS

            StyledText {
                text: entry.modelData.label || ""
                font.pixelSize: Theme.fontSizeSmall - 1
                font.weight: Font.DemiBold
                color: Theme.surfaceVariantText
            }

            DankSpinner {
                visible: !!entry.modelData.busy
                anchors.verticalCenter: parent.verticalCenter
                size: 12
            }
        }

        Item {
            visible: !entry.header
            anchors.fill: parent

            DankIcon {
                id: icon
                anchors.left: parent.left
                anchors.leftMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                name: entry.modelData.icon || ""
                size: 16
                color: entry.current ? Theme.primary : Theme.surfaceVariantText
            }

            StyledText {
                anchors.left: icon.right
                anchors.leftMargin: Theme.spacingS
                anchors.right: trail.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: entry.modelData.label || ""
                textFormat: Text.PlainText
                wrapMode: Text.NoWrap
                maximumLineCount: 1
                font.pixelSize: Theme.fontSizeSmall
                font.weight: entry.current ? Font.DemiBold : Font.Normal
                color: entry.current ? Theme.primary : Theme.surfaceText
                elide: Text.ElideMiddle
            }

            Item {
                id: trail
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(check.visible ? check.width : 0, detail.visible ? detail.implicitWidth : 0)
                height: 16

                DankIcon {
                    id: check
                    visible: entry.current
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    name: "check"
                    size: 16
                    color: Theme.primary
                }

                StyledText {
                    id: detail
                    visible: !entry.current && !!entry.modelData.detail
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: entry.modelData.detail || ""
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }
        }
    }
}
