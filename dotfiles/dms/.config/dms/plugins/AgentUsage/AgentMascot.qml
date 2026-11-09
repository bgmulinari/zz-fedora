import QtQuick
import qs.Common

// The popout's mascots, each following its own agent and each drawn exactly as
// its own product draws it. Clawd comes from Claude Code's welcome screen: its
// block glyphs, poses, and 60ms frame sequences. The Codex companion comes from
// the ChatGPT app's player: its spritesheet rows, frame timings, and jump on
// hover. What they do with those frames between them, the variety and the duets,
// is this strip's own, and so are the props they play with, which are drawn here
// and never touch either mascot's own pixels. One timer drives both and only runs while the strip is on
// screen, so a closed popout costs nothing.
Canvas {
    id: scene

    // Which mascots are here: an agent without one has no business on stage.
    property bool showClaude: false
    property bool showCodex: false
    // sleeping | idle | working | waiting | out
    property string claudeMood: "sleeping"
    // idle | working | worried | out
    property string codexMood: "idle"
    // The spritesheet's local path, empty until there is one.
    property string codexSheet: ""
    property bool active: false
    // The pointer over the strip, in the strip's coordinates.
    property bool pointerInside: false
    property real pointerX: 0
    property real pointerY: 0

    readonly property bool animated: active && Theme.currentAnimationSpeed !== SettingsData.AnimationSpeed.None

    // Room above the companion's head for what they play with.
    implicitHeight: 80

    // --------------------------------------------------------------- reactions

    // Something worth celebrating: a turn that ended or a window that reset.
    function play(agent) {
        // Good news for one is good news for both.
        if (showClaude)
            startClawdSequence(clawdSequences.celebrate);
        if (showCodex)
            playCodex("jumping", 3);
    }

    // A click plays one of the sequences Claude Code plays on a click, unless
    // one is playing; the companion waves.
    function clickAt(x, y) {
        if (showClaude && overClawd(x, y)) {
            if (clawdSequence === null) {
                playClawd(pick(clawdClickSequences));
                // The other one notices.
                if (showCodex && codexState() === "idle")
                    playCodex(pick(["waving", "jumping"]), 1);
            }
        } else if (showCodex && overCodex(x, y)) {
            playCodex("waving", 3);
            if (showClaude && clawdSequence === null && duetSteps === null)
                startClawdSequence(clawdSequences.look);
        }
    }

    onActiveChanged: {
        if (active) {
            cancelDuet();
            clawdX = Math.min(clawdX, clawdRange);
            codexX = codexHomeX;
            startCodexState();
            // Claude Code has Clawd make an entrance, a random one each time, and
            // the companion gets one to match. Asleep or out of its limit, each
            // stays as it is.
            if (showClaude && claudeMood !== "sleeping" && claudeMood !== "out")
                startClawdSequence(clawdSequences[pick(clawdEntrances)]);
            if (showCodex && codexMood !== "out")
                playCodex(pick(["waving", "jumping", "review"]), 1);
            requestPaint();
        }
    }
    onClaudeMoodChanged: {
        cancelDuet();
        clawdFrame = 0;
        requestPaint();
    }
    onCodexMoodChanged: {
        cancelDuet();
        startCodexState();
    }
    onShowClaudeChanged: requestPaint()
    onWidthChanged: {
        clawdX = Math.max(0, Math.min(clawdRange, clawdX));
        requestPaint();
    }

    Timer {
        // Claude Code's frame time.
        interval: scene.frameMs
        repeat: true
        running: scene.animated
        onTriggered: {
            if (scene.showClaude)
                scene.stepClawd();
            if (scene.showCodex)
                scene.stepCodex();
            scene.stepDuet();
            if (scene.propsMoving())
                scene.requestPaint();
        }
    }

    readonly property int frameMs: 60

    function pick(list) {
        return list[Math.floor(Math.random() * list.length)];
    }

    // Now and then each does something else, on the same rhythm but a clock of
    // its own so the two do not move in step: ticks until the next one.
    function ticksBetween(lowSeconds, highSeconds) {
        return Math.round((lowSeconds + Math.random() * (highSeconds - lowSeconds)) * 1000 / frameMs);
    }

    // ------------------------------------------------------------- Codex's sheet
    //
    // The rows and timings of the ChatGPT app's pet player. Each state plays
    // three times and settles into the idle loop; a state saying what Codex is
    // doing right now keeps looping instead, which the player also offers, since
    // the strip is only on screen for a glance.
    //
    // The companion fills 75% by 82% of its frame, so this size gives it about
    // the visual weight of Clawd. The frame's multiple of 12 by 13 keeps the
    // scaled rows and columns on whole pixels.
    readonly property int codexCellWidth: 60
    readonly property int codexCellHeight: 65

    readonly property var codexIdleMs: [280, 110, 110, 140, 140, 320].map(ms => ms * 6)
    readonly property var codexTracks: ({
            // The running rows are a scramble for being dragged, not a walk: one
            // leg swings through (column 2) and reaches (column 4) while the
            // other stays put, the stands between them are near copies, and the
            // last two columns repeat the first two. Played straight, it holds
            // a stand for frames on end and steps on one leg. This order swings
            // the leg out and back through its stride instead, with a single
            // stand between strides.
            running_right: codexCycle(1, [1, 2, 4, 2]),
            running_left: codexCycle(2, [1, 2, 4, 2]),
            waving: codexTrack(3, 4, 140, 280),
            jumping: codexTrack(4, 5, 140, 280),
            failed: codexTrack(5, 8, 140, 240),
            waiting: codexTrack(6, 6, 150, 260),
            running: codexTrack(7, 6, 120, 220),
            review: codexTrack(8, 6, 150, 280),
            // The two rows the app only points its head with, played as one full
            // turn at the sheet's quickest pace, and missing from older sheets.
            headSpin: codexTrack(9, 8, 110, 110).concat(codexTrack(10, 8, 110, 220))
        })
    readonly property bool codexHasLookRows: codexImage.implicitHeight >= 11 * codexCellHeight - 1
    readonly property real codexHomeX: width - codexCellWidth - (showClaude ? 16 : (width - codexCellWidth) / 2)
    onCodexHomeXChanged: if (duetSteps === null && codexTarget < 0)
        codexX = codexHomeX
    // Its feet, 96% of the way down its frame, level with Clawd's.
    readonly property real codexY: Math.round(clawdTop + clawdGround * px - codexCellHeight * 0.96)

    property string codexTransient: ""
    property bool codexHovered: false
    property int codexFlourishIn: ticksBetween(6, 14)
    property int codexPasses: 3
    // Running to a spot, -1 when not, and how much faster than its stride.
    property real codexTarget: -1
    property real codexSpeed: 1
    // Pixels a tick while it runs. The app only plays the running rows while the
    // pet is dragged, so their feet run in place and any travel slides them;
    // travel bunched into some frames shows as a skid on one leg, while an even
    // pace reads as the stride carrying it.
    readonly property real codexPace: 1.5
    // How far each running frame carries it. Its legs step by the ground covered,
    // not by the clock, so a faster run steps faster instead of gliding further
    // on each frame. A speed that is a whole multiple of the pace keeps the
    // steps on whole ticks.
    readonly property real codexFrameStride: 3
    property real codexWalked: 0
    // A row a duet holds it on.
    property string codexHeldRow: ""
    property real codexX: width - codexCellWidth - 16
    property var codexFrames: []
    property int codexLoopStart: 0
    property int codexIndex: 0
    property int codexElapsed: 0
    property int codexRow: 0
    property int codexColumn: 0

    readonly property var codexFlourishes: ({
            idle: ["waving", "jumping", "review", "jog", "headSpin", "juggle", "think", "doze", "groove", "confetti", "idea", "coffee", "bubble", "dizzy"],
            working: ["waving", "review", "think", "idea", "coffee"],
            worried: ["review", "jumping", "think"]
        })
    // The row it plays each prop on, and how many times through.
    readonly property var codexActs: ({
            juggle: ["waving", 4],
            think: ["review", 3],
            doze: ["waiting", 3],
            groove: ["jumping", 3],
            confetti: ["jumping", 3],
            idea: ["waving", 3],
            coffee: ["waiting", 3],
            bubble: ["waiting", 3],
            dizzy: ["headSpin", 2]
        })
    property string codexProp: ""
    property int codexPropTick: 0

    function codexTrack(row, count, ms, lastMs) {
        const frames = [];
        for (let i = 0; i < count; i++)
            frames.push({
                row: row,
                column: i,
                ms: i === count - 1 ? lastMs : ms
            });
        return frames;
    }

    // A running row's columns in the order they play. Its steps follow the
    // ground covered rather than a clock, so the frames carry no time.
    function codexCycle(row, columns) {
        return columns.map(column => ({
                    row: row,
                    column: column,
                    ms: 0
                }));
    }

    function codexIdleFrames() {
        return codexIdleMs.map((ms, i) => ({
                    row: 0,
                    column: i,
                    ms: ms
                }));
    }

    function codexState() {
        if (codexTarget >= 0)
            return codexTarget < codexX ? "running_left" : "running_right";
        if (codexTransient !== "")
            return codexTransient;
        if (codexHeldRow !== "")
            return codexHeldRow;
        if (codexHovered)
            return "jumping";
        switch (codexMood) {
        case "out":
            return "failed";
        case "working":
            return "running";
        case "worried":
            return "waiting";
        }
        return "idle";
    }

    function startCodexState() {
        const state = codexState();
        if (state === "idle") {
            codexFrames = codexIdleFrames();
            codexLoopStart = 0;
        } else if (state === "running_left" || state === "running_right" || (codexTransient === "" && (state === "failed" || state === "running" || state === "waiting"))) {
            codexFrames = codexTracks[state];
            codexLoopStart = 0;
        } else {
            const track = codexTracks[state];
            const passes = codexTransient !== "" ? codexPasses : 3;
            let frames = [];
            for (let i = 0; i < passes; i++)
                frames = frames.concat(track);
            codexFrames = frames.concat(codexIdleFrames());
            codexLoopStart = frames.length;
        }
        codexIndex = 0;
        codexElapsed = 0;
        codexWalked = 0;
        showCodexFrame();
    }

    function showCodexFrame() {
        const frame = codexFrames[codexIndex];
        if (!frame)
            return;
        codexRow = frame.row;
        codexColumn = frame.column;
    }

    function overCodex(x, y) {
        return x >= codexX && x < codexX + codexCellWidth && y >= codexY && y < codexY + codexCellHeight;
    }

    onPointerXChanged: pointerMoved()
    onPointerYChanged: pointerMoved()
    onPointerInsideChanged: pointerMoved()

    function pointerMoved() {
        const hovered = pointerInside && showCodex && overCodex(pointerX, pointerY);
        if (hovered !== codexHovered) {
            codexHovered = hovered;
            startCodexState();
        }
    }

    function playCodex(row, passes) {
        codexProp = "";
        codexTransient = row === "headSpin" && !codexHasLookRows ? "waving" : row;
        codexPasses = passes;
        startCodexState();
    }

    function playCodexAct(name) {
        const act = codexActs[name];
        playCodex(act[0], act[1]);
        codexProp = name;
        codexPropTick = 0;
    }

    function runCodexTo(x, speed) {
        codexTarget = Math.max(0, Math.min(width - codexCellWidth, x));
        codexSpeed = speed || 1;
        startCodexState();
    }

    function stepCodex() {
        if (codexFrames.length === 0)
            startCodexState();
        if (codexProp !== "")
            codexPropTick++;
        // Away from home with nothing to do, it heads back.
        if (duetSteps === null && codexTarget < 0 && codexX !== codexHomeX)
            runCodexTo(codexHomeX);
        if (codexTarget >= 0) {
            const gap = codexTarget - codexX;
            const travel = codexPace * codexSpeed;
            if (Math.abs(gap) <= travel) {
                codexX = codexTarget;
                codexTarget = -1;
                startCodexState();
            } else {
                codexX += gap > 0 ? travel : -travel;
                codexWalked += travel;
                if (codexWalked >= codexFrameStride) {
                    codexWalked -= codexFrameStride;
                    codexIndex = (codexIndex + 1) % codexFrames.length;
                    showCodexFrame();
                }
            }
            return;
        } else if (duetSteps === null && codexTransient === "" && !codexHovered) {
            // Now and then it does something else, whatever it is up to, as Clawd
            // does.
            const flourishes = codexFlourishes[codexMood];
            if (flourishes && --codexFlourishIn <= 0) {
                codexFlourishIn = ticksBetween(6, 14);
                const flourish = pick(flourishes);
                if (flourish === "jog")
                    runCodexTo(codexHomeX + (codexHomeX > width / 2 ? -1 : 1) * (30 + Math.random() * 40));
                else if (codexActs[flourish])
                    playCodexAct(flourish);
                else
                    playCodex(flourish, 1);
                return;
            }
        }
        codexElapsed += frameMs;
        const frame = codexFrames[codexIndex];
        if (frame && codexElapsed >= frame.ms) {
            codexElapsed = 0;
            if (codexIndex + 1 >= codexFrames.length) {
                codexIndex = codexLoopStart;
            } else {
                codexIndex++;
                // A reaction hands back to the mood once it has played.
                if (codexTransient !== "" && codexIndex >= codexLoopStart && codexLoopStart > 0) {
                    codexTransient = "";
                    codexProp = "";
                    startCodexState();
                    return;
                }
            }
        }
        showCodexFrame();
    }

    Item {
        id: codexSprite
        visible: scene.showCodex && scene.codexSheet !== "" && codexImage.status === Image.Ready
        // On whole device pixels, so an even pace stays even on a scaled output.
        x: Math.round(scene.codexX * scene.deviceRatio) / scene.deviceRatio
        y: scene.codexY
        width: scene.codexCellWidth
        height: scene.codexCellHeight
        clip: true

        // Decoded once at this size and slid behind the clip, so a new frame
        // costs no new decode.
        Image {
            id: codexImage
            source: scene.codexSheet !== "" ? "file://" + scene.codexSheet : ""
            x: -scene.codexColumn * scene.codexCellWidth
            y: -scene.codexRow * scene.codexCellHeight
            sourceSize.width: 8 * scene.codexCellWidth
            smooth: true
            asynchronous: true
            cache: false
        }
    }

    // ------------------------------------------------------------------ Clawd
    //
    // Claude Code draws Clawd with 9 by 3 terminal cells, each cell 2 pixels by
    // 4 here: a quadrant glyph fills 1 by 2 of them, and the lower-quarter "lid"
    // glyph the bottom row. Where the eyes are, what a glyph leaves empty shows
    // Clawd's black background rather than nothing.
    readonly property int px: 3
    readonly property int clawdColumns: 18
    readonly property int clawdRows: 12
    // The row just under its feet; the rows below it are for what a crouch kicks up.
    readonly property int clawdGround: 10
    // How far a waddle step takes it: one terminal column.
    readonly property int clawdStep: 2
    readonly property real clawdHalf: showCodex ? width / 2 : width
    readonly property int clawdRange: Math.max(0, Math.floor(clawdHalf / px) - clawdColumns)
    readonly property real clawdTop: height - clawdRows * px

    readonly property string clawdBody: "#D77757"
    readonly property string clawdBackground: "#000000"

    readonly property var clawdQuadrants: ({
            " ": 0,
            "█": 15,
            "▀": 3,
            "▄": 12,
            "▌": 5,
            "▐": 10,
            "▘": 1,
            "▝": 2,
            "▖": 4,
            "▗": 8,
            "▛": 7,
            "▜": 11,
            "▙": 13,
            "▟": 14
        })
    readonly property var clawdArms: ({
            down: {
                r1L: " ▐",
                r1R: "",
                r2L: "▝▜",
                r2R: "█▀"
            },
            up: {
                r1L: "▗▟",
                r1R: "▄",
                r2L: " ▜",
                r2R: "█▘"
            },
            "one-up": {
                r1L: " ▐",
                r1R: "▄",
                r2L: "▝▜",
                r2R: "█▘"
            }
        })
    // Spans laid out from the eyes' first column; a lid is the "▂" glyph.
    readonly property var clawdEyes: ({
            open: "▛███▛█",
            left: "▟███▟█",
            right: "█▟███▟",
            closed: "▂███▂█",
            wink: "▛███▂█"
        })
    readonly property var clawdFeet: ({
            both: " ▝▝   ▝▝ ",
            left: " ▝▝      ",
            right: "      ▝▝ "
        })
    // A turn in place, row by row: its glyphs and the columns where the
    // background shows through.
    readonly property var clawdFacing: ({
            "right-12": [[" ▐█▜██▛█ ", 2, 8], ["▝▜██████▀", 2, 7], [" ▝▝   ▝▝ ", 0, 0]],
            "right-30": [["  █▛██▛▌ ", 2, 7], [" ▝█████▛ ", 2, 7], ["  ▘▘  ▘▘ ", 0, 0]],
            "right-55": [["  ▐█▛█▜  ", 3, 7], ["  ▐████  ", 3, 7], ["  ▝▝ ▝▝  ", 0, 0]],
            "right-75": [["   ██▛▌  ", 3, 6], ["   ███▌  ", 3, 6], ["   ▘  ▘  ", 0, 0]],
            "edge": [["   ▐██   ", 4, 6], ["   ▐██   ", 4, 6], ["   ▝ ▝   ", 0, 0]],
            "back-105": [["   ███▌  ", 3, 6], ["   ███▌  ", 3, 6], ["   ▘  ▘  ", 0, 0]],
            "back-125": [["  ▐████  ", 3, 7], ["  ▐████  ", 3, 7], ["  ▝▝ ▝▝  ", 0, 0]],
            "back-150": [["  █████▌ ", 2, 7], [" ▝█████▛ ", 2, 7], ["  ▘▘  ▘▘ ", 0, 0]],
            "back": [[" ▐██████ ", 2, 8], ["▝▜██████▀", 2, 7], [" ▝▝   ▝▝ ", 0, 0]],
            "left-75": [["   ▛██▌  ", 3, 6], ["   ███▌  ", 3, 6], ["   ▘  ▘  ", 0, 0]],
            "left-55": [["  ▐▜▛██  ", 3, 7], ["  ▐████  ", 3, 7], ["  ▝▝ ▝▝  ", 0, 0]],
            "left-30": [["  ▛██▛█▌ ", 2, 7], [" ▝█████▛ ", 2, 7], ["  ▘▘  ▘▘ ", 0, 0]],
            "left-12": [[" ▐▛███▜█ ", 2, 8], ["▝▜██████▀", 2, 7], [" ▝▝   ▝▝ ", 0, 0]]
        })

    // n frames of a pose, as Claude Code's sequences are written. A pose is
    // [eyes, arms, feet]; an offset sinks it that many terminal rows.
    function hold(eyes, arms, feet, n, offset, poof) {
        const out = [];
        for (let i = 0; i < n; i++)
            out.push({
                eyes: eyes,
                arms: arms,
                feet: feet,
                offset: offset || 0,
                poof: poof || ""
            });
        return out;
    }
    // The same frames shifted that many terminal columns, out of its own frame
    // on the left and so clipped: how the sequences that slide in are written.
    function shifted(frames, x) {
        return frames.map(frame => Object.assign({}, frame, {
                    x: x
                }));
    }
    function standing(n, offset) {
        return hold("open", "down", "both", n, offset);
    }
    function armsUp(n, offset) {
        return hold("open", "up", "both", n, offset);
    }
    function lookRight(n, offset) {
        return hold("right", "down", "both", n, offset);
    }
    function lookLeft(n, offset) {
        return hold("left", "down", "both", n, offset);
    }
    function crouch() {
        return [].concat(hold("open", "down", "both", 1, 1, "dot"), hold("open", "down", "both", 1, 1, "wave"));
    }
    function blinkOut() {
        return [].concat(hold("closed", "down", "both", 1), standing(1));
    }
    function turning(names, shadow) {
        return names.map(name => ({
                    facing: name,
                    offset: 0,
                    poof: "",
                    shadow: shadow || ""
                }));
    }
    function jumpSequence() {
        return [].concat(crouch(), armsUp(3), standing(1), crouch(), armsUp(3), standing(1));
    }

    // Claude Code's sequences, frame for frame.
    readonly property var clawdSequences: {
        const jump = jumpSequence();
        return {
            jump: jump,
            skip: [].concat(shifted(standing(1, 1), -9), shifted(armsUp(2), -6), shifted(standing(1), -6), shifted(standing(1, 1), -6), shifted(armsUp(2), -3), shifted(standing(1), -3), shifted(standing(1, 1), -3), armsUp(2), crouch(), standing(1)),
            waddle: [].concat(shifted(lookRight(1), -9), shifted(hold("right", "down", "left", 2), -6), shifted(hold("right", "down", "right", 2), -5), shifted(hold("right", "down", "left", 2), -4), shifted(hold("right", "down", "right", 2), -3), shifted(hold("right", "down", "left", 2), -2), shifted(hold("right", "down", "right", 2), -1), lookRight(2), standing(2), blinkOut()),
            peek: [].concat(shifted(lookRight(1), -9), shifted(lookRight(5), -6), shifted(lookRight(3), -9), shifted(lookRight(4), -5), shifted(armsUp(2), -3), armsUp(2), crouch(), standing(1)),
            look: [].concat(lookRight(5), lookLeft(5), standing(1)),
            celebrate: [].concat(jump, standing(3, 1)),
            spin: [].concat(lookLeft(2), lookRight(2), lookLeft(2), armsUp(3), standing(1)),
            peekaboo: [].concat(standing(1, 3), standing(3, 2), lookRight(3, 2), lookLeft(3, 2), standing(2, 2), standing(1, 1), armsUp(4), standing(2), blinkOut()),
            drop: [].concat(armsUp(1, -3), armsUp(2, -2), armsUp(2, -1), armsUp(1), crouch(), standing(3), blinkOut()),
            wink: [].concat(hold("wink", "down", "both", 5), standing(1)),
            boop: [].concat(hold("closed", "down", "both", 1, 1, "dot"), hold("closed", "down", "both", 2, 1, "wave"), lookLeft(4), standing(2), blinkOut()),
            tap: [].concat(hold("open", "down", "left", 2), hold("open", "down", "right", 2), hold("open", "down", "left", 2), hold("open", "down", "right", 2), hold("open", "down", "left", 1), hold("open", "down", "right", 1), armsUp(3), standing(1)),
            sneeze: [].concat(hold("closed", "up", "both", 4), hold("closed", "down", "both", 2, 1, "wave"), hold("closed", "down", "both", 2), standing(2), blinkOut()),
            turn: [].concat(turning(["right-12", "right-30", "right-55", "right-75", "edge"]), turning(["back-105", "back-125", "back-150", "back", "back"]), turning(["back-150", "back-125", "back-105", "edge"]), turning(["left-75", "left-55", "left-30", "left-12"]), standing(1)),
            coinHop: [].concat(standing(2, 1), withShadow(armsUp(1), "wide"), turning(["right-55", "edge", "back-125", "back"], "narrow"), turning(["back-125", "edge", "left-55"], "narrow"), withShadow(armsUp(1), "wide"), crouch(), standing(1)),
            // What it does with a prop, in its own poses.
            juggle: [].concat(repeated([].concat(armsUp(4), hold("open", "one-up", "both", 4)), 6), standing(1)),
            think: [].concat(lookRight(14), hold("closed", "down", "both", 2), lookLeft(14), lookRight(14), blinkOut()),
            doze: [].concat(hold("closed", "down", "both", 48, 1), blinkOut()),
            groove: [].concat(repeated([].concat(hold("open", "down", "left", 3), hold("open", "one-up", "right", 3)), 8), standing(1)),
            confetti: [].concat(jump, armsUp(20), jump, standing(2)),
            idea: [].concat(lookLeft(4), lookRight(4), standing(6), armsUp(14), jump, standing(2)),
            coffee: [].concat(lookRight(14), hold("closed", "down", "both", 12), standing(10), lookRight(10), blinkOut()),
            bubble: [].concat(lookRight(44), blinkOut()),
            dizzy: [].concat(repeated([].concat(lookLeft(2), lookRight(2)), 10), hold("closed", "down", "both", 10), blinkOut())
        };
    }
    // Those with a prop: the same names draw it.
    readonly property var clawdActs: ["juggle", "think", "doze", "groove", "confetti", "idea", "coffee", "bubble", "dizzy"]
    // The ones Claude Code plays on a click: those that start in place.
    readonly property var clawdClickSequences: ["jump", "look", "spin", "peekaboo", "drop", "wink", "boop", "tap", "sneeze", "turn", "coinHop"]
    // The ones it can make an entrance with: those plus the three that slide in.
    readonly property var clawdEntrances: clawdClickSequences.concat(["skip", "waddle", "peek"])
    // What it breaks into between loops, by mood. The livelier ones suit idling;
    // at work it only pauses to tap, look around, or think, and waiting it fidgets.
    readonly property var clawdFlourishes: ({
            idle: clawdEntrances.concat(clawdActs),
            working: ["tap", "look", "spin", "think", "idea", "coffee"],
            waiting: ["tap", "spin", "think"]
        })

    function repeated(frames, times) {
        let out = [];
        for (let i = 0; i < times; i++)
            out = out.concat(frames);
        return out;
    }
    function withShadow(frames, shadow) {
        return frames.map(frame => Object.assign({}, frame, {
                    shadow: shadow
                }));
    }

    // Each mood, as a loop of those same poses. Idle is Claude Code's own
    // autoplay loop, waiting its jump, and out a hide and peek from its peekaboo.
    readonly property var clawdLoops: ({
            idle: [].concat(standing(12), lookRight(5), lookLeft(5)),
            waiting: [].concat(jumpSequence(), standing(20)),
            out: [].concat(standing(12, 2), lookRight(6, 2), lookLeft(6, 2)),
            sleeping: hold("closed", "down", "both", 1, 1)
        })

    property int clawdFlourishIn: ticksBetween(6, 14)
    property real clawdX: 0
    // Walking to a column, -1 when not.
    property int clawdTarget: -1
    // A pose a duet holds it in.
    property var clawdHeld: null
    property int clawdDirection: 1
    property int clawdFrame: 0
    property var clawdSequence: null
    property string clawdProp: ""
    property int clawdSequenceIndex: 0
    property var clawdCurrent: standing(1)[0]
    property string clawdDrawn: ""
    property var clawdCache: ({})

    function startClawdSequence(sequence) {
        clawdProp = "";
        clawdSequence = sequence;
        clawdSequenceIndex = 0;
    }

    function playClawd(name) {
        startClawdSequence(clawdSequences[name]);
        if (clawdActs.indexOf(name) >= 0)
            clawdProp = name;
    }

    function overClawd(x, y) {
        return x >= clawdX * px && x < (clawdX + clawdColumns) * px && y >= clawdTop;
    }

    // Working, it waddles from edge to edge, in its waddle sequence's steps: 2
    // frames a step, a terminal column each, looking the way it goes, and it turns
    // around in place at the end.
    function walkingFrame() {
        const eyes = clawdDirection > 0 ? "right" : "left";
        const feet = Math.floor(clawdFrame / 2) % 2 === 0 ? "left" : "right";
        return hold(eyes, "down", feet, 1)[0];
    }

    function stepClawd() {
        let frame;
        // Sent past its own half by a duet that ended early, it heads back.
        if (duetSteps === null && clawdTarget < 0 && clawdX > clawdRange)
            clawdTarget = clawdRange;
        const flourishes = duetSteps === null && clawdTarget < 0 ? clawdFlourishes[claudeMood] : null;
        if (clawdSequence === null && flourishes && --clawdFlourishIn <= 0) {
            clawdFlourishIn = ticksBetween(6, 14);
            playClawd(pick(flourishes));
        }
        if (clawdSequence !== null) {
            frame = clawdSequence[clawdSequenceIndex];
            clawdSequenceIndex++;
            if (clawdSequenceIndex >= clawdSequence.length) {
                if (clawdSequence === clawdSequences.turn)
                    clawdDirection = -clawdDirection;
                clawdSequence = null;
                clawdProp = "";
            }
        } else if (clawdTarget >= 0) {
            clawdFrame++;
            clawdDirection = clawdTarget > clawdX ? 1 : -1;
            if (clawdFrame % 2 === 0)
                clawdX += clawdDirection * Math.min(clawdStep, Math.abs(clawdTarget - clawdX));
            if (clawdX === clawdTarget)
                clawdTarget = -1;
            frame = walkingFrame();
        } else if (clawdHeld !== null) {
            frame = clawdHeld;
        } else if (claudeMood === "working" && duetSteps === null) {
            clawdFrame++;
            if (clawdFrame % 2 === 0) {
                clawdX += clawdDirection * clawdStep;
                if (clawdX <= 0 || clawdX >= clawdRange) {
                    clawdX = Math.max(0, Math.min(clawdRange, clawdX));
                    startClawdSequence(clawdSequences.turn);
                    // Bumping into the companion's side of the strip startles it.
                    if (clawdX > 0 && showCodex && codexState() === "idle" && Math.random() < 0.5)
                        playCodex("jumping", 1);
                }
            }
            frame = walkingFrame();
        } else {
            const loop = clawdLoops[claudeMood] || clawdLoops.idle;
            frame = loop[clawdFrame % loop.length];
            clawdFrame++;
        }
        clawdCurrent = frame;
        // Most frames repeat the last one, and a repeat paints nothing.
        const drawn = JSON.stringify(frame) + clawdX;
        if (drawn !== clawdDrawn) {
            clawdDrawn = drawn;
            requestPaint();
        }
    }

    // ----------------------------------------------------------------- duets
    //
    // What the two get up to together, from their own frames. A duet is a list of
    // steps; a step ends once its walks are done, its sequences have played, and
    // its wait, in ticks, is up. A mood change ends a duet at once, so the strip
    // always tells the truth.
    property var duetSteps: null
    property int duetIndex: -1
    property int duetWait: 0
    property int duetIn: ticksBetween(10, 20)
    // A ball in the air: which way it flies and how far along.
    property var duetBall: null

    readonly property bool bothHere: showClaude && showCodex && codexSprite.visible
    readonly property int clawdPixelWidth: clawdColumns * px
    // The companion's frame has this much air beside its body.
    readonly property int codexMargin: 8

    // Which duets suit what each is doing right now.
    function availableDuets() {
        const pair = claudeMood + "/" + codexMood;
        switch (pair) {
        case "idle/idle":
            return ["highFive", "chase", "copycat", "hideAndSeek", "catch", "jam", "party"];
        case "working/idle":
            return ["highFive", "chase", "copycat", "catch"];
        case "sleeping/idle":
            return ["wakeUp"];
        case "idle/working":
            return ["visit"];
        case "working/working":
            return ["glance"];
        case "out/idle":
            return ["cheerUp"];
        case "idle/out":
            return ["comfort"];
        }
        return [];
    }

    function duet(name) {
        const clawdStart = Math.min(clawdX, clawdRange);
        const home = codexHomeX;
        // A column for Clawd left of the middle, and a spot for the companion
        // right beside it there.
        const meetColumn = Math.max(0, Math.floor((width / 2 - clawdPixelWidth) / px));
        const beside = column => column * px + clawdPixelWidth - codexMargin;
        const besideClawd = beside(clawdStart);
        // A column for Clawd right beside the companion at home.
        const nextToCodex = Math.max(0, Math.floor((home + codexMargin - clawdPixelWidth) / px));
        switch (name) {
        case "highFive":
            return [{
                    clawdWalk: meetColumn,
                    codexRun: beside(meetColumn)
                }, {
                    clawd: "jump",
                    codex: "jumping",
                    codexPasses: 1
                }, {
                    hold: lookRight(1)[0],
                    wait: 8
                }, {
                    clawdWalk: clawdStart,
                    codexRun: home
                }];
        case "chase":
            return [{
                    codexRun: besideClawd + 30,
                    speed: 2
                }, {
                    hold: lookRight(1)[0],
                    wait: 5
                }, {
                    clawdWalk: 0,
                    codexRun: clawdPixelWidth + 10
                }, {
                    clawd: "turn"
                }, {
                    // A head start: Clawd's steps cover more ground than its legs.
                    codexRun: clawdPixelWidth + 40,
                    speed: 2
                }, {
                    codexRun: home,
                    clawdWalk: meetColumn,
                    speed: 2
                }, {
                    codex: "jumping",
                    codexPasses: 1,
                    clawd: "jump"
                }, {
                    clawdWalk: clawdStart
                }];
        case "catch":
            return [{
                    clawdWalk: meetColumn,
                    codexRun: beside(meetColumn) + 60
                }, {
                    hold: armsUp(1)[0],
                    ball: 1,
                    wait: 14
                }, {
                    codex: "jumping",
                    codexPasses: 1,
                    hold: standing(1)[0]
                }, {
                    codex: "waving",
                    codexPasses: 1,
                    ball: -1,
                    wait: 14,
                    hold: standing(1)[0]
                }, {
                    hold: armsUp(1)[0],
                    wait: 6
                }, {
                    hold: armsUp(1)[0],
                    ball: 1,
                    wait: 14
                }, {
                    clawd: "jump",
                    codex: "jumping",
                    codexPasses: 1
                }, {
                    clawdWalk: clawdStart,
                    codexRun: home
                }];
        case "jam":
            return [{
                    clawd: "groove",
                    codexAct: "groove"
                }];
        case "party":
            return [{
                    clawd: "confetti",
                    codexAct: "confetti"
                }];
        case "copycat":
            return [{
                    clawd: "spin",
                    wait: 3
                }, {
                    codex: "review",
                    codexPasses: 1,
                    hold: standing(1)[0]
                }, {
                    clawd: "jump",
                    wait: 3
                }, {
                    codex: "jumping",
                    codexPasses: 1,
                    hold: standing(1)[0]
                }, {
                    codex: "waving",
                    codexPasses: 2,
                    hold: hold("open", "one-up", "both", 1)[0]
                }];
        case "hideAndSeek":
            return [{
                    hold: standing(1, 3)[0],
                    wait: 6
                }, {
                    codexRow: "waiting",
                    hold: standing(1, 3)[0],
                    wait: 25
                }, {
                    codexRow: "waiting",
                    hold: lookRight(1, 2)[0],
                    wait: 12
                }, {
                    clawd: "drop",
                    codex: "jumping",
                    codexPasses: 2
                }];
        case "wakeUp":
            return [{
                    codexRun: besideClawd + 4
                }, {
                    codex: "waving",
                    codexPasses: 2
                }, {
                    hold: lookRight(1)[0],
                    wait: 10
                }, {
                    clawd: "sneeze",
                    codex: "jumping",
                    codexPasses: 1
                }, {
                    codexRun: home,
                    speed: 2
                }];
        case "visit":
            return [{
                    clawdWalk: nextToCodex
                }, {
                    hold: lookRight(1)[0],
                    wait: 20
                }, {
                    clawd: "tap"
                }, {
                    clawdWalk: clawdStart
                }];
        case "glance":
            return [{
                    codex: "waving",
                    codexPasses: 1,
                    clawd: "look"
                }];
        case "cheerUp":
            return [{
                    codexRun: besideClawd + 4
                }, {
                    codex: "waving",
                    codexPasses: 2
                }, {
                    hold: lookRight(1, 1)[0],
                    wait: 10
                }, {
                    codex: "jumping",
                    codexPasses: 1,
                    hold: hold("open", "up", "both", 1, 1)[0]
                }, {
                    codexRun: home
                }];
        case "comfort":
            return [{
                    clawdWalk: nextToCodex
                }, {
                    clawd: "boop"
                }, {
                    hold: hold("open", "one-up", "both", 1)[0],
                    wait: 12
                }, {
                    clawdWalk: clawdStart
                }];
        }
        return [];
    }

    function startDuet(name) {
        duetSteps = duet(name);
        duetIndex = -1;
        nextDuetStep();
    }

    function cancelDuet() {
        duetSteps = null;
        duetBall = null;
        clawdHeld = null;
        codexHeldRow = "";
        clawdTarget = -1;
    }

    function nextDuetStep() {
        duetIndex++;
        if (duetIndex >= duetSteps.length) {
            cancelDuet();
            duetIn = ticksBetween(10, 20);
            startCodexState();
            return;
        }
        const step = duetSteps[duetIndex];
        clawdHeld = step.hold || null;
        codexHeldRow = step.codexRow || "";
        duetWait = step.wait || 0;
        duetBall = step.ball ? {
            direction: step.ball,
            tick: 0,
            ticks: step.wait
        } : null;
        if (step.clawdWalk !== undefined && step.clawdWalk !== clawdX)
            clawdTarget = step.clawdWalk;
        if (step.clawd)
            playClawd(step.clawd);
        if (step.codexRun !== undefined)
            runCodexTo(step.codexRun, step.speed);
        if (step.codexAct)
            playCodexAct(step.codexAct);
        else if (step.codex)
            playCodex(step.codex, step.codexPasses || 1);
        else
            startCodexState();
    }

    function stepDuet() {
        if (duetSteps === null) {
            if (!bothHere || clawdSequence !== null || clawdTarget >= 0 || codexTarget >= 0 || --duetIn > 0)
                return;
            duetIn = ticksBetween(10, 20);
            const available = availableDuets();
            if (available.length > 0)
                startDuet(pick(available));
            return;
        }
        if (duetBall !== null && ++duetBall.tick >= duetBall.ticks)
            duetBall = null;
        if (clawdTarget >= 0 || codexTarget >= 0 || clawdSequence !== null || codexTransient !== "")
            return;
        if (--duetWait <= 0)
            nextDuetStep();
    }

    function poseCells(frame) {
        const rows = [];
        if (frame.facing) {
            const lines = clawdFacing[frame.facing];
            for (let r = 0; r < 3; r++)
                rows.push({
                    text: lines[r][0],
                    from: lines[r][1],
                    to: lines[r][2]
                });
            return rows;
        }
        const arms = clawdArms[frame.arms];
        rows.push({
            text: arms.r1L + clawdEyes[frame.eyes] + arms.r1R,
            from: 2,
            to: 8
        });
        rows.push({
            text: arms.r2L + "█████" + arms.r2R,
            from: 2,
            to: 7
        });
        rows.push({
            text: clawdFeet[frame.feet],
            from: 0,
            to: 0
        });
        return rows;
    }

    // One pose as rows of pixels: 0 empty, 1 body, 2 background.
    function posePixels(frame) {
        const key = frame.facing || (frame.eyes + "/" + frame.arms + "/" + frame.feet);
        if (clawdCache[key])
            return clawdCache[key];
        const grid = [];
        for (let y = 0; y < clawdRows; y++)
            grid.push(new Array(clawdColumns).fill(0));
        const rows = poseCells(frame);
        for (let r = 0; r < rows.length; r++) {
            const glyphs = Array.from(rows[r].text);
            for (let c = 0; c < glyphs.length; c++) {
                const inside = c >= rows[r].from && c < rows[r].to;
                const lid = glyphs[c] === "▂";
                const bits = lid ? 15 : (clawdQuadrants[glyphs[c]] || 0);
                for (let q = 0; q < 4; q++) {
                    const set = (bits >> q) & 1;
                    const value = set ? 1 : (inside ? 2 : 0);
                    const x = c * 2 + (q % 2);
                    const y = r * 4 + (q >= 2 ? 2 : 0);
                    grid[y][x] = value;
                    grid[y + 1][x] = value;
                }
                if (lid) {
                    grid[r * 4 + 3][c * 2] = 2;
                    grid[r * 4 + 3][c * 2 + 1] = 2;
                }
            }
        }
        clawdCache[key] = grid;
        return grid;
    }

    function drawClawd(ctx) {
        const frame = clawdSequence === null && !animated ? (clawdLoops[claudeMood] || clawdLoops.idle)[0] : clawdCurrent;
        const grid = posePixels(frame);
        const left = clawdX * px;
        const shift = (frame.x || 0) * 2;
        const inactive = Theme.surfaceVariantText;
        // Sunk, dropped, or slid in by whole terminal cells, and clipped to its
        // own frame.
        for (let y = 0; y < clawdRows; y++) {
            const row = y + frame.offset * 4;
            if (row < 0 || row >= clawdRows)
                continue;
            for (let x = 0; x < clawdColumns; x++) {
                const column = x + shift;
                if (grid[y][x] === 0 || column < 0 || column >= clawdColumns)
                    continue;
                ctx.fillStyle = grid[y][x] === 2 ? clawdBackground : clawdBody;
                fillCell(ctx, left + column * px, clawdTop + row * px, px, px);
            }
        }
        // The puffs a crouch kicks up, and the shadow under a coin hop.
        ctx.fillStyle = inactive;
        if (frame.poof && frame.offset > 0) {
            const puff = frame.poof === "dot" ? [[1, 10]] : [[0, 10], [1, 9]];
            for (let i = 0; i < puff.length; i++) {
                fillCell(ctx, left + puff[i][0] * px, clawdTop + puff[i][1] * px, px, px);
                fillCell(ctx, left + (16 + puff[i][0]) * px, clawdTop + puff[i][1] * px, px, px);
            }
        }
        if (frame.shadow)
            fillCell(ctx, left + (frame.shadow === "wide" ? 6 : 8) * px, clawdTop + 11 * px, (frame.shadow === "wide" ? 6 : 2) * px, px);
    }

    // ----------------------------------------------------------------- props
    //
    // What they play with, the same for both. Each is drawn around an anchor: the
    // middle of a head, its top, the ground, and which way is toward the other.
    readonly property int propPixel: 2
    readonly property var propColors: ["#EF5350", "#E9C46A", "#6FCF97", "#5B8DEF", "#C678DD"]
    readonly property var propLetterZ: ["###", ".#.", "#..", "###"]
    readonly property var propNote: [".##", ".#.", ".#.", "##.", "##."]
    readonly property var propBulb: [".###.", "#####", "#####", ".###."]
    readonly property var propStar: [".#.", "###", ".#."]
    readonly property var propCup: ["####.", "#####", "####.", "####."]
    readonly property var propBubble: [".###.", "#...#", "#...#", "#...#", ".###."]

    function clawdDozing() {
        return showClaude && claudeMood === "sleeping" && clawdSequence === null && clawdHeld === null;
    }

    function propsMoving() {
        return clawdProp !== "" || codexProp !== "" || duetBall !== null || clawdDozing();
    }

    function clawdAnchor() {
        return {
            x: (clawdX + clawdColumns / 2) * px,
            top: clawdTop + (clawdCurrent.offset || 0) * 4 * px,
            ground: clawdTop + clawdGround * px,
            side: 1,
            halfWidth: 21
        };
    }

    function codexAnchor() {
        return {
            x: codexX + codexCellWidth / 2,
            // Its head starts this far down its frame.
            top: codexY + 10,
            ground: codexY + codexCellHeight * 0.96,
            side: -1,
            halfWidth: 24
        };
    }

    function propSprite(ctx, rows, x, y, color) {
        const left = Math.round(x);
        const top = Math.round(y);
        ctx.fillStyle = color;
        for (let r = 0; r < rows.length; r++)
            for (let c = 0; c < rows[r].length; c++)
                if (rows[r][c] === "#")
                    fillCell(ctx, left + c * propPixel, top + r * propPixel, propPixel, propPixel);
    }

    function propDot(ctx, x, y, size, color) {
        ctx.fillStyle = color;
        fillCell(ctx, Math.round(x), Math.round(y), size * propPixel, size * propPixel);
    }

    function drawProp(ctx, name, t, at) {
        const faint = Theme.surfaceVariantText;
        const bright = Theme.surfaceText;
        switch (name) {
        case "juggle":
            for (let i = 0; i < 3; i++) {
                const angle = t * 0.22 + i * 2.094;
                propDot(ctx, at.x - 2 + Math.cos(angle) * 14, at.top - 5 - Math.abs(Math.sin(angle)) * 10, 2, propColors[i]);
            }
            break;
        case "think":
            if (t > 4)
                propDot(ctx, at.x + at.side * 8, at.top - 3, 1, bright);
            if (t > 9)
                propDot(ctx, at.x + at.side * 13, at.top - 7, 1, bright);
            if (t > 14) {
                const bubbleX = at.x + at.side * 20 - 10;
                ctx.fillStyle = bright;
                fillCell(ctx, Math.round(bubbleX), Math.max(0, Math.round(at.top - 17)), 20, 9);
                for (let i = 0; i < 3; i++)
                    if (Math.floor(t / 5) % 4 > i)
                        propDot(ctx, bubbleX + 3 + i * 5, Math.max(0, Math.round(at.top - 17)) + 3, 1, clawdBackground);
            }
            break;
        case "doze":
            for (let i = 0; i < 3; i++) {
                const rise = ((t + i * 16) % 48) / 48;
                ctx.globalAlpha = rise < 0.8 ? 1 : (1 - rise) * 5;
                propSprite(ctx, propLetterZ, at.x + at.side * (10 + rise * 8), at.top - 2 - rise * 13 - 8, faint);
            }
            ctx.globalAlpha = 1;
            break;
        case "groove":
            ctx.fillStyle = bright;
            fillCell(ctx, Math.round(at.x - at.halfWidth + 5), Math.round(at.top - 4), 2 * at.halfWidth - 10, propPixel);
            fillCell(ctx, Math.round(at.x - at.halfWidth + 1), Math.round(at.top - 2), propPixel * 2, propPixel);
            fillCell(ctx, Math.round(at.x + at.halfWidth - 5), Math.round(at.top - 2), propPixel * 2, propPixel);
            fillCell(ctx, Math.round(at.x - at.halfWidth - 1), Math.round(at.top), propPixel * 2, 12);
            fillCell(ctx, Math.round(at.x + at.halfWidth - 3), Math.round(at.top), propPixel * 2, 12);
            for (let i = 0; i < 2; i++) {
                const rise = ((t + i * 14) % 28) / 28;
                ctx.globalAlpha = 1 - rise * rise;
                propSprite(ctx, propNote, at.x + at.side * (at.halfWidth + 3 + rise * 6) - 3, at.top + 2 - rise * 16, propColors[i * 2 + 1]);
            }
            ctx.globalAlpha = 1;
            break;
        case "confetti":
            for (let i = 0; i < 12; i++) {
                const fall = ((t * 1.3 + i * 13) % 44) / 44;
                const x = at.x + (i - 5.5) * 6 + Math.sin(t * 0.25 + i) * 3;
                propDot(ctx, x, Math.max(0, at.top - 16) + fall * (at.ground - at.top + 12), 1, propColors[i % propColors.length]);
            }
            break;
        case "idea":
            if (t > 13) {
                propSprite(ctx, propBulb, at.x - 5, at.top - 15, propColors[1]);
                propSprite(ctx, ["###"], at.x - 3, at.top - 7, faint);
                if (Math.floor(t / 4) % 2 === 0) {
                    propDot(ctx, at.x - 11, at.top - 12, 1, propColors[1]);
                    propDot(ctx, at.x + 9, at.top - 12, 1, propColors[1]);
                }
            }
            break;
        case "coffee":
            const cupX = at.x + at.side * (at.halfWidth + 9) - 5;
            const cupY = at.ground - 8;
            propSprite(ctx, propCup, cupX, cupY, bright);
            ctx.fillStyle = "#7A4F2B";
            fillCell(ctx, Math.round(cupX), Math.round(cupY), 8, propPixel);
            for (let i = 0; i < 2; i++) {
                const rise = ((t + i * 9) % 18) / 18;
                ctx.globalAlpha = 1 - rise;
                propDot(ctx, cupX + 1 + i * 4 + Math.sin(t * 0.4 + i * 2) * 1.5, cupY - 3 - rise * 12, 1, faint);
            }
            ctx.globalAlpha = 1;
            break;
        case "bubble":
            for (let i = 0; i < 2; i++) {
                const rise = ((t + i * 20) % 40) / 40;
                const x = at.x + at.side * (at.halfWidth + 2 + rise * 9) - 5 + Math.sin(rise * 9) * 2;
                const y = at.top + 8 - rise * 22;
                ctx.globalAlpha = 0.85;
                if (rise < 0.9) {
                    propSprite(ctx, rise < 0.3 ? propStar : propBubble, x, y, bright);
                } else {
                    // Pop.
                    propDot(ctx, x - 3, y - 3, 1, bright);
                    propDot(ctx, x + 9, y - 3, 1, bright);
                    propDot(ctx, x - 3, y + 8, 1, bright);
                    propDot(ctx, x + 9, y + 8, 1, bright);
                }
            }
            ctx.globalAlpha = 1;
            break;
        case "dizzy":
            for (let i = 0; i < 3; i++) {
                const angle = t * 0.3 + i * 2.094;
                propSprite(ctx, propStar, at.x - 3 + Math.cos(angle) * at.halfWidth * 0.8, at.top - 6 + Math.sin(angle) * 3, propColors[1]);
            }
            break;
        }
    }

    // A ball flying between them, up and over.
    function drawBall(ctx) {
        const from = clawdAnchor();
        const to = codexAnchor();
        const fromX = from.x + 14;
        const fromY = from.top - 4;
        const toX = to.x - 14;
        const toY = to.top + 6;
        const along = duetBall.tick / duetBall.ticks;
        const done = duetBall.direction > 0 ? along : 1 - along;
        const peak = Math.sin(along * Math.PI) * Math.min(14, Math.min(fromY, toY));
        propDot(ctx, fromX + (toX - fromX) * done, fromY + (toY - fromY) * done - peak, 2, propColors[0]);
    }

    // The window's own scale, not the screen's: on a fractionally scaled output
    // the screen reports the next whole number while the canvas paints at, say,
    // 1.25 device pixels to the point.
    property real deviceRatio: 1

    // Every rectangle drawn here, its edges on whole device pixels. Unsnapped, a
    // 3-point cell at 1.25 lands on fractional pixels, each edge is antialiased
    // against the next cell's, and the seams show as a grid across the sprite.
    function fillCell(ctx, x, y, w, h) {
        const left = Math.round(x * deviceRatio) / deviceRatio;
        const top = Math.round(y * deviceRatio) / deviceRatio;
        ctx.fillRect(left, top, Math.round((x + w) * deviceRatio) / deviceRatio - left, Math.round((y + h) * deviceRatio) / deviceRatio - top);
    }

    onPaint: {
        const ctx = getContext("2d");
        ctx.reset();
        deviceRatio = Window.window ? Window.window.devicePixelRatio : 1;
        // Behind the companion's sprite, which is the strip's child.
        if (codexProp !== "" && codexSprite.visible)
            drawProp(ctx, codexProp, codexPropTick, codexAnchor());
        if (showClaude) {
            drawClawd(ctx);
            if (clawdProp !== "")
                drawProp(ctx, clawdProp, clawdSequenceIndex, clawdAnchor());
            else if (clawdDozing())
                drawProp(ctx, "doze", clawdFrame, clawdAnchor());
        }
        if (duetBall !== null)
            drawBall(ctx);
    }
}
