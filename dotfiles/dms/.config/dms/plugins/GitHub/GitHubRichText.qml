import QtQuick
import qs.Widgets
import "GitHubLogic.js" as Logic

// Rich text whose links look like github.com's: the pointer turns to a
// hand over one and it is underlined while it is there. html is the text;
// its links (Logic.anchorOpen's) take linkTint when it has none of their
// own. A click on one comes as linkActivated. A mention (a link to a
// person's or an organization's profile) opens their hover card when the
// pointer rests on it, hung from the line it is on; a card's own text
// turns that off (hovercard).
StyledText {
    id: rich

    property string html: ""
    property string linkTint: ""
    property bool hovercard: true
    property string subjectId: ""
    readonly property string hoveredHref: pointer.hovered ? linkAt(pointer.point.position.x, pointer.point.position.y) : ""

    textFormat: Text.RichText
    text: Logic.linksHovered(html, hoveredHref, linkTint)

    // The card's spot moves to a link's line when the pointer comes onto
    // the link, and stays there while it is on it.
    onHoveredHrefChanged: {
        if (hoveredHref === "")
            return;
        const line = Math.max(1, contentHeight / Math.max(1, lineCount));
        cardSpot.x = pointer.point.position.x;
        cardSpot.y = Math.floor(pointer.point.position.y / line) * line;
        cardSpot.height = line;
    }

    // Off a link the pointer keeps whatever shape is under it (a row's
    // hand, where the row opens something).
    HoverHandler {
        id: pointer
        cursorShape: rich.hoveredHref !== "" ? Qt.PointingHandCursor : undefined
    }

    GitHubCardSpot {
        id: cardSpot
        width: 1
        login: rich.hovercard ? Logic.profileLoginOf(rich.hoveredHref) : ""
        subjectId: rich.subjectId
    }
}
