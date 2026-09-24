import QtQuick
import qs.Common
import qs.Services
import qs.Widgets
import "GitHubLogic.js" as Logic

// The page behind one row: the pull request or issue (queries/detail.graphql,
// one request) or the run (`gh run view`), the changes that make sense for
// its state, and a comment box. A change that cannot be taken back with one
// click (merge, close, cancel) asks for a second click first. Escape,
// Backspace, or Left goes back to the list, Enter opens the page on GitHub,
// Ctrl+Enter in the comment box posts. The conversation is GitHubPost, a
// run's jobs GitHubJobs.
Item {
    id: detailPage

    property var item: null
    property var github: null
    // True while the popout shows this page; a running workflow is polled
    // only then.
    property bool active: false

    signal back()
    signal editingFinished()
    signal closeRequested()
    // A linked pull request, issue, or run to open in place of this page.
    signal openItem(var item)
    // A link that is a search of a repository's lists (a label, an issues
    // or pulls page with a query), for the panel to show there.
    signal searchRequested(string repo, string tab, string terms)

    // The page's own load: gh's view of a run, or Logic.normalizeDetail's
    // page of a pull request or issue.
    property var detail: null
    // What the viewer may change here; null until GitHub answers, and no
    // change is offered before it does.
    property var access: null
    // Original image URL -> the signed URL GitHub renders it from.
    property var images: ({})
    // The thread the comment box answers instead of the page: the thread's
    // first comment id, whom it answers, and where.
    property var replyTo: null
    // The conversation shows its latest entries until asked for all.
    property bool showAll: false
    readonly property int shownEntries: 12
    property string loadError: ""
    property bool loading: false
    // The change waiting for its confirming click, "" for none, and the
    // head commit the page showed at the first click, which a merge then
    // insists on.
    property string armed: ""
    property string armedHead: ""
    // Bumped whenever the page shows another item or account: an answer to
    // something asked for before (a change, an assignment) leaves this page
    // alone.
    property int generation: 0
    // Set while the comment box takes a page's draft, which is not a change
    // to save.
    property bool restoring: false

    readonly property bool editing: commentBox.getActiveFocus() || assigneeMenu.open
    // Close and reopen post what is written first, but never a reply: that
    // belongs to its thread.
    readonly property bool drafting: commentBox.text.trim() !== "" && !replyTo
    readonly property bool canComment: !access || !access.locked || access.canWrite

    readonly property string kind: item ? item.kind : ""
    readonly property string itemUrl: item ? item.url : ""
    readonly property bool isBusy: !!github && itemUrl !== "" && !!github.busy[itemUrl]
    readonly property string busyAction: isBusy ? github.busy[itemUrl] : ""
    readonly property string itemState: detail && detail.state ? String(detail.state) : (item && item.state ? String(item.state) : "OPEN")
    // The row the page opened from, brought up to date by the page's load.
    readonly property var current: {
        if (!item)
            return null;
        if (kind === "run")
            return Object.assign({}, item, detail || {}, {
                "kind": "run"
            });
        return Object.assign({}, item, {
            "state": itemState,
            "isDraft": detail ? !!detail.isDraft : !!item.isDraft,
            "stateReason": detail ? String(detail.stateReason || "") : String(item.stateReason || "")
        });
    }
    readonly property string runOutcome: kind === "run" && current ? Logic.outcome(current.status, current.conclusion) : ""
    readonly property string stateText: current ? Logic.stateLabel(kind, itemState, current.stateReason, !!current.isDraft, runOutcome) : ""

    readonly property var timeline: kind === "run" ? [] : Logic.buildTimeline(detail)
    readonly property var shownTimeline: showAll ? timeline : timeline.slice(-shownEntries)
    readonly property var comments: detail && kind !== "run" ? (detail.comments || []) : []
    readonly property var checks: kind === "pr" && detail ? (detail.checks || []) : []
    readonly property var checksReport: kind === "pr" && detail ? Logic.checksReport(checks, detail.checksState, detail.checksTotal) : null
    readonly property var mergeState: kind === "pr" ? Logic.mergeStatus(detail) : null
    // Each reviewer's standing verdict, as GitHub's sidebar and merge box
    // show it: an approval or a request for changes. A review that only
    // commented says nothing about the merge and is in the conversation.
    readonly property var reviews: kind === "pr" && detail ? (detail.latestReviews || []).filter(r => r.state === "APPROVED" || r.state === "CHANGES_REQUESTED") : []
    readonly property var reviewRequests: kind === "pr" && detail ? (detail.reviewRequests || []) : []
    // Whether the viewer follows this page, as the header's bell shows it;
    // null when it cannot be followed.
    readonly property var subscription: access && access.subscription && access.subscription.can && kind !== "run" ? access.subscription : null

    onItemChanged: start()

    // A page from nothing: its item's own draft (kept by page, so going
    // back, a window taking the page over, or the popout closing loses
    // nothing), then its load.
    function start() {
        generation++;
        detail = null;
        access = null;
        images = {};
        showAll = false;
        loadError = "";
        armed = "";
        assigneeMenu.close();
        flick.contentY = 0;
        const draft = item && github ? github.draftFor(item.url) : null;
        restoring = true;
        replyTo = draft ? draft.replyTo : null;
        commentBox.text = draft ? draft.text : "";
        restoring = false;
        reload();
    }

    // What is written is kept as it is written.
    function keepDraft() {
        if (!restoring && item && github)
            github.saveDraft(item.url, commentBox.text, replyTo);
    }

    onReplyToChanged: keepDraft()

    // Whether an answer still belongs on this page: the page exists and
    // shows the item it was asked for, for the same account.
    function stillHere() {
        const page = detailPage;
        const asked = generation;
        return () => Qt.isQtObject(page) && asked === page.generation;
    }

    // The page from GitHub again. A run page asks what the viewer may do
    // there once (a running run's polls ask only for the run). The same
    // answer leaves what shows as it is, the conversation's posts and a
    // run's open logs included.
    function reload() {
        if (!item)
            return;
        const here = stillHere();
        loading = true;
        // item, not the kind binding, which has not caught up yet when a
        // new item's change handler calls this.
        if (item.kind === "run") {
            github.loadRun(item, (json, error) => {
                if (!here())
                    return;
                loading = false;
                if (json) {
                    if (!github.sameJson(json, detail))
                        detail = json;
                    loadError = "";
                } else {
                    loadError = Logic.failureText(error);
                }
            }, detailPage);
            if (!access)
                github.loadRunAccess(item, answer => {
                    if (here() && answer)
                        access = answer;
                }, detailPage);
            return;
        }
        github.loadDetail(item, (page, error) => {
            if (!here())
                return;
            loading = false;
            if (!page) {
                loadError = Logic.failureText(error);
                return;
            }
            if (!github.sameJson(page.detail, detail))
                detail = page.detail;
            if (!github.sameJson(page.access, access))
                access = page.access;
            if (!github.sameJson(page.images, images))
                images = page.images;
            loadError = "";
        }, detailPage);
    }

    Connections {
        target: detailPage.github
        function onChanged(url) {
            if (url === detailPage.itemUrl)
                reloadSoon.restart();
        }
        // Nothing of the old account's stays on screen, even when the
        // new account cannot load the page.
        function onAccountSwitched() {
            detailPage.start();
        }
    }

    Timer {
        id: reloadSoon
        interval: 2000
        onTriggered: detailPage.reload()
    }

    Timer {
        interval: 10000
        repeat: true
        running: detailPage.active && (detailPage.runOutcome === "running" || detailPage.runOutcome === "queued")
        onTriggered: detailPage.reload()
    }

    Timer {
        id: disarm
        interval: 4000
        onTriggered: detailPage.armed = ""
    }

    // What the popout header shows while this page is open.
    readonly property string headerTitle: {
        if (!item)
            return "";
        if (kind !== "run")
            return "#" + item.number;
        const number = detail ? detail.number : item.number;
        return number ? "Run #" + number : "Run";
    }
    readonly property string headerSubtitle: item ? item.repo : ""

    function metaText() {
        if (!current)
            return "";
        if (kind === "run") {
            const parts = [String(current.event || "")];
            if (Number(current.attempt || 1) > 1)
                parts.push("attempt " + current.attempt);
            parts.push(Logic.when(current.createdAt));
            return parts.filter(p => p !== "").join(" · ");
        }
        // Who opened it, and when, lead the description's own header.
        if (!detail || !detail.commentsTotal)
            return "";
        return detail.commentsTotal + (detail.commentsTotal === 1 ? " comment" : " comments");
    }

    function startReply(thread) {
        const first = thread.comments.nodes[0];
        if (!first)
            return;
        replyTo = {
            "commentId": first.databaseId,
            "login": Logic.loginOf(first),
            "path": String(thread.path || "")
        };
        commentBox.forceActiveFocus();
    }

    function changeThread(thread, action) {
        if (!isBusy)
            github.mutate(Object.assign({}, item), action, "", null, {
                "threadId": thread.id
            });
    }

    // A pull request from a fork has its head branch in the fork.
    function headRepo() {
        return detail && detail.headRepo ? detail.headRepo : (item ? item.repo : "");
    }

    // Every clickable part of the page leads where it does on github.com
    // (Logic's URLs), through here: pull requests, issues, runs, and
    // searches open in place, and the rest in the browser, like a link to
    // a place in a page, which a page here does not scroll to.
    function openLink(url) {
        const search = Logic.parseSearchLink(url, kind === "pr" ? "prs" : "issues");
        if (search) {
            searchRequested(search.repo, search.tab, search.terms);
            return;
        }
        const link = Logic.parseLink(url);
        if (!link || link.anchor) {
            openExternally(url);
            return;
        }
        if (link.kind === "run" ? (kind === "run" && Number(item.databaseId) === link.databaseId) : (kind !== "run" && item.repo === link.repo && Number(item.number) === link.number))
            return;
        const here = stillHere();
        loading = true;
        github.resolveLink(link, (resolved, error) => {
            if (!here())
                return;
            loading = false;
            if (resolved)
                openItem(resolved);
            else
                openExternally(url);
        }, detailPage);
    }

    // Bodies are written by anyone: only web and mail links leave for
    // another app, as on github.com.
    function openExternally(url) {
        const safe = Logic.externalUrl(url);
        if (safe !== "")
            Qt.openUrlExternally(safe);
        else if (String(url || "") !== "")
            ToastService.showWarning("GitHub", "Only web and mail links open from a page.");
    }

    function openOnGitHub() {
        if (!item)
            return;
        Qt.openUrlExternally(item.url);
        closeRequested();
    }

    function copyLink() {
        if (item && github)
            github.copy(item.url, "Copied " + item.url);
    }

    // ------------------------------------------------------------- actions

    // What this page can change, in the order GitHub's own buttons read.
    // tone colors the icon (success for approving and merging, error for
    // what cannot be undone, the accent otherwise); tonal marks the one
    // change the page most likely came for, drawn with a soft fill.
    function actions() {
        // A page opened from a notification does not know its state until
        // it loads, so nothing is offered before then.
        if (!item || !access || (item.stateUnknown && !detail))
            return [];
        const list = [];
        if (kind === "pr" && itemState === "OPEN") {
            const mine = !!detail && detail.author.login === github.login;
            const draft = !!current.isDraft;
            if (access.canClose)
                list.push({
                    "id": "close",
                    "label": drafting ? "Close with comment" : "Close",
                    "icon": "do_not_disturb_on",
                    "tone": "error",
                    "confirm": true
                });
            if (draft && access.canUpdate)
                list.push({
                    "id": "ready",
                    "label": "Ready for review",
                    "icon": "rate_review",
                    "tone": "accent"
                });
            if (!mine)
                list.push({
                    "id": "approve",
                    "label": "Approve",
                    "icon": "check",
                    "tone": "success",
                    "tonal": true
                });
            if (!draft && access.canWrite)
                list.push({
                    "id": "merge",
                    "label": Logic.MERGE_LABELS[access.mergeMethod] || "Merge",
                    "icon": "merge",
                    "tone": "success",
                    "tonal": mine,
                    "confirm": true,
                    "disabled": !!detail && detail.mergeable === "CONFLICTING",
                    "hint": "has conflicts"
                });
        } else if (kind === "issue" && itemState === "OPEN") {
            if (access.canClose)
                list.push({
                    "id": "close",
                    "label": drafting ? "Close with comment" : "Close issue",
                    "icon": "check_circle",
                    "tone": "accent",
                    "confirm": true
                });
        } else if ((kind === "pr" || kind === "issue") && itemState === "CLOSED") {
            if (access.canReopen)
                list.push({
                    "id": "reopen",
                    "label": drafting ? "Reopen with comment" : "Reopen",
                    "icon": "undo",
                    "tone": "success"
                });
        } else if (kind === "run" && access.canWrite) {
            if (runOutcome === "running" || runOutcome === "queued") {
                list.push({
                    "id": "cancel",
                    "label": "Cancel run",
                    "icon": "stop_circle",
                    "tone": "error",
                    "confirm": true
                });
            } else {
                if (runOutcome === "failure" || runOutcome === "cancelled")
                    list.push({
                        "id": "rerunFailed",
                        "label": "Re-run failed jobs",
                        "icon": "replay",
                        "tone": "accent",
                        "tonal": true
                    });
                list.push({
                    "id": "rerun",
                    "label": "Re-run all jobs",
                    "icon": "restart_alt",
                    "tone": "accent"
                });
            }
        }
        return list;
    }

    // A change's tone (success, error, or the accent), as a status glyph's.
    function toneColor(tone) {
        if (tone === "success")
            return Theme.success;
        if (tone === "error")
            return Theme.error;
        return Theme.primary;
    }

    function trigger(action) {
        if (!action || action.disabled || isBusy)
            return;
        if (action.confirm && armed !== action.id) {
            armed = action.id;
            armedHead = detail && detail.headSha ? detail.headSha : "";
            disarm.restart();
            return;
        }
        armed = "";
        const target = Object.assign({}, current);
        const extra = {
            "mergeMethod": access ? access.mergeMethod : "MERGE",
            "headSha": armedHead
        };
        const body = drafting ? commentBox.text.trim() : "";
        if ((action.id === "close" || action.id === "reopen") && body !== "") {
            // The close follows the comment even when the page moves on or
            // its window closes in between: it was asked for. Not when gh
            // switched accounts meanwhile, though: that one never asked.
            const data = github;
            const account = data.accountGen;
            const posted = commentPosted(body, false);
            data.mutate(target, "comment", body, ok => {
                posted(ok);
                if (ok && data.accountGen === account)
                    data.mutate(target, action.id, "", null, extra);
            });
            return;
        }
        github.mutate(target, action.id, "", null, extra);
    }

    // What a posted comment clears: its page's kept draft, and the comment
    // box only while it still shows that page and that text.
    function commentPosted(body, reply) {
        const here = stillHere();
        const data = github;
        const url = item.url;
        return ok => {
            if (!ok)
                return;
            data.clearDraft(url, body);
            if (here() && commentBox.text.trim() === body) {
                commentBox.text = "";
                if (reply)
                    replyTo = null;
            }
        };
    }

    function postComment() {
        const body = commentBox.text.trim();
        if (body === "" || isBusy)
            return;
        if (replyTo) {
            github.mutate(Object.assign({}, item), "reply", body, commentPosted(body, true), {
                "commentId": replyTo.commentId
            });
            return;
        }
        github.mutate(Object.assign({}, item), "comment", body, commentPosted(body, false));
    }

    // Adds or removes one assignee; the page shows the change as soon as
    // GitHub takes it, before the reload that follows every change.
    function setAssigned(login, on) {
        if (!item || !github || !login || isBusy)
            return;
        const here = stillHere();
        const who = login === github.login ? "you" : login;
        github.mutate(item, on ? "assign" : "unassign", "", ok => {
            if (!ok || !here() || !detail)
                return;
            const rest = (detail.assignees || []).filter(person => person.login !== login);
            detail = Object.assign({}, detail, {
                "assignees": on ? rest.concat([
                    {
                        "login": login
                    }
                ]) : rest
            });
        }, {
            "login": login,
            "done": on ? "Assigned " + who + " to" : "Unassigned " + who + " from"
        });
    }

    function toggleSubscription() {
        const was = subscription;
        if (!was || isBusy)
            return;
        if (!github.canSubscribe) {
            github.addNotificationsScope();
            closeRequested();
            return;
        }
        const here = stillHere();
        const state = was.next;
        github.mutate(item, "subscription", "", ok => {
            if (!ok || !here() || !access)
                return;
            // Until the reload says why, the bell only says whether.
            access = Object.assign({}, access, {
                "subscription": Object.assign({}, was, {
                    "on": state === "SUBSCRIBED",
                    "reason": "",
                    "next": state === "SUBSCRIBED" ? "UNSUBSCRIBED" : "SUBSCRIBED"
                })
            });
        }, {
            "id": access.id,
            "state": state,
            "done": state === "SUBSCRIBED" ? "Subscribed to" : "Unsubscribed from"
        });
    }

    // Keys typed while selected text has focus: the page's own.
    function bodyKey(event) {
        if (handleKey(event))
            event.accepted = true;
    }

    function handleKey(event) {
        const control = event.modifiers & Qt.ControlModifier;
        switch (event.key) {
        case Qt.Key_Escape:
        case Qt.Key_Backspace:
        case Qt.Key_Left:
            back();
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            openOnGitHub();
            return true;
        case Qt.Key_R:
            if (!control)
                return false;
            reload();
            return true;
        case Qt.Key_Down:
            flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + 60);
            return true;
        case Qt.Key_Up:
            flick.contentY = Math.max(0, flick.contentY - 60);
            return true;
        case Qt.Key_PageDown:
            flick.contentY = Math.min(Math.max(0, flick.contentHeight - flick.height), flick.contentY + flick.height - 40);
            return true;
        case Qt.Key_PageUp:
            flick.contentY = Math.max(0, flick.contentY - flick.height + 40);
            return true;
        case Qt.Key_C:
            if (kind === "run" || !canComment)
                return false;
            commentBox.forceActiveFocus();
            return true;
        }
        return false;
    }

    // -------------------------------------------------------------- layout
    //
    // One scrolling page under the popout header (which carries the number,
    // the repository, and the page's buttons): the title block, the status
    // cards, and the conversation, with the comment box and the changes
    // pinned below.

    DankFlickable {
        id: flick
        anchors.top: parent.top
        anchors.bottom: composer.visible ? composer.top : parent.bottom
        anchors.bottomMargin: composer.visible ? Theme.spacingS : 0
        width: parent.width
        contentWidth: width
        contentHeight: body.implicitHeight + Theme.spacingM
        clip: true
        // A mouse drag selects text rather than dragging the page; the
        // wheel, the touchpad, touch, and the scroll bar still scroll it.
        acceptedButtons: Qt.NoButton

        Column {
            id: body
            width: flick.width - Theme.spacingS
            spacing: Theme.spacingL

            // ---------- Title block ----------
            Column {
                width: parent.width
                spacing: Theme.spacingS

                StyledText {
                    width: parent.width
                    text: !detailPage.current ? "" : String((detailPage.kind === "run" ? detailPage.current.displayTitle : (detailPage.detail ? detailPage.detail.title : detailPage.current.title)) || "")
                    textFormat: Text.PlainText
                    font.pixelSize: Theme.fontSizeLarge + 2
                    font.weight: Font.Bold
                    lineHeight: 1.15
                    color: Theme.surfaceText
                    wrapMode: Text.Wrap
                }

                // State, author, and age on the left; the assignees on the
                // right, where github.com keeps them in its sidebar.
                Item {
                    width: parent.width
                    height: Math.max(stateFlow.implicitHeight, assigneeBox.height)

                    Flow {
                        id: stateFlow
                        width: parent.width - (assigneeBox.visible ? assigneeBox.width + Theme.spacingM : 0)
                        spacing: Theme.spacingS

                        Rectangle {
                            visible: !!detailPage.detail || !(detailPage.item && detailPage.item.stateUnknown)
                            height: 24
                            width: stateRow.implicitWidth + Theme.spacingM * 2
                            radius: 12
                            color: Theme.withAlpha(stateGlyph.color, 0.16)

                            Row {
                                id: stateRow
                                anchors.centerIn: parent
                                spacing: Theme.spacingXS

                                GitHubStatusIcon {
                                    id: stateGlyph
                                    anchors.verticalCenter: parent.verticalCenter
                                    item: detailPage.current
                                    itemState: detailPage.itemState
                                    size: Theme.iconSizeSmall
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: detailPage.stateText
                                    font.pixelSize: Theme.fontSizeSmall
                                    font.weight: Font.DemiBold
                                    color: stateGlyph.color
                                }
                            }
                        }

                        // The pull requests that close this issue, or the
                        // issues this pull request closes, as github.com
                        // shows them beside the state; each opens here.
                        Repeater {
                            model: detailPage.detail && detailPage.kind !== "run" ? (detailPage.detail.linked || []) : []

                            IssueChip {
                                required property var modelData
                                target: modelData
                                text: Logic.refLabel(modelData, detailPage.item.repo)
                            }
                        }

                        // The issue this one is a sub-issue of.
                        IssueChip {
                            readonly property var parentIssue: detailPage.detail && detailPage.kind === "issue" ? detailPage.detail.parent : null
                            visible: !!parentIssue
                            target: parentIssue
                            text: parentIssue ? "Parent: " + parentIssue.title : ""
                            maxTextWidth: Math.max(80, stateFlow.width - 140)
                        }

                        // Which workflow ran; who opened a pull request or an
                        // issue is in its description's header instead.
                        GitHubLinkText {
                            page: detailPage
                            height: 24
                            verticalAlignment: Text.AlignVCenter
                            visible: detailPage.kind === "run" && text !== ""
                            text: detailPage.kind === "run" && detailPage.current ? String(detailPage.current.workflowName || "") : ""
                            url: detailPage.item ? Logic.workflowUrl(detailPage.item.repo, text) : ""
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                            color: Theme.surfaceText
                        }

                        StyledText {
                            visible: text !== ""
                            height: 24
                            verticalAlignment: Text.AlignVCenter
                            text: detailPage.kind === "run" ? "· " + detailPage.metaText() : detailPage.metaText()
                            textFormat: Text.PlainText
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    // "Assigned to" the first assignee ("you" when that is
                    // the viewer), the rest as a count; spelled out, since a
                    // name alone reads as a second author. Whoever may
                    // assign gets github.com's "Assign yourself" when no one
                    // is, and the picker (GitHubAssigneeMenu) behind the pen.
                    Row {
                        id: assigneeBox
                        readonly property var assignees: detailPage.detail && detailPage.kind !== "run" ? (detailPage.detail.assignees || []) : []
                        readonly property string first: assignees.length > 0 ? String(assignees[0].login) : ""
                        readonly property bool canAssign: !!detailPage.detail && detailPage.kind !== "run" && !!detailPage.access && detailPage.access.canAssign
                        visible: assignees.length > 0 || canAssign
                        anchors.right: parent.right
                        height: 24
                        spacing: Theme.spacingXS

                        DankIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "assignment_ind"
                            size: Theme.iconSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: assigneeBox.assignees.length > 0 ? "Assigned to" : "No one ·"
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        GitHubLinkText {
                            page: detailPage
                            visible: assigneeBox.assignees.length === 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: "Assign yourself"
                            action: () => detailPage.setAssigned(detailPage.github.login, true)
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                            color: Theme.primary
                        }

                        GitHubLinkText {
                            page: detailPage
                            visible: assigneeBox.assignees.length > 0
                            anchors.verticalCenter: parent.verticalCenter
                            text: detailPage.github && assigneeBox.first === detailPage.github.login ? "you" : assigneeBox.first
                            url: Logic.profileUrl(assigneeBox.first)
                            font.pixelSize: Theme.fontSizeSmall
                            font.weight: Font.DemiBold
                            color: Theme.surfaceText
                        }

                        StyledText {
                            visible: assigneeBox.assignees.length > 1
                            anchors.verticalCenter: parent.verticalCenter
                            text: "+" + (assigneeBox.assignees.length - 1)
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        DankSpinner {
                            visible: detailPage.busyAction === "assign" || detailPage.busyAction === "unassign"
                            anchors.verticalCenter: parent.verticalCenter
                            size: 14
                        }

                        DankActionButton {
                            id: assigneeEdit
                            visible: assigneeBox.canAssign
                            anchors.verticalCenter: parent.verticalCenter
                            buttonSize: 22
                            iconSize: 14
                            iconName: "edit"
                            iconColor: Theme.surfaceVariantText
                            tooltipText: "Change assignees"
                            onClicked: assigneeMenu.show(assigneeEdit)
                        }
                    }
                }

                // Branches on the left and the size of the change on the
                // right, as on github.com (pull requests); branch and commit
                // on the left and how long it ran on the right (runs).
                Item {
                    id: branchRow
                    readonly property Item side: diffBox.visible ? diffBox : (runTime.visible ? runTime : null)
                    visible: (detailPage.kind === "pr" && !!detailPage.detail) || detailPage.kind === "run"
                    width: parent.width
                    height: Math.max(branchFlow.implicitHeight, side ? side.height : 0)

                    Flow {
                        id: branchFlow
                        width: parent.width - (branchRow.side ? branchRow.side.width + Theme.spacingM : 0)
                        spacing: Theme.spacingXS

                        // In github.com's order: the base, then the head it
                        // merges from (owner:branch when it lives in a fork),
                        // and a copy of the head branch's name.
                        BranchChip {
                            visible: detailPage.kind === "pr"
                            text: detailPage.detail && detailPage.kind === "pr" ? detailPage.detail.baseRefName : ""
                            url: detailPage.kind === "pr" && detailPage.item ? Logic.branchUrl(detailPage.item.repo, text) : ""
                        }

                        DankIcon {
                            visible: detailPage.kind === "pr"
                            height: 22
                            name: "arrow_back"
                            size: Theme.iconSizeSmall - 2
                            color: Theme.surfaceVariantText
                        }

                        BranchChip {
                            id: headChip
                            readonly property string branch: detailPage.kind === "run" ? String(detailPage.current ? detailPage.current.headBranch || "" : "") : (detailPage.detail ? detailPage.detail.headRefName : "")
                            readonly property string owner: detailPage.headRepo().split("/")[0]
                            readonly property bool fork: detailPage.kind === "pr" && !!detailPage.item && owner !== "" && owner !== detailPage.item.repo.split("/")[0]
                            visible: branch !== ""
                            text: fork ? owner + ":" + branch : branch
                            url: Logic.branchUrl(detailPage.kind === "run" ? detailPage.item.repo : detailPage.headRepo(), branch)
                        }

                        GitHubCopyButton {
                            visible: detailPage.kind === "pr" && headChip.branch !== ""
                            buttonSize: 22
                            github: detailPage.github
                            copyText: headChip.text
                            toast: "Copied " + headChip.text
                            tooltipText: "Copy the branch name"
                        }

                        BranchChip {
                            readonly property string sha: detailPage.kind === "run" && detailPage.detail ? String(detailPage.detail.headSha || "") : ""
                            visible: sha !== ""
                            icon: "commit"
                            text: sha.slice(0, 7)
                            url: Logic.commitUrl(detailPage.item.repo, sha)
                        }
                    }

                    // How long the run took, or has been running so far (the
                    // page reloads while it runs).
                    Row {
                        id: runTime
                        readonly property string text: detailPage.kind === "run" && detailPage.current ? Logic.duration(detailPage.current.startedAt || detailPage.current.createdAt, detailPage.runOutcome === "running" || detailPage.runOutcome === "queued" ? "" : detailPage.current.updatedAt) : ""
                        visible: text !== ""
                        anchors.right: parent.right
                        height: 22
                        spacing: Theme.spacingXS

                        DankIcon {
                            anchors.verticalCenter: parent.verticalCenter
                            name: "timer"
                            size: Theme.iconSizeSmall
                            color: Theme.surfaceVariantText
                        }

                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            text: runTime.text
                            font.pixelSize: Theme.fontSizeSmall
                            color: Theme.surfaceVariantText
                        }
                    }

                    // The size of the change opens its Files changed tab.
                    Item {
                        id: diffBox
                        anchors.right: parent.right
                        visible: detailPage.kind === "pr" && !!detailPage.detail
                        width: diffStat.implicitWidth
                        height: 22

                        Row {
                            id: diffStat
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: Theme.spacingXS

                            StyledText {
                                text: detailPage.detail && detailPage.kind === "pr" ? "+" + detailPage.detail.additions : ""
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.DemiBold
                                font.underline: diffArea.containsMouse
                                color: Theme.success
                            }

                            StyledText {
                                text: detailPage.detail && detailPage.kind === "pr" ? "−" + detailPage.detail.deletions : ""
                                font.pixelSize: Theme.fontSizeSmall
                                font.weight: Font.DemiBold
                                font.underline: diffArea.containsMouse
                                color: Theme.error
                            }

                            StyledText {
                                text: detailPage.detail && detailPage.kind === "pr" ? "· " + detailPage.detail.changedFiles + (detailPage.detail.changedFiles === 1 ? " file" : " files") : ""
                                font.pixelSize: Theme.fontSizeSmall
                                font.underline: diffArea.containsMouse
                                color: Theme.surfaceVariantText
                            }
                        }

                        MouseArea {
                            id: diffArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: detailPage.openLink(detailPage.itemUrl + "/files")
                        }
                    }
                }

                // Labels in their GitHub colors, each opening the issues or
                // pull requests that carry it.
                Flow {
                    readonly property var labels: detailPage.detail && detailPage.kind !== "run" ? (detailPage.detail.labels || []) : []
                    visible: labels.length > 0
                    width: parent.width
                    spacing: Theme.spacingXS

                    Repeater {
                        model: parent.labels

                        GitHubLabelChip {
                            required property var modelData
                            name: modelData.name
                            hex: modelData.color
                            action: () => detailPage.openLink(Logic.labelUrl(detailPage.item.repo, modelData.name))
                        }
                    }
                }
            }

            StyledText {
                visible: text !== ""
                width: parent.width
                text: detailPage.loadError
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.error
                wrapMode: Text.Wrap
            }

            // ---------- Jobs (runs) ----------
            GitHubJobs {
                page: detailPage
                jobs: detailPage.kind === "run" && detailPage.detail ? (detailPage.detail.jobs || []) : []
            }

            // ---------- Conversation ----------
            Column {
                visible: detailPage.kind !== "run" && !!detailPage.detail
                width: parent.width
                spacing: Theme.spacingM

                // The description is the first post, as on GitHub.
                GitHubPost {
                    page: detailPage
                    login: detailPage.detail ? Logic.loginOf(detailPage.detail) : ""
                    stamp: detailPage.detail ? Logic.when(detailPage.detail.createdAt) : ""
                    stampUrl: detailPage.itemUrl
                    isAuthor: true
                    source: detailPage.detail ? String(detailPage.detail.body || "").trim() : ""
                    placeholder: "_No description provided._"
                }

                // Where the issue stands among others, as github.com lists
                // it under the description: its sub-issues and how many are
                // done, and the issues it is blocked by or blocking.
                GitHubCard {
                    id: relations
                    readonly property var info: detailPage.detail && detailPage.kind === "issue" ? detailPage.detail : null
                    readonly property int total: info ? info.subIssuesTotal : 0
                    visible: !!info && (total > 0 || info.blockedBy.length > 0 || info.blocking.length > 0)

                    GitHubCardHeader {
                        visible: relations.total > 0
                        icon: "account_tree"
                        title: "Sub-issues"
                        note: relations.info ? relations.info.subIssuesDone + " of " + relations.total + " done" : ""
                    }

                    Item {
                        visible: relations.total > 0
                        width: parent.width
                        height: 10

                        Rectangle {
                            x: Theme.spacingS
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - Theme.spacingS * 2
                            height: 4
                            radius: 2
                            color: Theme.withAlpha(Theme.surfaceText, 0.1)

                            Rectangle {
                                width: relations.total > 0 && relations.info ? parent.width * relations.info.subIssuesDone / relations.total : 0
                                height: parent.height
                                radius: 2
                                color: Theme.primary
                            }
                        }
                    }

                    Repeater {
                        model: relations.info ? relations.info.subIssues : []

                        StatusRow {
                            required property var modelData
                            item: modelData
                            lead: Logic.refLabel(modelData, detailPage.item.repo)
                            label: modelData.title
                            note: modelData.subIssuesTotal > 0 ? modelData.subIssuesDone + "/" + modelData.subIssuesTotal : ""
                            url: modelData.url
                        }
                    }

                    GitHubLinkRow {
                        visible: !!relations.info && relations.total > relations.info.subIssues.length
                        text: "All " + relations.total + " sub-issues on GitHub"
                        action: () => detailPage.openExternally(detailPage.itemUrl)
                    }

                    GitHubCardHeader {
                        visible: !!relations.info && relations.info.blockedBy.length > 0
                        icon: "block"
                        iconColor: Theme.error
                        title: "Blocked by"
                    }

                    Repeater {
                        model: relations.info ? relations.info.blockedBy : []

                        StatusRow {
                            required property var modelData
                            item: modelData
                            lead: Logic.refLabel(modelData, detailPage.item.repo)
                            label: modelData.title
                            note: modelData.subIssuesTotal > 0 ? modelData.subIssuesDone + "/" + modelData.subIssuesTotal : ""
                            url: modelData.url
                        }
                    }

                    GitHubCardHeader {
                        visible: !!relations.info && relations.info.blocking.length > 0
                        icon: "front_hand"
                        title: "Blocking"
                    }

                    Repeater {
                        model: relations.info ? relations.info.blocking : []

                        StatusRow {
                            required property var modelData
                            item: modelData
                            lead: Logic.refLabel(modelData, detailPage.item.repo)
                            label: modelData.title
                            note: modelData.subIssuesTotal > 0 ? modelData.subIssuesDone + "/" + modelData.subIssuesTotal : ""
                            url: modelData.url
                        }
                    }
                }

                // A conversation longer than what one request brings says
                // so, and where the rest is.
                GitHubLinkRow {
                    readonly property int missing: detailPage.detail ? Math.max(0, (detailPage.detail.commentsTotal || 0) - detailPage.comments.length) : 0
                    readonly property int missingReviews: detailPage.detail && detailPage.kind === "pr" ? Math.max(0, (detailPage.detail.reviewsTotal || 0) - (detailPage.detail.reviews || []).length) + Math.max(0, (detailPage.detail.threadsTotal || 0) - (detailPage.detail.threads || []).length) : 0
                    visible: missing > 0 || missingReviews > 0
                    icon: "history"
                    text: missing > 0 ? missing + " earlier comments on GitHub" : "Earlier reviews on GitHub"
                    action: () => detailPage.openExternally(detailPage.itemUrl)
                }

                GitHubLinkRow {
                    visible: !detailPage.showAll && detailPage.timeline.length > detailPage.shownEntries
                    icon: "unfold_more"
                    text: "Show " + (detailPage.timeline.length - detailPage.shownEntries) + " earlier"
                    action: () => detailPage.showAll = true
                }

                Repeater {
                    model: detailPage.shownTimeline

                    GitHubPost {
                        required property var modelData
                        page: detailPage
                        login: modelData.login
                        verb: modelData.type === "review" ? Logic.reviewVerb(modelData.state) : ""
                        verdict: modelData.state
                        stamp: Logic.when(modelData.at)
                        stampUrl: modelData.url
                        isAuthor: !!detailPage.detail && login === Logic.loginOf(detailPage.detail)
                        source: modelData.body
                        threads: modelData.threads
                    }
                }
            }

            // As on GitHub, the state of the merge comes after the whole
            // conversation: reviews, then checks and what blocks a merge.
            // ---------- Reviews (pull requests) ----------
            GitHubCard {
                visible: detailPage.reviews.length > 0 || detailPage.reviewRequests.length > 0

                GitHubCardHeader {
                    icon: "rate_review"
                    title: "Reviews"
                    note: detailPage.detail ? Logic.decisionText(detailPage.detail.reviewDecision) : ""
                }

                Repeater {
                    model: detailPage.reviews

                    StatusRow {
                        required property var modelData
                        outcome: modelData.state === "APPROVED" ? "success" : "failure"
                        icon: modelData.state === "APPROVED" ? "check_circle" : "error"
                        label: Logic.loginOf(modelData)
                        caption: Logic.reviewCaption(modelData.state)
                        url: Logic.profileUrl(label)
                    }
                }

                Repeater {
                    model: detailPage.reviewRequests

                    StatusRow {
                        required property var modelData
                        outcome: "queued"
                        icon: "hourglass_empty"
                        label: String(modelData.login || modelData.name || modelData.slug || "reviewer")
                        caption: "review requested"
                        url: Logic.reviewerUrl(detailPage.item.repo, modelData)
                    }
                }
            }

            // ---------- Checks (pull requests) ----------
            GitHubCard {
                visible: detailPage.checks.length > 0 || detailPage.mergeState !== null

                GitHubCardHeader {
                    visible: detailPage.checks.length > 0
                    outcome: detailPage.checksReport ? detailPage.checksReport.headline.outcome : ""
                    title: detailPage.checksReport ? detailPage.checksReport.headline.text : ""
                    note: detailPage.checksReport ? detailPage.checksReport.summary : ""
                }

                Repeater {
                    model: detailPage.checks.slice(0, 6)

                    StatusRow {
                        required property var modelData
                        outcome: modelData.outcome
                        label: modelData.name
                        caption: modelData.detail
                        url: modelData.url
                    }
                }

                GitHubLinkRow {
                    visible: detailPage.checks.length > 6
                    text: "All " + (detailPage.detail ? detailPage.detail.checksTotal || detailPage.checks.length : 0) + " checks on GitHub"
                    action: () => detailPage.openExternally(detailPage.itemUrl + "/checks")
                }

                // What still stands between the pull request and a merge,
                // the last line of GitHub's merge box.
                Rectangle {
                    visible: detailPage.mergeState !== null && detailPage.checks.length > 0
                    width: parent.width
                    height: 1
                    color: Theme.withAlpha(Theme.outlineVariant, 0.35)
                }

                GitHubCardHeader {
                    visible: detailPage.mergeState !== null
                    glyph: detailPage.mergeState ? detailPage.mergeState.glyph : null
                    title: detailPage.mergeState ? detailPage.mergeState.text : ""
                }
            }
        }
    }

    GitHubAssigneeMenu {
        id: assigneeMenu
        anchors.fill: parent
        z: 10
        github: detailPage.github
        item: detailPage.item
        assigned: detailPage.detail && detailPage.kind !== "run" ? (detailPage.detail.assignees || []).map(person => String(person.login)) : []
        changing: detailPage.isBusy
        onToggled: (login, on) => detailPage.setAssigned(login, on)
        onDismissed: {
            close();
            detailPage.editingFinished();
        }
    }

    // ---------- Bottom bar: comment box and the page's changes ----------
    //
    // As on GitHub, what can be done to the page sits with the comment box:
    // the field (one line until it is used), then the changes on the left
    // and Comment on the right. A run has no conversation, only its changes.
    Column {
        id: composer
        readonly property bool conversational: (detailPage.kind === "pr" || detailPage.kind === "issue") && detailPage.canComment
        readonly property bool locked: !!detailPage.access && detailPage.access.locked && !detailPage.canComment
        readonly property bool open: commentBox.getActiveFocus() || commentBox.text !== ""
        visible: conversational || locked || actionRepeater.count > 0
        anchors.bottom: parent.bottom
        width: parent.width
        spacing: Theme.spacingS

        Rectangle {
            width: parent.width
            height: 1
            color: Theme.withAlpha(Theme.outlineVariant, 0.5)
        }

        // Answering a review thread instead of the page.
        Item {
            visible: !!detailPage.replyTo && composer.conversational
            width: parent.width
            height: 26

            DankIcon {
                id: replyIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                name: "reply"
                size: Theme.iconSizeSmall
                color: Theme.primary
            }

            StyledText {
                anchors.left: replyIcon.right
                anchors.leftMargin: Theme.spacingXS
                anchors.right: cancelReply.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                text: detailPage.replyTo ? "Replying to " + detailPage.replyTo.login + " on " + detailPage.replyTo.path.split("/").pop() : ""
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceText
                elide: Text.ElideRight
            }

            DankActionButton {
                id: cancelReply
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                buttonSize: 24
                iconName: "close"
                iconSize: Theme.iconSizeSmall
                iconColor: Theme.surfaceVariantText
                tooltipText: "Cancel the reply"
                onClicked: detailPage.replyTo = null
            }
        }

        DankTextEdit {
            id: commentBox
            visible: composer.conversational
            width: parent.width
            height: composer.open ? 96 : 40
            placeholderText: detailPage.replyTo ? "Write a reply…" : "Write a comment…  (c)"
            onTextChanged: detailPage.keepDraft()
            onFocusStateChanged: hasFocus => {
                if (!hasFocus)
                    detailPage.editingFinished();
            }
            Keys.priority: Keys.BeforeItem
            Keys.onPressed: event => {
                if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && (event.modifiers & Qt.ControlModifier)) {
                    detailPage.postComment();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Escape) {
                    commentBox.setFocus(false);
                    detailPage.editingFinished();
                    event.accepted = true;
                }
            }

            Behavior on height {
                NumberAnimation {
                    duration: Theme.shortDuration
                    easing.type: Theme.standardEasing
                }
            }
        }

        Row {
            visible: composer.locked
            spacing: Theme.spacingS

            DankIcon {
                anchors.verticalCenter: parent.verticalCenter
                name: "lock"
                size: Theme.iconSizeSmall
                color: Theme.surfaceVariantText
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                text: "Conversation locked: only collaborators can comment"
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
            }
        }

        Item {
            visible: actionRepeater.count > 0 || composer.conversational
            width: parent.width
            height: Math.max(actionFlow.implicitHeight, composer.conversational ? commentButton.height : 0)

            Flow {
                id: actionFlow
                anchors.left: parent.left
                anchors.right: commentButton.visible ? commentButton.left : parent.right
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                spacing: Theme.spacingS

                Repeater {
                    id: actionRepeater
                    model: detailPage.actions()

                    ActionChip {
                        required property var modelData
                        action: modelData
                    }
                }
            }

            GitHubPillButton {
                id: commentButton
                visible: composer.conversational
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                filled: true
                icon: "send"
                text: detailPage.replyTo ? "Reply" : "Comment"
                running: detailPage.busyAction === "comment" || detailPage.busyAction === "reply"
                usable: commentBox.text.trim() !== "" && !detailPage.isBusy
                onActivated: detailPage.postComment()
            }
        }

        StyledText {
            visible: composer.open
            width: parent.width
            text: detailPage.replyTo ? "Ctrl+Enter to reply · Esc to stop writing" : "Ctrl+Enter to comment · Esc to stop writing"
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            elide: Text.ElideRight
        }
    }

    // ---------------------------------------------------------- components

    // A pull request or issue this page links to, beside the state (one
    // that closes it, or its parent), in the color of its own state; it
    // opens here.
    component IssueChip: Rectangle {
        id: issueChip
        property var target: null
        property string text: ""
        property real maxTextWidth: 10000
        height: 24
        width: issueRow.implicitWidth + Theme.spacingM * 2
        radius: 12
        color: issueArea.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.07) : "transparent"
        border.width: 1
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.8)

        Row {
            id: issueRow
            anchors.centerIn: parent
            spacing: Theme.spacingXS

            GitHubStatusIcon {
                anchors.verticalCenter: parent.verticalCenter
                item: issueChip.target
                size: Theme.iconSizeSmall
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, issueChip.maxTextWidth)
                text: issueChip.text
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.surfaceVariantText
                elide: Text.ElideRight
            }
        }

        MouseArea {
            id: issueArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: detailPage.openLink(issueChip.target.url)
        }
    }

    component BranchChip: Rectangle {
        id: branchChip
        property string text: ""
        property string url: ""
        property string icon: ""
        height: 22
        width: Math.min(branchChipRow.implicitWidth + Theme.spacingS * 2, 220)
        radius: 6
        color: Theme.withAlpha(Theme.primary, branchArea.containsMouse && url !== "" ? 0.22 : 0.12)

        Row {
            id: branchChipRow
            anchors.centerIn: parent
            spacing: 3

            DankIcon {
                visible: branchChip.icon !== ""
                anchors.verticalCenter: parent.verticalCenter
                name: branchChip.icon
                size: Theme.iconSizeSmall - 2
                color: Theme.primary
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, 220 - Theme.spacingS * 2 - (branchChip.icon !== "" ? Theme.iconSizeSmall : 0))
                text: branchChip.text
                textFormat: Text.PlainText
                isMonospace: true
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.primary
                wrapMode: Text.NoWrap
                elide: Text.ElideMiddle
            }
        }

        MouseArea {
            id: branchArea
            anchors.fill: parent
            enabled: branchChip.url !== ""
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: detailPage.openLink(branchChip.url)
        }
    }

    // A row of a card: its status glyph (an item's, or an outcome's, with
    // another icon in its color), a reference leading, a label, a caption,
    // and a note on the right. A click opens its link: a related issue or a
    // check's run in place, a person's profile in the browser.
    component StatusRow: Rectangle {
        id: statusRow
        property var item: null
        property string outcome: ""
        property string icon: ""
        property string lead: ""
        property string label: ""
        property string caption: ""
        property string note: ""
        property string url: ""

        width: parent ? parent.width : 0
        height: 30
        radius: Theme.cornerRadius
        color: rowArea.containsMouse && url !== "" ? Theme.withAlpha(Theme.surfaceText, 0.06) : "transparent"

        GitHubStatusIcon {
            id: rowIcon
            anchors.left: parent.left
            anchors.leftMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            item: statusRow.item
            outcome: statusRow.outcome
            icon: statusRow.icon
            size: Theme.iconSizeSmall
        }

        StyledText {
            id: rowLead
            visible: text !== ""
            anchors.left: rowIcon.right
            anchors.leftMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            text: statusRow.lead
            textFormat: Text.PlainText
            font.pixelSize: Theme.fontSizeSmall
            font.weight: Font.DemiBold
            color: Theme.primary
        }

        StyledText {
            id: rowLabel
            anchors.left: rowLead.visible ? rowLead.right : rowIcon.right
            anchors.leftMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, statusRow.caption !== "" ? parent.width * 0.6 : rowEnd.x - x - Theme.spacingS)
            text: statusRow.label
            textFormat: Text.PlainText
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceText
            elide: Text.ElideRight
        }

        StyledText {
            anchors.left: rowLabel.right
            anchors.leftMargin: Theme.spacingS
            anchors.right: rowEnd.left
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            text: statusRow.caption
            textFormat: Text.PlainText
            font.pixelSize: Theme.fontSizeSmall
            color: Theme.surfaceVariantText
            elide: Text.ElideRight
        }

        Row {
            id: rowEnd
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingS
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXS

            StyledText {
                visible: text !== ""
                anchors.verticalCenter: parent.verticalCenter
                text: statusRow.note
                font.pixelSize: Theme.fontSizeSmall
                font.features: {
                    "tnum": 1
                }
                color: Theme.surfaceVariantText
            }

            DankIcon {
                anchors.verticalCenter: parent.verticalCenter
                visible: statusRow.url !== "" && rowArea.containsMouse
                name: "chevron_right"
                size: Theme.iconSizeSmall - 2
                color: Theme.surfaceVariantText
            }
        }

        MouseArea {
            id: rowArea
            anchors.fill: parent
            enabled: statusRow.url !== ""
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: detailPage.openLink(statusRow.url)
        }
    }

    // A change of the page's: a confirming change turns red and asks "Click
    // again" for a few seconds on the first click.
    component ActionChip: GitHubPillButton {
        property var action: ({})
        readonly property bool isArmed: detailPage.armed === action.id

        icon: action.icon || ""
        text: isArmed ? "Click again to " + String(action.label).toLowerCase() : (action.disabled && action.hint ? action.label + " · " + action.hint : action.label)
        tone: isArmed ? Theme.error : detailPage.toneColor(action.tone)
        tonal: (!!action.tonal && !action.disabled) || isArmed
        running: detailPage.busyAction === action.id
        usable: !action.disabled && !detailPage.isBusy
        onActivated: detailPage.trigger(action)
    }
}
