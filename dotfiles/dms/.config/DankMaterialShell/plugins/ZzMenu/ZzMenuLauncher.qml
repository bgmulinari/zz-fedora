import QtQuick

// The launcher surface of the ZZ menu: the same rows the bar menu serves,
// reachable by typing the trigger in the app launcher. The menu proper is
// the bar widget's popout, which navigates groups the way a menu does;
// this surface is the search fallback, since the launcher closes after any
// plugin item runs and cannot hold a submenu open. Each row therefore
// carries its group path in the subtitle, as a search word, and as a
// category for the launcher's category picker.
Item {
    id: root

    property var pluginService: null
    property string trigger: "zz"

    readonly property string pluginId: "zzMenu"
    property string categoryId: ""

    ZzMenuInventory {
        id: menuInventory
        pluginService: root.pluginService
        onLoaded: {
            if (root.pluginService)
                root.pluginService.requestLauncherUpdate(root.pluginId);
        }
    }

    function getCategories() {
        const categories = [{ id: "", name: "All" }];
        const groups = menuInventory.groups;
        for (let i = 0; i < groups.length; i++) {
            if (!groups[i].parent)
                categories.push({ id: groups[i].id, name: groups[i].label });
        }
        return categories;
    }

    function setCategory(id) {
        categoryId = String(id || "");
    }

    // The launcher re-scores plugin items itself unless a row arrives
    // pre-scored, and its own sort is not stable, so every row carries a
    // score: definition order at rest (the shell honors a pre-score above
    // 900 with no query), and match quality while searching, where a hit on
    // the name beats the path, an alias, or the description.
    function scoreRow(row, terms, index) {
        const order = 1000 - index / 10;
        if (terms.length === 0)
            return order;
        const label = row.label.toLowerCase();
        const query = terms.join(" ");
        let score;
        if (label === query)
            score = 1000;
        else if (label.indexOf(query) === 0)
            score = 900;
        else if (label.indexOf(query) >= 0)
            score = 800;
        else if (terms.every(term => label.indexOf(term) >= 0))
            score = 700;
        else if (terms.every(term => row.pathText.indexOf(term) >= 0 || row.keywordText.indexOf(term) >= 0))
            score = 600;
        else
            score = 500;
        return score - index / 10;
    }

    function getItems(query) {
        // A stale inventory is asked for again when the search starts, not
        // on every keystroke: the refresh runs `zz app list` and re-renders
        // the launcher when it lands.
        if (!query)
            menuInventory.refreshIfStale();
        const terms = String(query || "").toLowerCase().split(/\s+/).filter(term => term.length > 0);
        const rows = menuInventory.rows;
        const items = [];
        for (let i = 0; i < rows.length; i++) {
            const row = rows[i];
            if (categoryId && row.group !== categoryId)
                continue;
            let matches = true;
            for (let t = 0; t < terms.length; t++) {
                if (row.search.indexOf(terms[t]) < 0) {
                    matches = false;
                    break;
                }
            }
            if (!matches)
                continue;
            let comment = row.description;
            if (row.path.length > 0)
                comment = row.path.join(" › ") + (row.description ? " · " + row.description : "");
            items.push({
                id: row.id,
                name: row.label,
                icon: "material:" + row.icon,
                comment: comment,
                action: row.action,
                terminal: row.terminal,
                keywords: row.keywords,
                categories: ["ZZ"],
                _preScored: scoreRow(row, terms, i)
            });
        }
        return items;
    }

    function executeItem(item) {
        menuInventory.run(item);
    }

    Component.onCompleted: {
        if (pluginService)
            trigger = String(pluginService.loadPluginData(pluginId, "trigger", trigger) || trigger);
    }
}
