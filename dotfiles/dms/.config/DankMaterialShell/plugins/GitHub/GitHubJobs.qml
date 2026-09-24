import QtQuick
import qs.Common
import qs.Widgets
import "GitHubLogic.js" as Logic

// A run's jobs as github.com's run page lists them: each job folds open
// into its steps, and each step of a finished job into its log, styled
// like github.com's (groups in bold, commands in the accent, errors and
// warnings in their colors, the last `logTail` lines until asked for all).
// A job opens by default when it failed, when it runs, or when it is the
// only one, and a failed step of a finished job opens with its log. What is
// open is kept here by job id, not in the rows, so the reload of a running
// run (every ten seconds) leaves it as it was. The split into steps goes by
// time and is a best effort (Logic.splitJobLog), which the job says under
// its steps, next to its whole log.
GitHubCard {
    id: jobsCard

    // The GitHubDetail this sits on, and the run's jobs from its load.
    property var page: null
    property var jobs: []

    readonly property var github: page ? page.github : null
    readonly property var item: page ? page.item : null
    readonly property int logTail: 400

    property var openJobs: ({})
    property var openSteps: ({})
    // Steps (and whole jobs) showing their whole log rather than its end.
    property var fullSteps: ({})
    // Jobs showing their whole log instead of per step.
    property var wholeJobs: ({})
    // Job id -> { loading, error, log }: a log this card shows is its own,
    // so the data layer's small cache dropping it (for a seventh job, or
    // another window's) takes nothing off the screen.
    property var logState: ({})
    // A finished job's log never changes, so each part's rich text is made
    // once: "job:step:whole" -> html.
    property var htmlCache: ({})

    visible: jobs.length > 0

    onItemChanged: clear()

    // Another account's answers are dropped: a log on its way stops
    // waiting, and the page starts over.
    Connections {
        target: jobsCard.github
        function onAccountSwitched() {
            jobsCard.clear();
        }
    }

    function clear() {
        openJobs = {};
        openSteps = {};
        fullSteps = {};
        wholeJobs = {};
        logState = {};
        htmlCache = {};
    }

    function jobKey(job) {
        return String(job.databaseId);
    }

    function jobFinished(job) {
        return String(job.status) === "completed";
    }

    function jobOpen(job) {
        const key = jobKey(job);
        if (openJobs[key] !== undefined)
            return openJobs[key];
        const outcome = Logic.outcome(job.status, job.conclusion);
        return jobs.length === 1 || outcome === "failure" || outcome === "running";
    }

    function toggleJob(job) {
        openJobs = Logic.withKey(openJobs, jobKey(job), !jobOpen(job));
    }

    function stepKey(job, step) {
        return jobKey(job) + ":" + step.number;
    }

    function stepHasLog(job, step) {
        return jobFinished(job) && step.conclusion !== "skipped" && !!step.startedAt;
    }

    function stepOpen(job, step) {
        if (!stepHasLog(job, step))
            return false;
        const key = stepKey(job, step);
        if (openSteps[key] !== undefined)
            return openSteps[key];
        return Logic.outcome(step.status, step.conclusion) === "failure";
    }

    function toggleStep(job, step) {
        if (stepHasLog(job, step))
            openSteps = Logic.withKey(openSteps, stepKey(job, step), !stepOpen(job, step));
    }

    // Loads a finished job's log once; the rows that show it ask.
    function ensureLog(job) {
        const key = jobKey(job);
        const state = logState[key];
        if (!github || !item || !jobFinished(job) || (state && (state.loading || state.log)))
            return;
        logState = Logic.withKey(logState, key, {
            "loading": true,
            "error": "",
            "log": null
        });
        github.loadJobLog(item.repo, job, (log, error) => {
            jobsCard.logState = Logic.withKey(jobsCard.logState, key, {
                "loading": false,
                "error": log ? "" : error,
                "log": log
            });
        }, jobsCard);
    }

    function logHtml(key, lines, whole) {
        const cacheKey = key + ":" + (whole ? "all" : "tail");
        if (htmlCache[cacheKey] === undefined)
            htmlCache[cacheKey] = Logic.logHtml(whole ? lines : lines.slice(-logTail), {
                "command": Theme.primary,
                "error": Theme.error,
                "warning": Theme.warning,
                "muted": Theme.surfaceVariantText
            });
        return htmlCache[cacheKey];
    }

    function headline() {
        const failing = jobs.filter(job => Logic.outcome(job.status, job.conclusion) === "failure").length;
        if (failing > 0)
            return failing + " of " + jobs.length + (jobs.length === 1 ? " job failed" : " jobs failed");
        return jobs.length + (jobs.length === 1 ? " job" : " jobs");
    }

    // The shell's text rendering, read off its own text item for the logs
    // (a TextEdit, which StyledText is not).
    StyledText {
        id: themeText
        visible: false
    }

    GitHubCardHeader {
        icon: "account_tree"
        title: jobsCard.jobs.length > 0 ? jobsCard.headline() : ""
    }

    Repeater {
        model: jobsCard.jobs

        Column {
            id: jobColumn
            required property var modelData
            readonly property string key: jobsCard.jobKey(modelData)
            readonly property string outcome: Logic.outcome(modelData.status, modelData.conclusion)
            readonly property bool open: jobsCard.jobOpen(modelData)
            readonly property bool finished: jobsCard.jobFinished(modelData)
            readonly property bool whole: !!jobsCard.wholeJobs[key]
            readonly property var steps: (modelData.steps || []).slice().sort((a, b) => a.number - b.number)
            readonly property var log: jobsCard.logState[key] ? jobsCard.logState[key].log : null
            width: parent.width
            spacing: 0

            FoldRow {
                open: jobColumn.open
                outcome: jobColumn.outcome
                label: String(jobColumn.modelData.name || "job")
                caption: Logic.duration(jobColumn.modelData.startedAt, jobColumn.outcome === "running" ? "" : jobColumn.modelData.completedAt)
                externalUrl: String(jobColumn.modelData.url || "")
                onToggled: jobsCard.toggleJob(jobColumn.modelData)
            }

            Column {
                visible: jobColumn.open
                x: Theme.spacingL
                width: parent.width - x
                spacing: 0

                Repeater {
                    model: jobColumn.open && !jobColumn.whole ? jobColumn.steps : []

                    Column {
                        id: stepColumn
                        required property var modelData
                        readonly property string outcome: Logic.outcome(modelData.status, modelData.conclusion)
                        readonly property bool open: jobsCard.stepOpen(jobColumn.modelData, modelData)
                        readonly property var lines: jobColumn.log && jobColumn.log.steps[modelData.number] ? jobColumn.log.steps[modelData.number] : []
                        width: parent.width
                        spacing: 0

                        FoldRow {
                            small: true
                            foldable: jobsCard.stepHasLog(jobColumn.modelData, stepColumn.modelData)
                            open: stepColumn.open
                            outcome: stepColumn.outcome
                            label: String(stepColumn.modelData.name || "")
                            caption: stepColumn.modelData.conclusion === "skipped" || !stepColumn.modelData.startedAt ? "" : Logic.duration(stepColumn.modelData.startedAt, stepColumn.outcome === "running" ? "" : stepColumn.modelData.completedAt)
                            onToggled: jobsCard.toggleStep(jobColumn.modelData, stepColumn.modelData)
                        }

                        LogBox {
                            visible: stepColumn.open
                            job: jobColumn.modelData
                            partKey: jobsCard.stepKey(jobColumn.modelData, stepColumn.modelData)
                            log: jobColumn.log
                            lines: stepColumn.lines
                        }
                    }
                }

                // The whole log, for when the split into steps is off.
                LogBox {
                    visible: jobColumn.open && jobColumn.whole
                    job: jobColumn.modelData
                    partKey: jobColumn.key + ":job"
                    log: jobColumn.log
                    lines: jobColumn.log ? jobColumn.log.all : []
                }

                GitHubLinkRow {
                    visible: jobColumn.finished && jobColumn.steps.length > 0
                    icon: jobColumn.whole ? "view_list" : "article"
                    text: jobColumn.whole ? "Show the log by step" : "Show the whole job log"
                    note: jobColumn.whole ? "" : "steps are split by time"
                    action: () => {
                        jobsCard.wholeJobs = Logic.withKey(jobsCard.wholeJobs, jobColumn.key, !jobColumn.whole);
                        if (!jobColumn.whole)
                            jobsCard.ensureLog(jobColumn.modelData);
                    }
                }

                // GitHub keeps a running job's log to its own page until
                // the job finishes.
                Row {
                    visible: !jobColumn.finished && jobColumn.outcome !== "queued"
                    height: 28
                    spacing: Theme.spacingXS

                    DankIcon {
                        anchors.verticalCenter: parent.verticalCenter
                        name: "info"
                        size: Theme.iconSizeSmall - 2
                        color: Theme.surfaceVariantText
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Logs arrive when the job finishes."
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                    }

                    GitHubLinkText {
                        page: jobsCard.page
                        anchors.verticalCenter: parent.verticalCenter
                        text: "Watch it live on GitHub"
                        url: String(jobColumn.modelData.url || "")
                        external: true
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.primary
                    }
                }

                StyledText {
                    visible: jobColumn.steps.length === 0
                    height: 28
                    verticalAlignment: Text.AlignVCenter
                    text: jobColumn.outcome === "queued" ? "Waiting for a runner…" : "No steps."
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }
            }
        }
    }

    // Log lines of a step or a whole job, loaded with the job's log when it
    // first shows.
    component LogBox: Rectangle {
        id: logBox

        property var job: ({})
        property string partKey: ""
        property var log: null
        property var lines: []
        readonly property var load: jobsCard.logState[jobsCard.jobKey(job)] || ({})
        readonly property bool whole: !!jobsCard.fullSteps[partKey]

        onVisibleChanged: {
            if (visible)
                jobsCard.ensureLog(job);
        }
        Component.onCompleted: {
            if (visible)
                jobsCard.ensureLog(job);
        }

        width: parent ? parent.width : 0
        height: logColumn.implicitHeight + Theme.spacingS * 2
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceText, 0.05)
        border.width: 1
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.4)

        Column {
            id: logColumn
            x: Theme.spacingS
            y: Theme.spacingS
            width: parent.width - Theme.spacingS * 2
            spacing: Theme.spacingXS

            StyledText {
                visible: !logBox.log
                width: parent.width
                text: logBox.load.error ? logBox.load.error : "Loading the log…"
                font.pixelSize: Theme.fontSizeSmall
                color: logBox.load.error ? Theme.error : Theme.surfaceVariantText
                wrapMode: Text.Wrap
            }

            GitHubLinkRow {
                visible: !!logBox.log && !logBox.whole && logBox.lines.length > jobsCard.logTail
                icon: "unfold_more"
                text: "Show all " + logBox.lines.length + " lines (the last " + jobsCard.logTail + " are shown)"
                action: () => jobsCard.fullSteps = Logic.withKey(jobsCard.fullSteps, logBox.partKey, true)
            }

            StyledText {
                visible: !!logBox.log && logBox.lines.length === 0
                text: "No output."
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }

            GitHubTextView {
                visible: !!logBox.log && logBox.lines.length > 0
                width: parent.width
                renderProbe: themeText
                isMonospace: true
                selectByMouse: true
                textFormat: TextEdit.RichText
                wrapMode: TextEdit.WrapAnywhere
                font.pixelSize: Theme.fontSizeSmall - 1
                text: visible ? jobsCard.logHtml(logBox.partKey, logBox.lines, logBox.whole) : ""
            }
        }
    }

    // A row that folds what is under it open (a job's steps, a step's log):
    // the chevron, the outcome, the name, and how long it took; a job's row
    // also opens its page on GitHub.
    component FoldRow: Rectangle {
        id: foldRow
        property bool open: false
        property bool foldable: true
        property bool small: false
        property string outcome: ""
        property string label: ""
        property string caption: ""
        property string externalUrl: ""
        signal toggled()

        width: parent ? parent.width : 0
        height: small ? 26 : 30
        radius: Theme.cornerRadius
        color: foldArea.containsMouse && foldable ? Theme.withAlpha(Theme.surfaceText, 0.06) : "transparent"

        DankIcon {
            id: chevron
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingXS
            anchors.verticalCenter: parent.verticalCenter
            name: foldRow.open ? "expand_more" : "chevron_right"
            size: Theme.iconSizeSmall
            color: Theme.surfaceVariantText
            opacity: foldRow.foldable ? 1 : 0
        }

        GitHubStatusIcon {
            id: foldIcon
            anchors.left: chevron.right
            anchors.leftMargin: Theme.spacingXS
            anchors.verticalCenter: parent.verticalCenter
            outcome: foldRow.outcome
            size: foldRow.small ? Theme.iconSizeSmall - 2 : Theme.iconSizeSmall
        }

        StyledText {
            anchors.left: foldIcon.right
            anchors.leftMargin: Theme.spacingS
            anchors.right: foldCaption.left
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            text: foldRow.label
            textFormat: Text.PlainText
            font.pixelSize: foldRow.small ? Theme.fontSizeSmall : Theme.fontSizeMedium
            color: foldRow.foldable || !foldRow.small ? Theme.surfaceText : Theme.surfaceVariantText
            elide: Text.ElideRight
        }

        StyledText {
            id: foldCaption
            anchors.right: foldExternal.visible ? foldExternal.left : parent.right
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            text: foldRow.caption
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
        }

        MouseArea {
            id: foldArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: foldRow.foldable ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                if (foldRow.foldable)
                    foldRow.toggled();
            }
        }

        DankActionButton {
            id: foldExternal
            visible: foldRow.externalUrl !== ""
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            buttonSize: 24
            iconName: "open_in_new"
            iconSize: 14
            iconColor: Theme.surfaceVariantText
            tooltipText: "Open the job on GitHub"
            onClicked: jobsCard.page.openExternally(foldRow.externalUrl)
        }
    }
}
