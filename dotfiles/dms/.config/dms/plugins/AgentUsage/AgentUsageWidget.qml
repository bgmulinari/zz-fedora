import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.DCommon.Widgets
import qs.Modules.Plugins

// One bar pill and one popout for every AI agent subscription on the machine,
// all on one page, limits first: the question this answers is how much room
// is left, and where. Everything shown comes from the records UsageModel
// discovers; nothing here talks to an endpoint.
PluginComponent {
    id: root

    property var popoutService: null

    readonly property string pluginPath: pluginService && pluginId ? String(pluginService.getPluginPath(pluginId) || "") : ""

    // Every agent with numbers feeds the bar and the summary line; the page
    // gives a section to the ones with a subscription to show, in the order
    // they were dragged into.
    readonly property var providers: usage.enabledProviders
    readonly property var sections: dragSections !== null ? dragSections : usage.panelProviders

    // Countdowns read this instead of Date.now() so the popout keeps telling
    // the truth while it sits open.
    property double nowMs: Date.now()
    onProvidersChanged: {
        nowMs = Date.now();
        noteResets();
    }

    // The bar speaks for every subscription: the fullest window anywhere is
    // the one about to stop a prompt. The settings can pin it to one agent, one
    // kind of window, or both.
    readonly property string pinnedAgent: String(usage.setting("barAgent", "any"))
    readonly property string pinnedLimit: String(usage.setting("barLimit", "fullest"))
    readonly property var pillWindow: pinnedWindow(providers, pinnedAgent, pinnedLimit)
    readonly property bool alarming: !!pillWindow && pillWindow.percent >= 0.9
    readonly property string pillText: pillWindow ? Math.round(pillWindow.percent * 100) + "%" : ""

    // Nothing to report, nothing in the bar: the pill collapses to zero
    // width until the first scan finds usage, and stays away entirely on a
    // machine that has never run an AI agent.
    readonly property bool hasProviders: providers.length > 0
    onHasProvidersChanged: setVisibilityOverride(hasProviders)
    Component.onCompleted: setVisibilityOverride(hasProviders)

    UsageModel {
        id: usage
        settings: root.pluginData
        scriptsDir: root.pluginPath !== "" ? root.pluginPath + "/scripts" : ""
    }

    function clamp(v, lo, hi) {
        return Math.max(lo, Math.min(hi, v));
    }

    function refreshNow() {
        usage.refreshAll(true);
    }

    // ---------------------------------------------------------------- limits
    //
    // Collectors report a short rolling window and a long one, spelled their
    // own way ("Session (5-hour)", "5h window", "Rolling (5h)"). Everything
    // below normalizes them into one record so the meters speak one language.

    function windowIsLong(text) {
        return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0 || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0;
    }

    function windowTitle(label) {
        const text = String(label || "").toLowerCase();
        if (text.indexOf("month") >= 0)
            return "Monthly";
        if (windowIsLong(text))
            return "Weekly";
        if (text.indexOf("session") >= 0 || /\d+\s*-?\s*(h(our)?|m(in(ute)?s?)?)\b/.test(text))
            return "Session";
        const plain = String(label || "").replace(/\s*\(.*\)\s*/, "").trim();
        return plain === "" ? "Limit" : plain;
    }

    // A collector that already knows which window a limit belongs to says so,
    // and that beats reading it back out of the label: a model-scoped limit
    // is titled after its model, and "Opus 5 (1M context)" would parse as a
    // one-minute window. A window whose reset has passed is untouched again.
    function limitWindows(p) {
        if (!p)
            return [];
        const out = [];
        const list = p.limits || [];
        for (let i = 0; i < list.length; i++) {
            const entry = list[i] || {};
            const percent = Number(entry.percent);
            if (!(percent >= 0))
                continue;
            const reset = new Date(String(entry.resetsAt || "")).getTime();
            const expired = isFinite(reset) && reset <= root.nowMs;
            out.push({
                title: String(entry.title || "") !== "" ? String(entry.title) : windowTitle(entry.label),
                percent: expired ? 0 : percent,
                resetAt: expired ? "" : String(entry.resetsAt || "")
            });
        }
        return out;
    }

    // A model-scoped window ("Fable Weekly") is its own allowance, but it runs
    // on the same clock as the window it is named for, so it shows attached to
    // that row rather than as a row of its own. One with nothing to attach to
    // still gets its own row.
    function scopedPart(title) {
        const match = String(title || "").match(/^(.+) (Session|Weekly|Monthly)$/);
        return match ? {
            model: match[1],
            window: match[2]
        } : null;
    }

    function displayWindows(p) {
        const windows = limitWindows(p);
        const out = [];
        const byTitle = {};
        for (let i = 0; i < windows.length; i++) {
            if (scopedPart(windows[i].title))
                continue;
            windows[i].scoped = [];
            out.push(windows[i]);
            byTitle[windows[i].title] = windows[i];
        }
        for (let j = 0; j < windows.length; j++) {
            const part = scopedPart(windows[j].title);
            if (!part)
                continue;
            const base = byTitle[part.window];
            if (base) {
                base.scoped.push({
                    title: part.model,
                    percent: windows[j].percent
                });
            } else {
                windows[j].scoped = [];
                out.push(windows[j]);
            }
        }
        return out;
    }

    // The window that decides how much room is left: the fullest one, since
    // that is what stops the next prompt. Across providers the pill shows
    // whichever agent is closest to its ceiling.
    function worstWindow(list) {
        let best = null;
        for (let i = 0; i < list.length; i++) {
            const windows = limitWindows(list[i]);
            for (let j = 0; j < windows.length; j++) {
                if (!best || windows[j].percent > best.percent)
                    best = windows[j];
            }
        }
        return best;
    }

    // The pinned window, or the nearest thing to it: a pinned agent without the
    // pinned kind of window shows its own fullest, and one with no limits at
    // all leaves the bar to the fullest anywhere rather than to nothing. A kind
    // of window means that window itself, not a model's allowance on its clock.
    function pinnedWindow(list, agent, limit) {
        const agents = agent === "any" ? list : list.filter(p => p.providerId === agent);
        if (limit !== "fullest") {
            let best = null;
            for (let i = 0; i < agents.length; i++) {
                const windows = limitWindows(agents[i]);
                for (let j = 0; j < windows.length; j++) {
                    if (windows[j].title === limit && (!best || windows[j].percent > best.percent))
                        best = windows[j];
                }
            }
            if (best)
                return best;
        }
        return worstWindow(agents) || worstWindow(list);
    }

    function resetMsFor(w) {
        if (!w || w.resetAt === "")
            return -1;
        const ms = new Date(w.resetAt).getTime();
        return isFinite(ms) ? ms - root.nowMs : -1;
    }

    function formatDuration(ms) {
        if (!(ms > 0))
            return "now";
        const minutes = Math.floor(ms / 60000);
        const hours = Math.floor(minutes / 60);
        const days = Math.floor(hours / 24);
        if (days > 0)
            return days + "d " + (hours % 24) + "h";
        if (hours > 0)
            return hours + "h " + (minutes % 60) + "m";
        return Math.max(1, minutes) + "m";
    }

    function plural(count, one, other) {
        return count + " " + (count === 1 ? one : other);
    }

    function limitTooltip(w, stale, fetchedAt) {
        if (!w)
            return "";
        const lines = [];
        const used = w.title + ": " + Math.round(w.percent * 100) + "% used";
        const resetMs = resetMsFor(w);
        lines.push(resetMs > 0 ? used + " · resets in " + formatDuration(resetMs) : used);
        // The age of numbers kept past a failed check is shown only on hover.
        if (stale) {
            if (!(fetchedAt > 0))
                lines.push("Last updated time unavailable");
            else if (root.nowMs - fetchedAt > 60000)
                lines.push("Last updated " + formatDuration(root.nowMs - fetchedAt) + " ago");
            else
                lines.push("Last updated less than a minute ago");
        }
        const scoped = w.scoped || [];
        for (let i = 0; i < scoped.length; i++) {
            const span = w.title === "Session" || w.title === "Weekly" || w.title === "Monthly" ? w.title.toLowerCase() : w.title;
            lines.push(scoped[i].title + ": " + Math.round(scoped[i].percent * 100) + "% of its " + span + " allowance");
        }
        return lines.join("\n");
    }

    function resetCreditsText(credits) {
        const count = credits ? Number(credits.available) : 0;
        if (!(count > 0))
            return "";
        const text = plural(count, "free reset", "free resets");
        const expires = new Date(String(credits.nextExpiresAt || "")).getTime();
        return isFinite(expires) && expires > root.nowMs ? text + " · next expires in " + formatDuration(expires - root.nowMs) : text;
    }

    function planLabel(p) {
        const tier = String(p && p.tierLabel || "");
        return tier === "" ? "" : tier.charAt(0).toUpperCase() + tier.slice(1);
    }

    // --------------------------------------------------------------- mascots
    //
    // Clawd and the Codex companion each follow their own agent, asked only
    // while the popout is open. A limit used up outranks everything, then a
    // session that needs you, then one at work. An agent with no mascot of its
    // own has none on stage. AgentMascot draws them; here is only what they feel.

    readonly property bool mascotsEnabled: usage.setting("mascotEnabled", true) === true
    readonly property bool hasClaude: hasProvider("claude")
    readonly property bool hasCodex: hasProvider("codex")
    // The companion needs its sheet, which may never turn up.
    readonly property bool mascotsShown: mascotsEnabled && (hasClaude || (hasCodex && codexSheet !== ""))
    property var sessions: ({
            claude: {
                busy: 0,
                waiting: 0,
                idle: 0
            },
            codex: {
                running: 0,
                working: false
            }
        })
    property string codexSheet: ""
    // What each mascot has to react to next time it is on screen.
    property var pendingReactions: ({})
    property var lastWindows: ({})

    function hasProvider(id) {
        return providers.some(p => p.providerId === id);
    }

    function fullestOf(id) {
        return worstWindow(providers.filter(p => p.providerId === id));
    }

    readonly property var claudeWindow: fullestOf("claude")
    readonly property var codexWindow: fullestOf("codex")

    readonly property string claudeMood: {
        if (claudeWindow && claudeWindow.percent >= 1)
            return "out";
        if (sessions.claude.waiting > 0)
            return "waiting";
        if (sessions.claude.busy > 0)
            return "working";
        return sessions.claude.idle > 0 ? "idle" : "sleeping";
    }

    readonly property string codexMood: {
        if (codexWindow && codexWindow.percent >= 1)
            return "out";
        if (sessions.codex.working)
            return "working";
        if (codexWindow && codexWindow.percent >= 0.9)
            return "worried";
        return "idle";
    }

    function mascotText() {
        const lines = [];
        if (hasClaude) {
            const counts = sessions.claude;
            const moods = {
                out: "a limit is used up",
                waiting: plural(counts.waiting, "session", "sessions") + " waiting for you",
                working: plural(counts.busy, "session", "sessions") + " working",
                idle: plural(counts.idle, "session", "sessions") + " idle",
                sleeping: "not running"
            };
            lines.push("Claude Code: " + moods[claudeMood]);
        }
        if (hasCodex) {
            const moods = {
                out: "a limit is used up",
                working: "working",
                worried: "close to a limit",
                idle: sessions.codex.running > 0 ? "open" : "not running"
            };
            lines.push("Codex: " + moods[codexMood]);
        }
        return lines.join("\n");
    }

    function queueReaction(agent) {
        const next = Object.assign({}, pendingReactions);
        next[agent] = true;
        pendingReactions = next;
    }

    // A window that has reset reads far below where it last was. Comparing
    // against the last reading, not the reset time, keeps a reset time that
    // merely wobbles between checks from setting this off.
    function noteResets() {
        const seen = {};
        for (let i = 0; i < providers.length; i++) {
            const id = providers[i].providerId;
            const windows = limitWindows(providers[i]);
            for (let j = 0; j < windows.length; j++) {
                const key = id + "/" + windows[j].title;
                const before = lastWindows[key];
                if (before !== undefined && before >= 0.1 && windows[j].percent < before / 2)
                    queueReaction(id);
                seen[key] = windows[j].percent;
            }
        }
        lastWindows = seen;
    }

    function applySessions(text) {
        let parsed = null;
        try {
            parsed = JSON.parse(text);
        } catch (e) {
            return;
        }
        if (!parsed || !parsed.claude || !parsed.codex)
            return;
        // A turn that ended with nothing else going on. Only Claude Code says
        // so outright; Codex's quiet moments might just be a long model call.
        if (sessions.claude.busy > 0 && parsed.claude.busy === 0 && parsed.claude.waiting === 0 && !pendingReactions.claude)
            queueReaction("claude");
        sessions = parsed;
    }

    Process {
        id: sessionProbe
        command: [root.pluginPath + "/scripts/session-state"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.applySessions(text)
        }
    }

    Timer {
        interval: 3000
        repeat: true
        triggeredOnStart: true
        running: root.interactionActive && root.mascotsShown && root.pluginPath !== ""
        onTriggered: {
            if (!sessionProbe.running)
                sessionProbe.running = true;
        }
    }

    // The Codex companion's spritesheet is not shipped with the plugin; this
    // finds or fetches it the first time the strip wants it, and only once
    // while the shell runs, so a machine without one is not asked again.
    property bool codexSheetSought: false
    Process {
        id: codexPetProbe
        command: [root.pluginPath + "/scripts/codex-pet"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.codexSheet = text.trim()
        }
    }

    readonly property bool wantsCodexSheet: interactionActive && mascotsEnabled && hasCodex && codexSheet === "" && !codexSheetSought && pluginPath !== ""
    onWantsCodexSheetChanged: {
        if (wantsCodexSheet && !codexPetProbe.running) {
            codexSheetSought = true;
            codexPetProbe.running = true;
        }
    }

    // ---------------------------------------------------------- sign-in, launch

    // The command that signs each agent in again. Any other agent's sign-in
    // trouble stays text, with its own help to follow.
    readonly property var signInCommands: ({
            claude: "claude auth login",
            codex: "codex login",
            opencode: "opencode auth login"
        })

    // A lapsed or missing sign-in is something to fix from here; any other
    // trouble is only reported.
    function needsSignIn(p) {
        if (!p || !signInCommands[p.providerId])
            return false;
        return p.usageStatusText === "Sign-in expired" || p.usageStatusText === "Waiting for auth";
    }

    // Whatever keeps the numbers from being current, said beside the last ones
    // known: they stay on show until a check succeeds again. A failed refresh
    // with numbers kept may leave the status empty and say why only in its help.
    function usageNote(p) {
        if (!p || needsSignIn(p))
            return "";
        if (p.usageStatusText === "" && !(p.limitsStale === true && p.authHelpText !== ""))
            return "";
        return p.authHelpText || p.usageStatusText;
    }

    function signIn(p) {
        const command = p ? signInCommands[p.providerId] : "";
        if (!command)
            return;
        Quickshell.execDetached(["xdg-terminal-exec", "--title=" + p.providerName + " sign-in", "--", "bash", "-lc", command + "; status=$?; printf '\\nPress Enter to close.'; read _; exit $status"]);
        root.closePopout();
    }

    // The agents `zz agent` knows how to start.
    readonly property var launchable: ["claude", "codex", "opencode"]

    function canLaunch(p) {
        return !!p && launchable.indexOf(p.providerId) >= 0;
    }

    function launch(p) {
        if (!canLaunch(p))
            return;
        Quickshell.execDetached(["bash", "-lc", "exec zz agent run --agent=\"$0\"", p.providerId]);
        root.closePopout();
    }

    // Brand marks resolve by convention so a new collector needs nothing from
    // this file: assets/<id>.svg, plus an assets/<id>-light.svg twin for marks
    // drawn in white. The marks sit directly on the popout surface, so the
    // shell's light or dark mode decides which twin to try first and a missing
    // file falls through to the generic glyph.
    function markCandidates(p) {
        if (!p)
            return [];
        const candidates = [];
        if (Theme.isLightMode)
            candidates.push(Qt.resolvedUrl("assets/" + p.providerId + "-light.svg"));
        candidates.push(Qt.resolvedUrl("assets/" + p.providerId + ".svg"));
        return candidates;
    }

    // --------------------------------------------------------------- summary
    //
    // The hero's line rotates through what the token counts add up to across
    // every agent.

    readonly property var summaryPhrases: {
        let week = 0;
        let today = 0;
        let prompts = 0;
        let sessions = 0;
        const byDay = {};
        const byModel = {};
        for (let i = 0; i < providers.length; i++) {
            const p = providers[i];
            const days = p.recentDays || [];
            for (let d = 0; d < days.length; d++) {
                const tokens = Number(days[d].messageCount || 0);
                week += tokens;
                byDay[days[d].date] = (byDay[days[d].date] || 0) + tokens;
            }
            today += Number(p.todayTotalTokens || 0);
            prompts += Number(p.todayPrompts || 0);
            sessions += Number(p.todaySessions || 0);
            const models = p.modelUsage || {};
            for (const id in models) {
                const bucket = models[id] || {};
                const name = usage.friendlyModelName(id);
                byModel[name] = (byModel[name] || 0) + Number(bucket.inputTokens || 0) + Number(bucket.outputTokens || 0) + Number(bucket.cacheReadInputTokens || 0) + Number(bucket.cacheCreationInputTokens || 0);
            }
        }

        const phrases = [];
        if (week > 0)
            phrases.push(usage.formatTokenCount(week) + " tokens this week");
        if (today > 0)
            phrases.push(usage.formatTokenCount(today) + " tokens today");
        let topModel = "";
        for (const model in byModel) {
            if (topModel === "" || byModel[model] > byModel[topModel])
                topModel = model;
        }
        if (topModel !== "" && byModel[topModel] > 0)
            phrases.push("Mostly " + topModel);
        let busiest = "";
        for (const date in byDay) {
            if (busiest === "" || byDay[date] > byDay[busiest])
                busiest = date;
        }
        if (busiest !== "" && byDay[busiest] > 0)
            phrases.push("Busiest day: " + dayName(busiest));
        if (prompts > 0)
            phrases.push(plural(prompts, "prompt", "prompts") + " today");
        if (sessions > 0)
            phrases.push(plural(sessions, "session", "sessions") + " today");
        return phrases;
    }

    function dayName(date) {
        const parsed = new Date(String(date || "") + "T00:00:00");
        if (isNaN(parsed.getTime()))
            return String(date || "");
        return ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"][parsed.getDay()];
    }

    property int phraseIndex: 0
    property real phraseOpacity: 1
    // Every record that lands rebuilds the phrases, and opening the popout
    // refreshes each agent in turn. Indexing the live list would swap the line
    // on each of those, so the hero holds what it shows until the next fade.
    property string shownPhrase: ""
    onSummaryPhrasesChanged: if (shownPhrase === "" || summaryPhrases.length <= 1)
        showPhrase()

    function showPhrase() {
        const n = summaryPhrases.length;
        shownPhrase = n > 0 ? summaryPhrases[phraseIndex % n] : "";
    }

    SequentialAnimation {
        id: phraseSwap
        PropertyAnimation {
            target: root
            property: "phraseOpacity"
            to: 0
            duration: Theme.shorterDuration
            easing.type: Easing.OutCubic
        }
        ScriptAction {
            script: {
                root.phraseIndex = (root.phraseIndex + 1) % Math.max(1, root.summaryPhrases.length);
                root.showPhrase();
            }
        }
        PropertyAnimation {
            target: root
            property: "phraseOpacity"
            to: 1
            duration: Theme.shortDuration
            easing.type: Easing.OutCubic
        }
    }

    // Only speaks up when the numbers cover more than this machine.
    function footerText() {
        if (usage.syncStatusText !== "")
            return usage.syncStatusText;
        for (let i = 0; i < providers.length; i++) {
            const count = Number(providers[i].syncDeviceCount || 0);
            if (providers[i].syncEnabled && count > 0)
                return "Merged from " + plural(count, "device", "devices");
        }
        return "";
    }

    // -------------------------------------------------------------- keyboard
    //
    // The keyboard walks everything on the page that does something, in reading
    // order: the refresh button, then each agent's line and any Sign-in required
    // link under it. Hovering moves the same cursor, so only one thing is lit.

    readonly property var keyStops: {
        const stops = [
            {
                kind: "refresh",
                index: 0
            }
        ];
        for (let p = 0; p < sections.length; p++) {
            stops.push({
                kind: lineStop(p),
                index: p
            });
            if (needsSignIn(sections[p]))
                stops.push({
                    kind: "signin",
                    index: p
                });
        }
        return stops;
    }
    property bool cursorActive: false
    property int keyIndex: 0
    readonly property var keyTarget: cursorActive && keyIndex >= 0 && keyIndex < keyStops.length ? keyStops[keyIndex] : null

    // Every agent's line is a stop, so Ctrl+Up/Down can move it: its terminal
    // button when it has one, else its mark.
    function lineStop(p) {
        return canLaunch(sections[p]) ? "launch" : "mark";
    }

    function hasKey(kind, index) {
        return !!keyTarget && keyTarget.kind === kind && keyTarget.index === (index || 0);
    }

    function pointAt(kind, index) {
        for (let i = 0; i < keyStops.length; i++) {
            if (keyStops[i].kind === kind && keyStops[i].index === (index || 0)) {
                keyIndex = i;
                cursorActive = true;
                return;
            }
        }
    }

    // The first arrow only shows where the cursor is.
    function moveKey(dy) {
        if (cursorActive)
            keyIndex = clamp(keyIndex + dy, 0, keyStops.length - 1);
        cursorActive = true;
    }

    function activateSelection() {
        const target = keyTarget;
        if (!target || target.kind === "refresh")
            refreshNow();
        else if (target.kind === "launch")
            launch(sections[target.index]);
        else if (target.kind === "signin")
            signIn(sections[target.index]);
    }

    // Ctrl+Up/Down carries the agent the cursor is in up or down the page, and
    // the cursor along with it.
    function reorderProvider(dy) {
        const target = keyTarget;
        if (dragIndex >= 0 || !target || target.kind === "refresh")
            return;
        const to = clamp(target.index + dy, 0, sections.length - 1);
        if (to === target.index)
            return;
        usage.moveProvider(sections[target.index].providerId, to);
        Qt.callLater(() => pointAt(lineStop(to), to));
    }

    function handleKey(event) {
        const control = event.modifiers & Qt.ControlModifier;
        let accepted = true;
        switch (event.key) {
        case Qt.Key_Down:
        case Qt.Key_J:
            control ? reorderProvider(1) : moveKey(1);
            break;
        case Qt.Key_Up:
        case Qt.Key_K:
            control ? reorderProvider(-1) : moveKey(-1);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            activateSelection();
            break;
        case Qt.Key_R:
            refreshNow();
            break;
        case Qt.Key_Escape:
            if (dragIndex >= 0)
                settleProviderDrag(true);
            else
                root.closePopout();
            break;
        default:
            accepted = false;
        }
        event.accepted = accepted;
    }

    // Keeps whatever the cursor lands on inside the scrolled view.
    function revealItem(item) {
        if (!item || !content)
            return;
        const flick = content.flick;
        const top = item.mapToItem(content.column, 0, 0).y;
        const margin = Theme.spacingM;
        if (top - margin < flick.contentY)
            flick.contentY = Math.max(0, top - margin);
        else if (top + item.height + margin > flick.contentY + flick.height)
            flick.contentY = Math.max(0, Math.min(flick.contentHeight - flick.height, top + item.height + margin - flick.height));
    }

    // ------------------------------------------------------------- drag order
    //
    // An agent is dragged by its mark. The layout stays fixed until the lifted
    // section settles: the rows it has passed step aside by its pitch, and only
    // then does the model change.

    // What the popout's lazily built content hands back for the code out here.
    property var content: null
    property var dragSections: null
    property string dragProviderId: ""
    property int dragIndex: -1
    property int dragTarget: -1
    property real dragOffset: 0
    property real dragPressY: 0
    property var rowPitches: []
    property bool settling: false

    readonly property real dragHysteresis: 0.6

    // How many rows a drag of `offset` has passed, fractionally: sections are
    // not all one height, so each is measured by its own pitch.
    function rowsPassed(offset) {
        const step = offset < 0 ? -1 : 1;
        let left = Math.abs(offset);
        let passed = 0;
        for (let i = dragIndex + step; i >= 0 && i < rowPitches.length; i += step) {
            if (left < rowPitches[i])
                return step * (passed + left / rowPitches[i]);
            left -= rowPitches[i];
            passed++;
        }
        return step * (passed + left / rowPitches[dragIndex]);
    }

    function rowShift(index) {
        if (dragIndex < 0)
            return 0;
        if (index === dragIndex)
            return dragOffset;
        const pitch = rowPitches[dragIndex] || 0;
        if (dragIndex < dragTarget && index > dragIndex && index <= dragTarget)
            return -pitch;
        if (dragIndex > dragTarget && index >= dragTarget && index < dragIndex)
            return pitch;
        return 0;
    }

    function beginProviderDrag(index, y) {
        if (dragIndex >= 0 || !content)
            return;
        const pitches = [];
        for (let i = 0; i < content.repeater.count; i++)
            pitches.push(content.repeater.itemAt(i).height + content.column.spacing);
        rowPitches = pitches;
        // Keep the same model object so grabbing does not rebuild the delegates.
        dragSections = sections;
        dragProviderId = sections[index].providerId;
        dragPressY = y;
        dragOffset = 0;
        dragTarget = index;
        dragIndex = index;
    }

    function dragProviderOver(y) {
        if (dragIndex < 0 || settling)
            return;
        dragOffset = y - dragPressY;
        const raw = rowsPassed(dragOffset);
        const held = dragTarget - dragIndex;
        const next = Math.abs(raw - held) >= dragHysteresis ? Math.round(raw) : held;
        dragTarget = clamp(dragIndex + next, 0, sections.length - 1);
    }

    function resetProviderDrag() {
        dropAnimation.stop();
        dragIndex = -1;
        dragTarget = -1;
        dragProviderId = "";
        dragOffset = 0;
        settling = false;
        dragSections = null;
    }

    function finishProviderDrag() {
        const id = dragProviderId;
        const to = dragTarget;
        const moved = dragIndex >= 0 && to !== dragIndex;
        // Disable slot motion before replacing the model: it already matches
        // the preview.
        dragIndex = -1;
        if (moved)
            usage.moveProvider(id, to);
        resetProviderDrag();
        if (moved)
            Qt.callLater(() => pointAt(lineStop(to), to));
    }

    function settleProviderDrag(cancel) {
        if (dragIndex < 0)
            return;
        dropAnimation.stop();
        settling = true;
        if (cancel)
            dragTarget = dragIndex;
        const step = dragTarget < dragIndex ? -1 : 1;
        let offset = 0;
        if (dragTarget !== dragIndex) {
            for (let i = dragIndex + step; step > 0 ? i <= dragTarget : i >= dragTarget; i += step)
                offset += step * rowPitches[i];
        }
        dropAnimation.to = offset;
        dropAnimation.restart();
    }

    NumberAnimation {
        id: dropAnimation
        target: root
        property: "dragOffset"
        duration: Theme.shorterDuration
        easing.type: Easing.OutCubic
        onFinished: root.finishProviderDrag()
    }

    // ------------------------------------------------------------------- bar

    pillRightClickAction: () => root.refreshNow()

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DIcon {
                name: "smart_toy"
                size: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                color: root.alarming ? Theme.error : Theme.widgetIconColor
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                visible: text !== ""
                text: root.pillText
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                color: root.alarming ? Theme.error : Theme.widgetTextColor
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }

    verticalBarPill: Component {
        Column {
            spacing: 1

            DIcon {
                name: "smart_toy"
                size: Theme.barIconSize(root.barThickness, undefined, root.barConfig?.maximizeWidgetIcons, root.barConfig?.iconScale)
                color: root.alarming ? Theme.error : Theme.widgetIconColor
                anchors.horizontalCenter: parent.horizontalCenter
            }

            StyledText {
                visible: text !== ""
                text: root.pillText
                font.pixelSize: Theme.barTextSize(root.barThickness, root.barConfig?.fontScale, root.barConfig?.maximizeWidgetText)
                color: root.alarming ? Theme.error : Theme.widgetTextColor
                anchors.horizontalCenter: parent.horizontalCenter
            }
        }
    }

    // ---------------------------------------------------------------- popout

    popoutWidth: 380

    popoutContent: Component {
        // No header: the hero row names the page and carries the refresh
        // action, and Esc or a click outside closes the popout.
        PopoutComponent {
            id: popout

            readonly property bool showing: !!parentPopout && parentPopout.shouldBeVisible

            function opened() {
                root.nowMs = Date.now();
                root.cursorActive = false;
                root.keyIndex = 0;
                root.resetProviderDrag();
                panelFlick.contentY = 0;
                usage.refreshLimits();
                keys.forceActiveFocus();
                focusRetry.tries = 0;
                focusRetry.restart();
            }

            onShowingChanged: {
                if (showing)
                    opened();
                else
                    root.resetProviderDrag();
            }
            Component.onCompleted: {
                root.content = {
                    flick: panelFlick,
                    column: column,
                    repeater: sectionRepeater
                };
                if (showing)
                    opened();
            }

            // The host and its window hand focus around while the popout comes
            // up, so one forceActiveFocus at open time is not enough.
            Timer {
                id: focusRetry
                interval: 40
                repeat: true
                property int tries: 0
                onTriggered: {
                    if (!popout.showing || keys.activeFocus || ++tries > 25) {
                        stop();
                        return;
                    }
                    keys.forceActiveFocus();
                }
            }

            // Countdowns tick and the summary line turns only while visible.
            Timer {
                interval: 30000
                running: popout.showing
                repeat: true
                onTriggered: root.nowMs = Date.now()
            }

            Timer {
                interval: 2800
                running: popout.showing && root.summaryPhrases.length > 1
                repeat: true
                onTriggered: phraseSwap.restart()
            }

            Item {
                id: keys
                width: 1
                height: 1
                focus: true
                Keys.onPressed: event => root.handleKey(event)
            }

            DFlickable {
                id: panelFlick
                width: parent.width
                implicitHeight: Math.min(column.implicitHeight, 620)
                height: implicitHeight
                contentWidth: width
                contentHeight: column.implicitHeight
                clip: true

                Column {
                    id: column
                    width: panelFlick.width
                    spacing: Theme.spacingL

                    // ---------- Hero: agents · rotating summary · refresh ----------
                    Row {
                        id: heroRow
                        width: parent.width
                        spacing: Theme.spacingM

                        DIcon {
                            id: heroIcon
                            visible: !root.mascotsShown
                            name: "smart_toy"
                            size: 32
                            color: Theme.primary
                            anchors.verticalCenter: parent.verticalCenter
                        }

                        Column {
                            width: heroRow.width - (heroIcon.visible ? heroIcon.width + heroRow.spacing : 0) - heroRefresh.width - heroRow.spacing
                            spacing: 2
                            anchors.verticalCenter: parent.verticalCenter

                            StyledText {
                                width: parent.width
                                text: "Agents"
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                            }

                            StyledText {
                                width: parent.width
                                text: root.shownPhrase !== "" ? root.shownPhrase : "Subscriptions"
                                textFormat: Text.PlainText
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                elide: Text.ElideRight
                                opacity: root.phraseOpacity
                            }
                        }

                        CursorButton {
                            id: heroRefresh
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "refresh"
                            tooltipText: "Refresh"
                            hasCursor: root.hasKey("refresh")
                            onEntered: root.pointAt("refresh")
                            onClicked: root.refreshNow()
                        }
                    }

                    // The strip's top is headroom for what they play with, empty
                    // most of the time; it rises into the gap above it rather than
                    // widening that gap.
                    Item {
                        visible: root.mascotsShown
                        width: parent.width
                        height: scene.height - Theme.spacingL

                        AgentMascot {
                            id: scene
                            y: -Theme.spacingL
                            width: parent.width
                            height: implicitHeight
                            active: popout.showing && root.mascotsShown
                            showClaude: root.hasClaude
                            showCodex: root.hasCodex && root.codexSheet !== ""
                            claudeMood: root.claudeMood
                            codexMood: root.codexMood
                            codexSheet: root.codexSheet
                            pointerInside: sceneMouse.containsMouse
                            pointerX: sceneMouse.mouseX
                            pointerY: sceneMouse.mouseY

                            // Held until the strip is on screen to play them.
                            readonly property var pending: active ? root.pendingReactions : ({})
                            onPendingChanged: {
                                const agents = Object.keys(pending);
                                if (agents.length === 0)
                                    return;
                                for (let i = 0; i < agents.length; i++)
                                    play(agents[i]);
                                // Clearing them here would re-enter this binding.
                                Qt.callLater(() => root.pendingReactions = ({}));
                            }

                            MouseArea {
                                id: sceneMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => scene.clickAt(mouse.x, mouse.y)
                            }

                            DTooltipHost {
                                target: scene
                                hoverArea: sceneMouse
                                text: root.mascotText()
                                multiline: true
                            }
                        }
                    }

                    StyledText {
                        visible: root.providers.length === 0
                        width: parent.width
                        topPadding: Theme.spacingL
                        bottomPadding: Theme.spacingL
                        text: "No AI agents found yet.\nAgents show up here once you have used them."
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeMedium
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    Repeater {
                        id: sectionRepeater
                        model: root.sections

                        ProviderSection {
                            required property var modelData
                            required property int index
                            width: column.width
                            provider: modelData
                            providerIndex: index
                        }
                    }

                    StyledText {
                        visible: text !== ""
                        width: parent.width
                        text: root.footerText()
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeSmall
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------ components

    // One subscription: its mark, name, and plan, then its limits.
    component ProviderSection: Column {
        id: section
        property var provider: null
        property int providerIndex: -1
        readonly property var windows: root.displayWindows(provider)
        readonly property bool dragged: root.dragIndex === providerIndex

        spacing: Theme.spacingM
        z: dragged ? 2 : 0
        opacity: dragged ? 0.9 : 1
        transform: Translate {
            y: root.rowShift(section.providerIndex)

            Behavior on y {
                enabled: root.dragIndex >= 0 && !section.dragged
                NumberAnimation {
                    duration: Theme.shorterDuration
                    easing.type: Easing.OutCubic
                }
            }
        }

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.withAlpha(Theme.outlineVariant, 0.6)
        }

        Item {
            id: sectionHead
            width: parent.width
            implicitHeight: Math.max(sectionMark.height, sectionLaunch.visible ? sectionLaunch.height : 0)
            // Lit for the keyboard, and as the drop spot while an agent is dragged.
            readonly property bool lit: root.dragProviderId !== "" ? root.dragTarget === section.providerIndex : root.hasKey("mark", section.providerIndex)
            readonly property bool hasStop: root.hasKey("mark", section.providerIndex) || root.hasKey("launch", section.providerIndex)
            onHasStopChanged: if (hasStop)
                root.revealItem(sectionHead)

            // Only the mark is lit: it is the handle the agent moves by.
            Rectangle {
                anchors.fill: sectionMark
                anchors.margins: -4
                radius: Theme.cornerRadius
                color: sectionHead.lit ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"
            }

            ProviderMark {
                id: sectionMark
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                provider: section.provider

                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    preventStealing: true
                    cursorShape: pressed ? Qt.ClosedHandCursor : Qt.OpenHandCursor
                    onPressed: mouse => root.beginProviderDrag(section.providerIndex, mapToItem(root.content.column, mouse.x, mouse.y).y)
                    onPositionChanged: mouse => {
                        if (pressed)
                            root.dragProviderOver(mapToItem(root.content.column, mouse.x, mouse.y).y);
                    }
                    onReleased: if (!root.settling)
                        root.settleProviderDrag(false)
                    onCanceled: root.settleProviderDrag(true)
                }
            }

            StyledText {
                id: sectionName
                anchors.left: sectionMark.right
                anchors.leftMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, sectionHead.width - sectionMark.width - sectionLaunch.width - Theme.spacingS * 2)
                text: section.provider ? section.provider.providerName : ""
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeMedium
                font.weight: Font.Bold
                color: Theme.surfaceText
                elide: Text.ElideRight
            }

            // The plan reads as part of the name: Claude Code Ultra.
            StyledText {
                id: sectionPlan
                anchors.left: sectionName.right
                anchors.leftMargin: Theme.spacingS
                anchors.right: sectionNote.visible ? sectionNote.left : (sectionLaunch.visible ? sectionLaunch.left : parent.right)
                anchors.rightMargin: Theme.spacingS
                anchors.baseline: sectionName.baseline
                text: root.planLabel(section.provider)
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                elide: Text.ElideRight
            }

            // A mark beside the name when the numbers are not current, with why
            // and what to do on hover.
            DIcon {
                id: sectionNote
                readonly property string message: root.usageNote(section.provider)
                visible: message !== ""
                anchors.right: sectionLaunch.visible ? sectionLaunch.left : parent.right
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                name: "info"
                size: Theme.fontSizeMedium
                color: Theme.surfaceVariantText

                MouseArea {
                    id: noteHover
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton
                }

                DTooltipHost {
                    target: sectionNote
                    hoverArea: noteHover
                    text: sectionNote.message
                    multiline: true
                    side: "top"
                }
            }

            // Opens the agent made for this subscription.
            CursorButton {
                id: sectionLaunch
                visible: root.canLaunch(section.provider)
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                iconName: "terminal"
                tooltipText: section.provider ? "Start " + section.provider.providerName : ""
                hasCursor: root.hasKey("launch", section.providerIndex)
                onEntered: root.pointAt("launch", section.providerIndex)
                onClicked: root.launch(section.provider)
            }
        }

        TextLink {
            visible: root.needsSignIn(section.provider)
            text: "Sign-in required"
            idleColor: Theme.error
            tooltip: section.provider ? "Sign in to " + section.provider.providerName + " again" : ""
            picked: root.hasKey("signin", section.providerIndex)
            onEntered: root.pointAt("signin", section.providerIndex)
            onClicked: root.signIn(section.provider)
        }

        Repeater {
            model: section.windows

            CompactLimit {
                required property var modelData
                width: section.width
                window: modelData
                stale: !!section.provider && section.provider.limitsStale === true
                fetchedAt: section.provider ? Number(section.provider.limitsFetchedAt || 0) : 0
            }
        }

        StyledText {
            visible: text !== ""
            width: parent.width
            text: root.resetCreditsText(section.provider ? section.provider.resetCredits : null)
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }
    }

    // An action button the keyboard cursor can land on.
    component CursorButton: DActionButton {
        property bool hasCursor: false
        iconSize: Theme.iconSize - 4
        iconColor: hasCursor ? Theme.primary : Theme.surfaceVariantText
        backgroundColor: hasCursor ? Theme.withAlpha(Theme.primary, 0.2) : "transparent"
    }

    // A provider's mark, falling back to the bar glyph when it ships none.
    component ProviderMark: Item {
        id: mark
        property var provider: null
        // Provider objects are rebuilt on every refresh, which churns the
        // candidate array's identity without changing its content; key the
        // walker on the URLs themselves.
        property var candidates: root.markCandidates(provider)
        property string candidatesKey: candidates.join("\n")
        property int candidateIndex: 0
        onCandidatesKeyChanged: candidateIndex = 0

        width: 22
        height: 22

        Image {
            id: markImage
            anchors.fill: parent
            source: mark.candidateIndex < mark.candidates.length ? mark.candidates[mark.candidateIndex] : ""
            sourceSize.width: 44
            sourceSize.height: 44
            fillMode: Image.PreserveAspectFit
            // Advancing source from inside its own status change trips the
            // binding-loop detector; step one tick later.
            onStatusChanged: if (status === Image.Error && mark.candidateIndex < mark.candidates.length)
                Qt.callLater(() => mark.candidateIndex++)
        }

        DIcon {
            anchors.centerIn: parent
            visible: markImage.status !== Image.Ready
            name: "smart_toy"
            size: mark.width
            color: Theme.primary
        }
    }

    // A plain-text control: stands in for bordered buttons, which pile up here.
    component TextLink: StyledText {
        id: link
        signal clicked
        signal entered
        property bool picked: false
        property string tooltip: ""
        property color idleColor: Theme.surfaceVariantText
        readonly property bool hot: linkMouse.containsMouse || picked

        onPickedChanged: if (picked)
            root.revealItem(link)
        color: hot ? Theme.surfaceText : idleColor
        font.pixelSize: Theme.fontSizeSmall
        font.underline: hot

        MouseArea {
            id: linkMouse
            anchors.fill: parent
            anchors.margins: -4
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: link.entered()
            onClicked: link.clicked()
        }

        DTooltipHost {
            target: link
            hoverArea: linkMouse
            text: link.tooltip
        }
    }

    // One line per limit window: title, meter, the share used, and the time
    // until it resets. The row's tooltip adds any model-scoped allowance on the
    // same clock, which is a tick on this row's meter.
    component CompactLimit: Item {
        id: compact
        property var window: null
        // Numbers kept past a failed check say how old they are, on hover.
        property bool stale: false
        property real fetchedAt: 0
        readonly property var scoped: window && window.scoped ? window.scoped : []
        readonly property bool alarming: !!window && window.percent >= 0.9
        readonly property real resetMs: root.resetMsFor(window)

        implicitHeight: Math.max(compactTitle.implicitHeight, compactValue.implicitHeight)

        MouseArea {
            id: compactHover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }

        DTooltipHost {
            target: compact
            hoverArea: compactHover
            text: root.limitTooltip(compact.window, compact.stale, compact.fetchedAt)
            multiline: true
            side: "top"
        }

        StyledText {
            id: compactTitle
            width: parent.width * 0.3
            anchors.verticalCenter: parent.verticalCenter
            text: compact.window ? compact.window.title : ""
            textFormat: Text.PlainText
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceText
            elide: Text.ElideRight
        }

        Meter {
            anchors.left: compactTitle.right
            anchors.right: compactPercent.left
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            value: compact.window ? compact.window.percent : -1
            alarming: compact.alarming
            markers: compact.scoped
        }

        // Sized to the widest time left, so every meter ends in the same place.
        StyledText {
            id: compactValueWidest
            visible: false
            text: "00h 00m"
            font.pixelSize: Theme.fontSizeSmall
        }

        // Sized to the widest share, for the same reason.
        StyledText {
            id: compactPercentWidest
            visible: false
            text: "100%"
            font.pixelSize: Theme.fontSizeSmall
        }

        StyledText {
            id: compactPercent
            width: Math.ceil(compactPercentWidest.implicitWidth)
            anchors.right: compactValue.left
            anchors.rightMargin: Theme.spacingL
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: compact.window ? Math.round(compact.window.percent * 100) + "%" : ""
            font.pixelSize: Theme.fontSizeSmall
            color: compact.alarming ? Theme.error : Theme.surfaceText
        }

        StyledText {
            id: compactValue
            width: Math.ceil(compactValueWidest.implicitWidth)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            text: compact.resetMs > 0 ? root.formatDuration(compact.resetMs) : ""
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }
    }

    // Rounded track showing the percentage of the allowance used.
    component Meter: Item {
        id: meter
        property real value: -1
        property bool alarming: false
        // Other allowances on the same clock, drawn as ticks across the track.
        property var markers: []

        implicitHeight: 6

        Rectangle {
            id: meterTrack
            anchors.fill: parent
            radius: height / 2
            color: Theme.surfaceVariantAlpha
        }

        Rectangle {
            anchors.left: meterTrack.left
            anchors.verticalCenter: meterTrack.verticalCenter
            height: meterTrack.height
            radius: meterTrack.radius
            width: meterTrack.width * root.clamp(meter.value, 0, 1)
            color: meter.alarming ? Theme.error : Theme.primary

            Behavior on width {
                NumberAnimation {
                    duration: Theme.shortDuration
                    easing.type: Theme.standardEasing
                }
            }
        }

        Repeater {
            model: meter.markers

            Rectangle {
                required property var modelData
                width: 3
                height: meter.height * 2.5
                radius: width / 2
                anchors.verticalCenter: meterTrack.verticalCenter
                x: root.clamp(meterTrack.width * root.clamp(Number(modelData.percent), 0, 1) - width / 2, 0, meterTrack.width - width)
                color: meter.alarming ? Theme.error : Theme.surfaceText
            }
        }
    }
}
