import QtQuick

// Where a profile link's hover card hangs: a link to a person or an
// organization (GitHubLinkText, a mention in rich text or a Markdown body)
// sets login while the pointer is on it, and the panel's card layer
// (GitHubHovercard) opens their card under (or over) this spot after a
// moment, as an avatar's does. The spot is the link, or the line of text
// it is on; it must not move while the card shows, or the card goes (as it
// does when a scroll moves the link away). subjectId is the pull request
// or issue the card is shown for, when there is one.
Item {
    id: spot

    property string login: ""
    property string subjectId: ""

    // The panel's card layer, the first parent that has one, found on the
    // first hover and kept (see GitHubAvatar).
    property Item cardHost: null
    property string shownFor: ""

    function cardLayer() {
        if (!cardHost)
            for (let p = spot.parent; p && !cardHost; p = p.parent)
                if (p.hovercardLayer !== undefined)
                    cardHost = p.hovercardLayer;
        return cardHost;
    }

    // One spot moves from one link to the next: the card for the last one
    // lets go of it first, so the next one's opens.
    onLoginChanged: {
        const layer = cardLayer();
        if (!layer)
            return;
        if (shownFor !== "") {
            layer.hovered(spot, shownFor, subjectId, false);
            layer.gone(spot);
        }
        shownFor = login;
        if (login !== "")
            layer.hovered(spot, login, subjectId, true);
    }

    Component.onDestruction: {
        if (cardHost)
            cardHost.gone(spot);
    }
}
