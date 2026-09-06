import QtQuick
import qs.Common
import qs.Widgets
import qs.Modules.Plugins

// One bar pill and one popout for every coding-agent subscription on the
// machine: rate-limit meters with reset countdowns, tokens per day for the
// last week, and the all-time token split by model. Everything shown comes
// from the records UsageModel discovers; nothing here talks to an endpoint.
PluginComponent {
    id: root

    property var popoutService: null

    readonly property string pluginPath: pluginService && pluginId ? String(pluginService.getPluginPath(pluginId) || "") : ""

    readonly property var providers: usage.enabledProviders
    // The selection follows the provider, not the slot it happens to sit in:
    // a provider whose first scan lands while the popout is open would
    // otherwise shift the list underneath the reader.
    property string selectedProviderId: ""
    readonly property int providerIndex: {
        for (let i = 0; i < providers.length; i++)
            if (providers[i].providerId === selectedProviderId)
                return i;
        return 0;
    }
    readonly property var provider: providers.length > 0 ? providers[providerIndex] : null

    // Countdowns read this instead of Date.now() so the popout keeps telling
    // the truth while it sits open.
    property double nowMs: Date.now()

    readonly property var limits: limitWindows(provider)
    readonly property var models: modelRows(provider)
    // The bar speaks for every subscription, not just the selected tab: the
    // fullest window anywhere is the one about to stop a prompt.
    readonly property var pillWindow: worstWindow(providers)
    readonly property bool alarming: !!pillWindow && pillWindow.percent >= 0.9
    readonly property string pillText: pillWindow ? Math.round(pillWindow.percent * 100) + "%" : ""

    // Nothing to report, nothing in the bar: the pill collapses to zero
    // width until the first scan finds usage, and stays away entirely on a
    // machine that has never run a coding agent.
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

    function selectProvider(index) {
        if (providers.length === 0)
            return;
        const wrapped = ((index % providers.length) + providers.length) % providers.length;
        selectedProviderId = providers[wrapped].providerId;
    }

    function refreshNow() {
        usage.refreshAll(true);
    }

    // ---------------------------------------------------------------- limits
    //
    // Every collector titles each limit after its window ("Session",
    // "Weekly", or a model-scoped name), so nothing here reads a window back
    // out of free text. A record without a title falls back to its label
    // minus any parenthetical.
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
            const label = String(entry.label || "").replace(/\s*\(.*\)\s*/, "").trim();
            out.push({
                title: String(entry.title || "") !== "" ? String(entry.title) : (label === "" ? "Limit" : label),
                percent: percent,
                resetAt: String(entry.resetsAt || "")
            });
        }
        return out;
    }

    // The window that decides how much room is left: the fullest one, since
    // that is what stops the next prompt. Across providers the pill shows
    // whichever agent is closest to its ceiling.
    function fullestWindow(windows, best) {
        for (let i = 0; i < windows.length; i++) {
            if (!best || windows[i].percent > best.percent)
                best = windows[i];
        }
        return best;
    }

    function worstWindow(list) {
        let best = null;
        for (let i = 0; i < list.length; i++)
            best = fullestWindow(limitWindows(list[i]), best);
        return best;
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

    // ---------------------------------------------------------------- content

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

    // The plan you pay for, under the name of the tool it pays for.
    function heroMeta(p) {
        if (!p)
            return "";
        if (String(p.usageStatusText || "") !== "")
            return p.usageStatusText;
        const tier = String(p.tierLabel || "");
        if (tier === "")
            return "Subscription";
        return tier.charAt(0).toUpperCase() + tier.slice(1);
    }

    // Local calendar date, recomputed from nowMs so a popout left open
    // across midnight moves the "Today" row with the clock.
    function todayDate() {
        return usage.dateString(new Date(root.nowMs));
    }

    function dayName(date) {
        const parsed = new Date(String(date || "") + "T00:00:00");
        if (isNaN(parsed.getTime()))
            return String(date || "");
        return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()];
    }

    function todayCaption(p) {
        if (!p)
            return "";
        return "Today: " + Number(p.todayPrompts || 0) + " prompts in " + Number(p.todaySessions || 0) + " sessions";
    }

    function allTimeCaption(p) {
        if (!p)
            return "";
        const parts = [];
        if (Number(p.totalPrompts || 0) > 0)
            parts.push(Number(p.totalPrompts) + " prompts");
        if (Number(p.activeDays || 0) > 0)
            parts.push(Number(p.activeDays) + " active days");
        return parts.length > 0 ? "All time: " + parts.join(", ") : "";
    }

    function weekPeak(p) {
        const days = p ? (p.recentDays || []) : [];
        let peak = 0;
        for (let i = 0; i < days.length; i++)
            peak = Math.max(peak, Number(days[i].messageCount || 0));
        return peak;
    }

    function modelRows(p) {
        const usageByModel = p ? (p.modelUsage || {}) : {};
        const rows = [];
        for (const id in usageByModel) {
            const bucket = usageByModel[id] || {};
            const input = Number(bucket.inputTokens || 0);
            const output = Number(bucket.outputTokens || 0);
            const cacheRead = Number(bucket.cacheReadInputTokens || 0);
            const cacheWrite = Number(bucket.cacheCreationInputTokens || 0);
            rows.push({
                name: usage.friendlyModelName(id),
                total: input + output + cacheRead + cacheWrite,
                input: input,
                output: output,
                cacheRead: cacheRead,
                cacheWrite: cacheWrite
            });
        }
        rows.sort(function (a, b) {
            return b.total - a.total;
        });
        return rows.slice(0, 4);
    }

    function modelDetail(row) {
        if (!row)
            return "";
        return "in " + usage.formatTokenCount(row.input) + " · out " + usage.formatTokenCount(row.output) + " · cache " + usage.formatTokenCount(row.cacheRead + row.cacheWrite);
    }

    // Only speaks up when the numbers cover more than this machine.
    function footerText() {
        if (usage.syncStatusText !== "")
            return usage.syncStatusText;
        if (provider && provider.syncEnabled && provider.syncDeviceCount > 0)
            return "Merged from " + provider.syncDeviceCount + " device" + (provider.syncDeviceCount === 1 ? "" : "s");
        return "";
    }

    // ------------------------------------------------------------------- bar

    pillRightClickAction: () => root.refreshNow()

    horizontalBarPill: Component {
        Row {
            spacing: Theme.spacingXS

            DankIcon {
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

            DankIcon {
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
        // No header: the hero row names the provider and carries the
        // refresh action, and Esc or a click outside closes the popout.
        PopoutComponent {
            id: popout

            // Opening the popout wants fresh limits; the countdowns tick only
            // while it is visible.
            Connections {
                target: popout.parentPopout
                function onShouldBeVisibleChanged() {
                    if (popout.parentPopout.shouldBeVisible) {
                        root.nowMs = Date.now();
                        usage.refreshLimits();
                    }
                }
            }

            Timer {
                interval: 30000
                running: popout.parentPopout ? popout.parentPopout.shouldBeVisible : false
                repeat: true
                onTriggered: root.nowMs = Date.now()
            }

            DankFlickable {
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
                    spacing: Theme.spacingM

                    // ---------- Hero: mark · name · plan · refresh ----------
                    Row {
                        id: heroRow
                        visible: !!root.provider
                        width: parent.width
                        spacing: Theme.spacingM

                        Item {
                            id: heroTile
                            width: 40
                            height: 40
                            anchors.verticalCenter: parent.verticalCenter

                            // Provider objects are rebuilt on every refresh, which
                            // churns the candidate array's identity without changing
                            // its content; key the walker on the URLs themselves.
                            property var candidates: root.markCandidates(root.provider)
                            property string candidatesKey: candidates.join("\n")
                            property int candidateIndex: 0
                            onCandidatesKeyChanged: candidateIndex = 0

                            Image {
                                id: heroMark
                                anchors.centerIn: parent
                                width: 32
                                height: 32
                                source: heroTile.candidateIndex < heroTile.candidates.length ? heroTile.candidates[heroTile.candidateIndex] : ""
                                sourceSize.width: 64
                                sourceSize.height: 64
                                fillMode: Image.PreserveAspectFit
                                // Advancing source from inside its own status change
                                // trips the binding-loop detector; step one tick later.
                                onStatusChanged: if (status === Image.Error && heroTile.candidateIndex < heroTile.candidates.length)
                                    Qt.callLater(function() { heroTile.candidateIndex++; })
                            }

                            DankIcon {
                                anchors.centerIn: parent
                                visible: heroMark.status !== Image.Ready
                                name: "smart_toy"
                                size: Theme.iconSize
                                color: Theme.primary
                            }
                        }

                        Column {
                            width: heroRow.width - heroTile.width - heroRefresh.width - 2 * heroRow.spacing
                            spacing: 2
                            anchors.verticalCenter: parent.verticalCenter

                            StyledText {
                                width: parent.width
                                text: root.provider ? root.provider.providerName : ""
                                font.pixelSize: Theme.fontSizeLarge
                                font.weight: Font.Bold
                                color: Theme.surfaceText
                                elide: Text.ElideRight
                            }

                            StyledText {
                                width: parent.width
                                text: root.heroMeta(root.provider)
                                font.pixelSize: Theme.fontSizeSmall
                                color: Theme.surfaceVariantText
                                elide: Text.ElideRight
                            }
                        }

                        DankActionButton {
                            id: heroRefresh
                            anchors.verticalCenter: parent.verticalCenter
                            iconName: "refresh"
                            iconSize: Theme.iconSize - 4
                            iconColor: Theme.surfaceVariantText
                            onClicked: root.refreshNow()
                        }
                    }

                    StyledText {
                        visible: root.providers.length === 0
                        width: parent.width
                        topPadding: Theme.spacingL
                        bottomPadding: Theme.spacingL
                        text: "No coding-agent subscriptions found yet.\nAgents show up here once you have used them."
                        color: Theme.surfaceVariantText
                        font.pixelSize: Theme.fontSizeMedium
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                    }

                    // ---------- Provider switch ----------
                    Row {
                        id: providerSwitch
                        visible: root.providers.length > 1
                        width: parent.width
                        spacing: Theme.spacingS

                        readonly property real cellWidth: root.providers.length > 0 ? (width - spacing * (root.providers.length - 1)) / root.providers.length : 0

                        Repeater {
                            model: root.providers

                            Rectangle {
                                required property var modelData
                                required property int index

                                readonly property bool selected: index === root.providerIndex

                                width: providerSwitch.cellWidth
                                height: 32
                                radius: Theme.cornerRadius
                                color: selected ? Theme.primary : (chipArea.containsMouse ? Theme.surfaceContainerHighest : Theme.surfaceContainerHigh)

                                StyledText {
                                    anchors.centerIn: parent
                                    text: parent.modelData.providerName
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: parent.selected ? Font.Medium : Font.Normal
                                    color: parent.selected ? Theme.primaryText : Theme.surfaceText
                                }

                                MouseArea {
                                    id: chipArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.selectProvider(parent.index)
                                }
                            }
                        }
                    }

                    // ---------- Status ----------
                    Rectangle {
                        visible: !!root.provider && String(root.provider.usageStatusText || "") !== "" && String(root.provider.authHelpText || "") !== ""
                        width: parent.width
                        implicitHeight: statusText.implicitHeight + Theme.spacingM * 2
                        radius: Theme.cornerRadius
                        color: Theme.withAlpha(Theme.error, 0.10)
                        border.width: 1
                        border.color: Theme.withAlpha(Theme.error, 0.35)

                        StyledText {
                            id: statusText
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.leftMargin: Theme.spacingM
                            anchors.rightMargin: Theme.spacingM
                            text: root.provider ? String(root.provider.authHelpText || "") : ""
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            wrapMode: Text.WordWrap
                        }
                    }

                    // ---------- Limits ----------
                    Column {
                        id: limitsSection
                        visible: root.limits.length > 0
                        width: parent.width
                        spacing: Theme.spacingS

                        SectionHeader {
                            text: "LIMITS"
                        }

                        Repeater {
                            model: root.limits

                            LimitRow {
                                required property var modelData
                                width: limitsSection.width
                                window: modelData
                            }
                        }
                    }

                    // ---------- Tokens by day ----------
                    Column {
                        id: usageSection
                        visible: !!root.provider && root.provider.recentDays && root.provider.recentDays.length > 0
                        width: parent.width
                        spacing: Theme.spacingS

                        readonly property var days: root.provider ? (root.provider.recentDays || []) : []
                        readonly property real peak: Math.max(1, root.weekPeak(root.provider))

                        SectionHeader {
                            text: "TOKENS BY DAY"
                        }

                        Repeater {
                            model: usageSection.days

                            DayRow {
                                required property var modelData
                                required property int index

                                width: usageSection.width
                                day: modelData
                                ratio: Number(modelData.messageCount || 0) / usageSection.peak
                                // By date, not by position: a fallback source
                                // can hand over a window that stops short of today.
                                today: String(modelData.date || "") === root.todayDate()
                            }
                        }

                        StyledText {
                            visible: text !== ""
                            width: parent.width
                            text: root.todayCaption(root.provider)
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
                        }
                    }

                    // ---------- Tokens by model ----------
                    Column {
                        id: modelSection
                        visible: root.models.length > 0
                        width: parent.width
                        spacing: Theme.spacingS

                        SectionHeader {
                            text: "TOKENS BY MODEL"
                        }

                        Repeater {
                            model: root.models

                            ModelRow {
                                required property var modelData
                                width: modelSection.width
                                row: modelData
                                // Scaled to the heaviest model, so the top
                                // row is always full.
                                share: modelData.total / Math.max(1, root.models[0].total)
                            }
                        }

                        StyledText {
                            visible: text !== ""
                            width: parent.width
                            text: root.allTimeCaption(root.provider)
                            color: Theme.surfaceVariantText
                            font.pixelSize: Theme.fontSizeSmall
                            elide: Text.ElideRight
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

    component SectionHeader: StyledText {
        width: parent.width
        font.pixelSize: Theme.fontSizeSmall
        font.weight: Font.Medium
        font.letterSpacing: 1
        color: Theme.surfaceVariantText
    }

    // Rounded track showing the percentage of the allowance used.
    component Meter: Item {
        id: meter
        property real value: -1
        property bool alarming: false
        property color fillColor: alarming ? Theme.error : Theme.primary

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
            color: meter.fillColor

            Behavior on width {
                NumberAnimation {
                    duration: Theme.shortDuration
                    easing.type: Theme.standardEasing
                }
            }
        }
    }

    // A limit window: title and percentage, meter, and reset countdown.
    component LimitRow: Column {
        id: limitRow
        property var window: null

        readonly property bool alarming: !!window && window.percent >= 0.9

        spacing: Theme.spacingXS

        Item {
            width: parent.width
            implicitHeight: Math.max(limitLabel.implicitHeight, limitValue.implicitHeight)

            StyledText {
                id: limitLabel
                text: limitRow.window ? limitRow.window.title : ""
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                elide: Text.ElideRight
                anchors.left: parent.left
                anchors.right: limitValue.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
            }

            StyledText {
                id: limitValue
                text: limitRow.window && limitRow.window.percent >= 0 ? Math.round(limitRow.window.percent * 100) + "%" : "—"
                color: limitRow.alarming ? Theme.error : Theme.surfaceText
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.Medium
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        Meter {
            width: parent.width
            value: limitRow.window ? limitRow.window.percent : -1
            alarming: limitRow.alarming
        }

        StyledText {
            width: parent.width
            text: {
                const remainingMs = root.resetMsFor(limitRow.window);
                return remainingMs > 0 ? "Resets in " + root.formatDuration(remainingMs) : "";
            }
            visible: text !== ""
            color: Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
        }
    }

    // One row per day: label, bar, tokens. Today is picked out in full
    // foreground so the week reads as a run-up to right now.
    component DayRow: Item {
        id: dayRow
        property var day: null
        property real ratio: 0
        property bool today: false

        implicitHeight: Math.max(dayLabel.implicitHeight, dayValue.implicitHeight) + Theme.spacingXS

        StyledText {
            id: dayLabel
            text: dayRow.today ? "Today" : root.dayName(dayRow.day ? dayRow.day.date : "")
            color: dayRow.today ? Theme.surfaceText : Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            font.weight: dayRow.today ? Font.Bold : Font.Normal
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: 48
        }

        Meter {
            anchors.left: dayLabel.right
            anchors.right: dayValue.left
            anchors.leftMargin: Theme.spacingS
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            height: 6
            value: dayRow.ratio
            fillColor: dayRow.today ? Theme.primary : Theme.withAlpha(Theme.primary, 0.55)
        }

        StyledText {
            id: dayValue
            text: usage.formatTokenCount(dayRow.day ? Number(dayRow.day.messageCount || 0) : 0)
            color: dayRow.today ? Theme.surfaceText : Theme.surfaceVariantText
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.Medium
            horizontalAlignment: Text.AlignRight
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 52
        }
    }

    // Model rows read as a table: the share bar fills the row behind the
    // label instead of stacking under it, which keeps the whole dashboard
    // on one screen. The input/output/cache split rides along as a caption.
    component ModelRow: Item {
        id: modelRow
        property var row: null
        property real share: 0

        implicitHeight: modelText.implicitHeight + Theme.spacingM

        Rectangle {
            anchors.fill: parent
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.surfaceText, 0.05)
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: parent.width * root.clamp(modelRow.share, 0, 1)
            radius: Theme.cornerRadius
            color: Theme.withAlpha(Theme.primary, 0.18)

            Behavior on width {
                NumberAnimation {
                    duration: Theme.shortDuration
                    easing.type: Theme.standardEasing
                }
            }
        }

        Column {
            id: modelText
            spacing: 1
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingS
            anchors.right: modelTokens.left
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter

            StyledText {
                width: parent.width
                text: modelRow.row ? modelRow.row.name : ""
                color: Theme.surfaceText
                font.pixelSize: Theme.fontSizeMedium
                elide: Text.ElideRight
            }

            StyledText {
                width: parent.width
                text: root.modelDetail(modelRow.row)
                color: Theme.surfaceVariantText
                font.pixelSize: Theme.fontSizeSmall
                elide: Text.ElideRight
            }
        }

        StyledText {
            id: modelTokens
            text: modelRow.row ? usage.formatTokenCount(modelRow.row.total) : ""
            color: Theme.surfaceText
            font.pixelSize: Theme.fontSizeMedium
            font.weight: Font.Medium
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
        }
    }
}
