import QtQuick
import qs.Common

// Drag handles on the popout's free edges and corners: every side but the
// one against the bar. A double click on any handle asks for the default
// size back.
//
// The pulled edge goes where the pointer has travelled since the press:
// its starting place plus the pointer's offset. niri reports a drag in the
// frame of the surface as it stood at the press, even as the popout moves
// on screen, so the offset read from the handle stays true for the whole
// drag. The size that puts the edge there comes from the popout's own
// placement, which centers it on the mark or pins it against the screen.
Item {
    id: resizer

    // The DankPopout hosting the panel.
    property var popout: null
    property real minWidth: 400
    property real minHeight: 360

    // The popout's width and this panel's height, as a drag makes them.
    signal resizing(real width, real height)
    signal finished(real width, real height)
    signal resetRequested()

    // DankPopout numbers the bar edges 0 top, 1 bottom, 2 left, 3 right.
    readonly property int barEdge: popout ? popout.effectiveBarPosition : 0
    readonly property real maxWidth: popout ? Math.max(minWidth, popout.screenWidth - Theme.spacingXL * 2) : minWidth
    readonly property real maxHeight: popout ? Math.max(minHeight, popout.screenHeight - popout.storedBarThickness - popout.storedBarSpacing - 96) : minHeight

    readonly property int thickness: Theme.spacingS + 4
    readonly property int corner: 20
    // The panel sits inside the popout's padding; the handles reach out to
    // its visible edge.
    readonly property int outset: Theme.spacingS

    property var heldGrip: null
    property point pressedAt
    property real startEdgeX: 0
    property real startEdgeY: 0
    property real startWidth: 0
    property real startHeight: 0
    property real nextWidth: 0
    property real nextHeight: 0

    function clamp(value, low, high) {
        return Math.round(Math.max(low, Math.min(high, value)));
    }

    // Where the pulled edge sits on screen at the size last asked for.
    function edgeX(sx) {
        return sx < 0 ? popout.alignedX : popout.alignedX + popout.popupWidth;
    }

    function edgeY(sy) {
        return sy < 0 ? popout.alignedY : popout.alignedY + popout.popupHeight;
    }

    function begin(area, mouse) {
        if (!popout)
            return;
        heldGrip = area;
        pressedAt = area.mapToItem(resizer, mouse.x, mouse.y);
        startEdgeX = edgeX(area.sx);
        startEdgeY = edgeY(area.sy);
        startWidth = popout.popupWidth;
        startHeight = resizer.height;
        nextWidth = startWidth;
        nextHeight = startHeight;
    }

    // Moves one edge by `gap`: try the size a centered popout needs, see
    // how far the edge really went, and correct once when the popout is
    // pinned against the screen (or cannot move that way at all).
    function solve(size, gap, guess, low, high, apply, edge) {
        const before = edge();
        const tried = clamp(size + gap / guess, low, high);
        if (tried === size)
            return size;
        apply(tried);
        const moved = edge() - before;
        if (Math.abs(moved - gap) < 1)
            return tried;
        const slope = moved / (tried - size);
        const settled = Math.abs(slope) < 0.01 ? size : clamp(size + gap / slope, low, high);
        apply(settled);
        return settled;
    }

    function step(area, mouse) {
        if (heldGrip !== area)
            return;
        const p = area.mapToItem(resizer, mouse.x, mouse.y);
        if (area.sx !== 0) {
            const gap = startEdgeX + (p.x - pressedAt.x) - edgeX(area.sx);
            if (Math.abs(gap) >= 1)
                nextWidth = solve(nextWidth, gap, barEdge <= 1 ? area.sx * 0.5 : area.sx, minWidth, maxWidth, width => resizing(width, nextHeight), () => edgeX(area.sx));
        }
        if (area.sy !== 0) {
            const gap = startEdgeY + (p.y - pressedAt.y) - edgeY(area.sy);
            if (Math.abs(gap) >= 1)
                nextHeight = solve(nextHeight, gap, barEdge >= 2 ? area.sy * 0.5 : area.sy, minHeight, maxHeight, height => resizing(nextWidth, height), () => edgeY(area.sy));
        }
    }

    // A press that changed nothing saves nothing, so the second click of
    // a double click cannot put back the size the reset just cleared.
    function end(area) {
        if (heldGrip !== area)
            return;
        heldGrip = null;
        if (nextWidth !== startWidth || nextHeight !== startHeight)
            finished(nextWidth, nextHeight);
    }

    component Grip: MouseArea {
        id: grip

        // Which way the handle pulls: -1 the left or top edge, 1 the right
        // or bottom edge, 0 not along that axis.
        property int sx: 0
        property int sy: 0

        visible: !(sx < 0 && resizer.barEdge === 2) && !(sx > 0 && resizer.barEdge === 3) && !(sy < 0 && resizer.barEdge === 0) && !(sy > 0 && resizer.barEdge === 1)
        hoverEnabled: true
        preventStealing: true
        cursorShape: sx !== 0 && sy !== 0 ? (sx === sy ? Qt.SizeFDiagCursor : Qt.SizeBDiagCursor) : (sx !== 0 ? Qt.SizeHorCursor : Qt.SizeVerCursor)
        onPressed: mouse => resizer.begin(grip, mouse)
        onPositionChanged: mouse => resizer.step(grip, mouse)
        onReleased: resizer.end(grip)
        onCanceled: resizer.end(grip)
        onDoubleClicked: {
            resizer.heldGrip = null;
            resizer.resetRequested();
        }

        // A short bar on the edge being pulled, so the handle shows itself
        // under the pointer.
        Rectangle {
            visible: (grip.containsMouse || grip.pressed) && (grip.sx === 0 || grip.sy === 0)
            anchors.centerIn: parent
            width: grip.sx === 0 ? 40 : 4
            height: grip.sy === 0 ? 40 : 4
            radius: 2
            color: Theme.withAlpha(Theme.primary, grip.pressed ? 0.9 : 0.6)
        }
    }

    Grip {
        sx: -1
        x: -resizer.outset
        y: resizer.corner - resizer.outset
        width: resizer.thickness
        height: resizer.height - resizer.corner * 2 + resizer.outset * 2
    }

    Grip {
        sx: 1
        x: resizer.width + resizer.outset - width
        y: resizer.corner - resizer.outset
        width: resizer.thickness
        height: resizer.height - resizer.corner * 2 + resizer.outset * 2
    }

    Grip {
        sy: -1
        x: resizer.corner - resizer.outset
        y: -resizer.outset
        width: resizer.width - resizer.corner * 2 + resizer.outset * 2
        height: resizer.thickness
    }

    Grip {
        sy: 1
        x: resizer.corner - resizer.outset
        y: resizer.height + resizer.outset - height
        width: resizer.width - resizer.corner * 2 + resizer.outset * 2
        height: resizer.thickness
    }

    Grip {
        sx: -1
        sy: -1
        x: -resizer.outset
        y: -resizer.outset
        width: resizer.corner
        height: resizer.corner
    }

    Grip {
        sx: 1
        sy: -1
        x: resizer.width + resizer.outset - width
        y: -resizer.outset
        width: resizer.corner
        height: resizer.corner
    }

    Grip {
        sx: -1
        sy: 1
        x: -resizer.outset
        y: resizer.height + resizer.outset - height
        width: resizer.corner
        height: resizer.corner
    }

    Grip {
        sx: 1
        sy: 1
        x: resizer.width + resizer.outset - width
        y: resizer.height + resizer.outset - height
        width: resizer.corner
        height: resizer.corner
    }
}
