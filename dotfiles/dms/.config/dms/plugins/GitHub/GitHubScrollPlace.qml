import QtQuick
import "GitHubLogic.js" as Logic

// Where a view (the list, a page) was scrolled when the popout went away,
// and the way back there when it shows again. The hidden popout lays its
// content out again, which scrolls the view to the top, and coming back the
// content grows back over a few frames: the place is taken up again as it
// grows, until it fits or a moment passes.
QtObject {
    id: place

    // The Flickable it keeps the place of.
    property Flickable target: null
    property real kept: 0
    // The place still to take up, or -1.
    property real pending: -1

    function keep() {
        kept = target.contentY;
    }

    function restore() {
        pending = kept;
        settle.restart();
        apply();
    }

    function apply() {
        if (pending < 0 || !target)
            return;
        target.contentY = Logic.scrollClamp(pending, target.originY, target.contentHeight, target.height);
        if (target.contentHeight - target.height >= pending)
            pending = -1;
    }

    property Timer settle: Timer {
        interval: 1500
        onTriggered: place.pending = -1
    }

    property Connections growth: Connections {
        target: place.target

        function onContentHeightChanged() {
            place.apply();
        }
    }
}
