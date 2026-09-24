.pragma library

// The GitHub plugin's pure logic: what each list asks GitHub, how GitHub's
// answers become rows and pages, how links, job logs, and Markdown are read,
// and the rules for what a change hides or announces. Nothing here touches
// QML, gh, or the clock unless handed one, so GitHubData and the views call
// it and tests/support/github_logic.js runs it under Node.

// ---------------------------------------------------------------- lists
//
// Every list the popout offers, per scope: the viewer's own ("involving
// you", as GitHub's dashboards) and one repository's (everything in it, by
// state). The names are the aliases of queries/inbox.graphql, which receives
// these strings as variables, so the first page, the next ones, and a search
// ask the same question. A repository's list keys carry it after an @
// ("prOpen@owner/name").

var LISTS = {
    "viewer": {
        "issues": [
            {
                "name": "issueAssigned",
                "label": "Assigned",
                "search": "is:issue is:open archived:false assignee:@me sort:updated-desc"
            },
            {
                "name": "issueCreated",
                "label": "Created",
                "search": "is:issue is:open archived:false author:@me sort:updated-desc"
            },
            {
                "name": "issueMentioned",
                "label": "Mentioned",
                "search": "is:issue is:open archived:false mentions:@me sort:updated-desc"
            }
        ],
        "prs": [
            {
                "name": "prReview",
                "label": "Review requests",
                "search": "is:pr is:open archived:false review-requested:@me sort:updated-desc"
            },
            {
                "name": "prCreated",
                "label": "Created",
                "search": "is:pr is:open archived:false author:@me sort:updated-desc"
            },
            {
                "name": "prAssigned",
                "label": "Assigned",
                "search": "is:pr is:open archived:false assignee:@me sort:updated-desc"
            },
            {
                "name": "prMentioned",
                "label": "Mentioned",
                "search": "is:pr is:open archived:false mentions:@me sort:updated-desc"
            }
        ]
    },
    "repo": {
        "issues": [
            {
                "name": "issueOpen",
                "label": "Open",
                "search": "is:issue is:open sort:updated-desc"
            },
            {
                "name": "issueClosed",
                "label": "Closed",
                "search": "is:issue is:closed sort:updated-desc"
            }
        ],
        "prs": [
            {
                "name": "prOpen",
                "label": "Open",
                "search": "is:pr is:open sort:updated-desc"
            },
            {
                "name": "prMerged",
                "label": "Merged",
                "search": "is:pr is:merged sort:updated-desc"
            },
            {
                "name": "prClosed",
                "label": "Closed",
                "search": "is:pr is:closed is:unmerged sort:updated-desc"
            }
        ]
    }
};

// Counted, never listed: the pull requests assigned to the viewer that do
// not also ask for their review, so the bar can add assignments to review
// requests without counting a pull request twice.
var COUNTS = {
    "prAssignedOnly": "is:pr is:open archived:false assignee:@me -review-requested:@me"
};

var TABS = [
    {
        "id": "inbox",
        "label": "Inbox",
        "icon": "notifications"
    },
    {
        "id": "issues",
        "label": "Issues",
        "icon": "adjust"
    },
    {
        "id": "prs",
        "label": "Pull requests",
        "icon": "merge"
    },
    {
        "id": "actions",
        "label": "Actions",
        "icon": "play_circle"
    }
];

var FIXED_FILTERS = {
    "inbox": [
        {
            "key": "all",
            "label": "All"
        },
        {
            "key": "mention",
            "label": "Mentioned"
        },
        {
            "key": "review_requested",
            "label": "Review requests"
        },
        {
            "key": "assign",
            "label": "Assigned"
        }
    ],
    "actions": [
        {
            "key": "all",
            "label": "All"
        },
        {
            "key": "active",
            "label": "In progress"
        },
        {
            "key": "failed",
            "label": "Failed"
        }
    ]
};

function isRepo(name) {
    return /^[\w.-]+\/[\w.-]+$/.test(String(name || ""));
}

function scopedKey(name, repo) {
    return repo ? name + "@" + repo : name;
}

function keyRepo(key) {
    const at = String(key).indexOf("@");
    return at < 0 ? "" : String(key).slice(at + 1);
}

function keyName(key) {
    const at = String(key).indexOf("@");
    return at < 0 ? String(key) : String(key).slice(0, at);
}

function kindOf(key) {
    return keyName(key).indexOf("pr") === 0 ? "pr" : "issue";
}

function listDef(key) {
    const table = keyRepo(key) ? LISTS.repo : LISTS.viewer;
    const name = keyName(key);
    for (const tab in table) {
        const found = table[tab].find(list => list.name === name);
        if (found)
            return found;
    }
    return null;
}

// The search behind a list key, "" for none.
function searchFor(key) {
    const def = listDef(key);
    if (!def)
        return "";
    const repo = keyRepo(key);
    return repo ? "repo:" + repo + " " + def.search : def.search;
}

// What a search adds its words to: the list's search in every state. A
// repository's lists differ only by state, so its search takes the whole
// kind; the viewer's keep whom they involve.
function searchBase(key) {
    const repo = keyRepo(key);
    if (repo)
        return "repo:" + repo + (kindOf(key) === "pr" ? " is:pr" : " is:issue") + " sort:updated-desc";
    return searchFor(key).replace(/\bis:open\s+/, "");
}

// The tabs in GitHub's order. A repository has no inbox of its own:
// notifications are the viewer's.
function tabsFor(scope) {
    return scope ? TABS.filter(tab => tab.id !== "inbox") : TABS.slice();
}

function filtersFor(scope, tab) {
    if (FIXED_FILTERS[tab])
        return FIXED_FILTERS[tab];
    const table = scope ? LISTS.repo : LISTS.viewer;
    return (table[tab] || []).map(list => ({
                "key": scopedKey(list.name, scope),
                "label": list.label
            }));
}

// The list a tab counts: the first filter (review requests, assigned
// issues, or a repository's open ones).
function primaryKey(scope, tab) {
    const filters = filtersFor(scope, tab);
    return filters.length > 0 ? filters[0].key : "";
}

// Every list key of a scope.
function listKeys(scope) {
    const table = scope ? LISTS.repo : LISTS.viewer;
    const keys = [];
    for (const tab in table)
        for (const list of table[tab])
            keys.push(scopedKey(list.name, scope));
    return keys;
}

// The variables of the operation that fetches a scope's first pages: each
// list's search under its alias, and for the viewer the counted searches.
function searchVariables(scope) {
    const vars = {};
    for (const key of listKeys(scope))
        vars[keyName(key)] = searchFor(key);
    if (!scope)
        for (const name in COUNTS)
            vars[name] = COUNTS[name];
    return vars;
}

function isOpenList(key) {
    return /(^|\s)is:open(\s|$)/.test(searchFor(key));
}

function isClosedList(key) {
    return /(^|\s)is:(closed|merged)(\s|$)/.test(searchFor(key));
}

// A list page from a search answer: { items, cursor, more, count }.
function pageOf(result) {
    const info = result && result.pageInfo ? result.pageInfo : {};
    return {
        "items": (result && result.nodes ? result.nodes : []).filter(node => node && node.url).map(node => itemOf(node)),
        "cursor": String(info.endCursor || ""),
        "more": !!info.hasNextPage,
        "count": Number(result && result.issueCount || 0)
    };
}

// What a background refresh makes of a list: { items, cursor, more, count,
// loading, gen }, or null when the list scrolled past its first page. A
// fresh first page cannot stand in front of pages fetched from an older
// answer (a new item pushes one of the first page's into the second, which
// then goes missing), so such a list is fetched again as a whole instead.
// gen changes whenever the items do, so a next page asked for the old
// items is dropped; `reset` (an explicit refresh) starts over from the page.
function firstPageRecord(current, page, reset, pageSize) {
    if (!reset && current.items.length > pageSize)
        return null;
    const same = !reset && JSON.stringify(current.items) === JSON.stringify(page.items);
    return {
        "items": same ? current.items : page.items,
        "cursor": page.cursor,
        "more": page.more,
        "count": page.count,
        "loading": same ? current.loading : false,
        "gen": same ? current.gen : current.gen + 1
    };
}

function labelsOf(labels) {
    return (labels && labels.nodes ? labels.nodes : []).filter(label => !!label).map(label => ({
                "name": String(label.name || ""),
                "color": String(label.color || "")
            }));
}

// A search result (queries/inbox.graphql's pr or issue fragment) as a row.
function itemOf(node) {
    const kind = node.__typename === "PullRequest" ? "pr" : "issue";
    let checks = "";
    if (kind === "pr") {
        const commits = node.commits && node.commits.nodes ? node.commits.nodes : [];
        const rollup = commits.length > 0 && commits[0] && commits[0].commit ? commits[0].commit.statusCheckRollup : null;
        checks = rollup ? String(rollup.state || "") : "";
    }
    return {
        "kind": kind,
        "url": String(node.url),
        "number": Number(node.number || 0),
        "title": String(node.title || ""),
        "repo": node.repository ? String(node.repository.nameWithOwner || "") : "",
        "author": node.author ? String(node.author.login || "") : "ghost",
        "updatedAt": String(node.updatedAt || ""),
        "comments": node.comments ? Number(node.comments.totalCount || 0) : 0,
        "isDraft": !!node.isDraft,
        "state": String(node.state || "OPEN"),
        "stateReason": String(node.stateReason || ""),
        "reviewDecision": String(node.reviewDecision || ""),
        "checks": checks,
        "labels": labelsOf(node.labels)
    };
}

// The words of a list search in the loaded rows: every word somewhere in
// what the row shows.
function rowMatches(item, words) {
    const parts = [item.title, item.repo, String(item.number || ""), item.author, item.displayTitle, item.workflowName, item.headBranch, item.event, item.reason ? REASONS[item.reason] : ""];
    const haystack = parts.concat((item.labels || []).map(label => label.name || label)).filter(part => !!part).join(" ").toLowerCase();
    return words.every(word => haystack.indexOf(word) >= 0);
}

function searchWords(text) {
    return String(text || "").toLowerCase().split(/\s+/).filter(word => word.length > 0);
}

// ------------------------------------------------------------ notifications

var REASONS = {
    "approval_requested": "Approval requested",
    "assign": "Assigned",
    "author": "Author",
    "ci_activity": "CI activity",
    "comment": "Comment",
    "invitation": "Invitation",
    "manual": "Subscribed",
    "member_feature_requested": "Feature requested",
    "mention": "Mentioned",
    "review_requested": "Review requested",
    "security_advisory_credit": "Advisory credit",
    "security_alert": "Security alert",
    "state_change": "State change",
    "subscribed": "Watching",
    "team_mention": "Team mentioned"
};

var NOTIFICATION_ICONS = {
    "PullRequest": "merge",
    "Issue": "adjust",
    "Commit": "commit",
    "Release": "sell",
    "Discussion": "forum",
    "CheckSuite": "play_circle",
    "RepositoryVulnerabilityAlert": "security",
    "RepositoryDependabotAlertsThread": "security"
};

// The subject arrives as an API URL whose shape depends on its type; the
// known ones map to their page, anything else to the repository.
function normalizeThread(thread) {
    const repo = thread.repository ? String(thread.repository.full_name || "") : "";
    const subject = thread.subject || {};
    const type = String(subject.type || "");
    const api = String(subject.url || "");
    const base = repoUrl(repo);
    let url = repo ? base : "https://github.com/notifications";
    let number = 0;
    let match = api.match(/\/repos\/[^\/]+\/[^\/]+\/(pulls|issues|discussions)\/(\d+)$/);
    if (match && ((type === "PullRequest" && match[1] === "pulls") || (type === "Issue" && match[1] === "issues") || (type === "Discussion" && match[1] === "discussions"))) {
        number = Number(match[2]);
        url = base + "/" + (match[1] === "pulls" ? "pull" : match[1]) + "/" + number;
    } else if ((match = api.match(/\/repos\/[^\/]+\/[^\/]+\/commits\/([0-9a-fA-F]+)$/)) && type === "Commit") {
        url = base + "/commit/" + match[1];
    } else if (type === "Release" && repo) {
        url = base + "/releases";
    } else if (type === "CheckSuite" && repo) {
        url = base + "/actions";
    }
    return {
        "kind": "notification",
        "id": String(thread.id || ""),
        "type": type,
        "reason": String(thread.reason || ""),
        "title": String(subject.title || ""),
        "repo": repo,
        "number": number,
        "url": url,
        "updatedAt": String(thread.updated_at || "")
    };
}

// The page a pull request or issue thread opens: the thread already says
// what its subject is, so the page opens at once and fills in from its own
// load; null for any other subject.
function itemForThread(thread) {
    if ((thread.type !== "PullRequest" && thread.type !== "Issue") || !(thread.number > 0))
        return null;
    return {
        "kind": thread.type === "PullRequest" ? "pr" : "issue",
        "url": thread.url,
        "number": thread.number,
        "title": thread.title,
        "repo": thread.repo,
        "updatedAt": thread.updatedAt,
        // Open, closed, or merged arrives with the page's own load.
        "stateUnknown": true
    };
}

function filterThreads(threads, key) {
    if (key === "mention")
        return threads.filter(thread => thread.reason === "mention" || thread.reason === "team_mention");
    return key === "all" ? threads : threads.filter(thread => thread.reason === key);
}

// The next page of the unread inbox continues before the oldest thread
// loaded, not at a page number: marking threads read shrinks the unread
// list, which would shift numbered pages over threads not yet seen. A
// second of overlap keeps threads updated in the same second; the caller
// drops the ones it has.
function olderThan(threads) {
    let oldest = "";
    for (const thread of threads)
        if (thread.updatedAt && (oldest === "" || thread.updatedAt < oldest))
            oldest = thread.updatedAt;
    const ms = new Date(oldest).getTime();
    return oldest !== "" && isFinite(ms) ? new Date(ms + 1000).toISOString().replace(/\.\d{3}Z$/, "Z") : "";
}

// Which threads are news for a desktop notification, and the record to keep:
// { login: { since, seen: { id: updatedAt } } }, one entry per account, so
// switching gh accounts and back misses nothing. A thread is news when it
// changed since it was last seen, or, never seen, when it is newer than
// everything seen before (less a grace for notifications GitHub delivers
// late), so an old thread that moves into the fetched page as others are
// read is not. The first look for an account only records, so the caller
// makes the first call with a real answer for that account in hand. The
// record keeps the newest threads.
var ANNOUNCE_GRACE_MS = 600000;
var ANNOUNCE_KEPT = 500;

function announce(saved, login, threads) {
    const book = saved && typeof saved === "object" && !Array.isArray(saved) ? saved : {};
    const mine = book[login];
    const first = !mine || typeof mine !== "object" || typeof mine.seen !== "object" || mine.seen === null;
    const seen = first ? {} : Object.assign({}, mine.seen);
    const since = first ? "" : String(mine.since || "");
    const sinceMs = new Date(since).getTime();
    const floor = since !== "" && isFinite(sinceMs) ? new Date(sinceMs - ANNOUNCE_GRACE_MS).toISOString() : "";
    let newest = since;
    const fresh = [];
    for (const thread of threads) {
        const at = String(thread.updatedAt || "");
        const before = seen[thread.id];
        if (!first && (before ? at > before : at > floor))
            fresh.push(thread);
        if (!before || at > before)
            seen[thread.id] = at;
        if (at > newest)
            newest = at;
    }
    const ids = Object.keys(seen);
    if (ids.length > ANNOUNCE_KEPT) {
        ids.sort((a, b) => String(seen[b]).localeCompare(String(seen[a])));
        for (const id of ids.slice(ANNOUNCE_KEPT))
            delete seen[id];
    }
    return {
        "fresh": fresh,
        "state": withKey(book, login, {
            "since": newest,
            "seen": seen
        })
    };
}

// ----------------------------------------------------------------- runs

// A run, a job, or a check in one vocabulary: status plus conclusion,
// either as Actions spells them or as a GraphQL rollup state.
function outcome(status, conclusion) {
    const s = String(status || "").toLowerCase();
    const c = String(conclusion || "").toLowerCase();
    if (["queued", "waiting", "requested", "pending", "expected"].indexOf(s) >= 0 || s === "" && ["pending", "expected"].indexOf(c) >= 0)
        return "queued";
    if (s === "in_progress")
        return "running";
    if (c === "success")
        return "success";
    if (["failure", "timed_out", "startup_failure", "error", "action_required"].indexOf(c) >= 0)
        return "failure";
    if (c === "cancelled")
        return "cancelled";
    if (c === "skipped" || c === "neutral" || c === "stale")
        return "skipped";
    return s === "completed" ? "skipped" : "queued";
}

function isActiveRun(run) {
    const value = outcome(run.status, run.conclusion);
    return value === "queued" || value === "running";
}

function isFailedRun(run) {
    return outcome(run.status, run.conclusion) === "failure";
}

var OUTCOME_ICONS = {
    "queued": "schedule",
    "running": "progress_activity",
    "success": "check_circle",
    "failure": "cancel",
    "cancelled": "block",
    "skipped": "do_not_disturb_on"
};

// A status glyph: an icon and its tone, which GitHubStatusIcon colors from
// the shell theme as GitHub colors them there: open or passing in success,
// merged or done in the accent, closed or failed in error, running in
// warning, anything settled but not green muted, and plain as text.
function glyph(icon, tone) {
    return {
        "icon": icon,
        "tone": tone
    };
}

function outcomeGlyph(value) {
    const tone = value === "success" ? "success" : (value === "failure" ? "error" : (value === "running" || value === "queued" ? "warning" : "muted"));
    return glyph(OUTCOME_ICONS[value] || "radio_button_unchecked", tone);
}

// What a pull request, an issue, or a run is and where it stands; `state`
// overrides the item's own (a page's load knows better than its row). A
// notification says only what its subject is.
function itemGlyph(item, state) {
    if (item.kind === "notification")
        return glyph(NOTIFICATION_ICONS[item.type] || "notifications", "plain");
    if (item.kind === "run")
        return outcomeGlyph(outcome(item.status, item.conclusion));
    const s = String(state || item.state || "OPEN");
    if (item.kind === "pr") {
        if (s === "MERGED")
            return glyph("merge", "accent");
        if (s === "CLOSED")
            return glyph("cancel", "error");
        return item.isDraft ? glyph("edit_note", "muted") : glyph("merge", "success");
    }
    if (s === "CLOSED")
        return isUnfinished(item) ? glyph("block", "muted") : glyph("check_circle", "accent");
    return glyph("adjust", "success");
}

var RUN_LABELS = {
    "queued": "Queued",
    "running": "In progress",
    "success": "Succeeded",
    "failure": "Failed",
    "cancelled": "Cancelled",
    "skipped": "Skipped"
};

// The runs a full refresh keeps: exactly the watched repositories' answers.
// A quick refresh of the running ones keeps the other watched
// repositories' runs as they were; runs of repositories no longer watched
// go either way.
function mergeRuns(current, fresh, asked, watched, keep) {
    const kept = current.filter(run => watched.indexOf(run.repo) >= 0 && asked.indexOf(run.repo) < 0);
    const merged = kept.concat(fresh);
    merged.sort((a, b) => String(b.createdAt).localeCompare(String(a.createdAt)));
    return merged.slice(0, keep);
}

// The runs a filter of the Actions tab shows.
function filterRuns(runs, key) {
    if (key === "active")
        return runs.filter(run => isActiveRun(run));
    if (key === "failed")
        return runs.filter(run => isFailedRun(run));
    return runs;
}

// ------------------------------------------------------------ job logs
//
// A job's log, split into its steps, once the job has finished: GitHub
// publishes no log for a running job. The raw log is one text with a
// timestamp on every line; each step that ran begins at a line of its own
// kind, taken only once that step has started: the runner's own steps at
// fixed lines, a workflow step at its `##[group]Run` line. Step start times
// have a resolution of a second, so a composite action's inner groups can
// share a second with the next step; a step named after its command
// ("Run npm test", the default) therefore begins only at that very line
// when the log has it, and any other at the next Run group. A step with a
// name of its own after a composite action can still take the action's last
// group when both fall in one second: the log says nothing that tells them
// apart. So the split stays a best effort, which the page says, and the
// whole log is kept beside it.

function groupSays(content, name) {
    const said = content.slice("##[group]".length).trim();
    return said === name || said.indexOf(name) === 0 || name.indexOf(said) === 0;
}

// `named`: the step's own name is the command its Run line shows.
function stepBegins(step, content, named) {
    const name = String(step.name || "");
    if (name === "Initialize containers")
        return content.indexOf("##[group]Checking docker version") === 0;
    if (name === "Stop containers")
        return content.indexOf("Stop and remove container:") === 0 || content.indexOf("Print service container logs:") === 0;
    if (name === "Complete job")
        return content.indexOf("Cleaning up orphan processes") === 0;
    if (name.indexOf("Post ") === 0)
        return content.indexOf("Post job cleanup.") === 0;
    if (content.indexOf("##[group]Run ") !== 0)
        return false;
    return !named || groupSays(content, name);
}

function splitJobLog(text, steps) {
    const ran = steps.filter(step => step.conclusion !== "skipped" && step.startedAt).slice().sort((a, b) => a.number - b.number);
    const starts = ran.map(step => new Date(String(step.startedAt)).getTime());
    const lines = [];
    for (const raw of String(text || "").split(/\r?\n/)) {
        const match = raw.match(/^\uFEFF?(\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d)(?:\.\d+)?Z ?(.*)$/);
        if (match)
            lines.push({
                "time": new Date(match[1] + "Z").getTime(),
                "content": match[2].replace(/\x1b\[[0-9;]*[A-Za-z]/g, "")
            });
    }
    // A step named "Run ..." whose very line is in the log waits for it;
    // one whose name is its own (that also happens to start with Run) does
    // not.
    const named = ran.map((step, j) => {
        const name = String(step.name || "");
        return name.indexOf("Run ") === 0 && lines.some(line => line.time >= starts[j] && line.content.indexOf("##[group]Run ") === 0 && groupSays(line.content, name));
    });
    const out = {};
    for (const step of ran)
        out[step.number] = [];
    let current = 0;
    for (const line of lines) {
        // A step that printed nothing leaves no mark, so look a few steps
        // ahead for the one this line begins.
        for (let j = current + 1; j < Math.min(ran.length, current + 4); j++) {
            if (line.time >= starts[j] && stepBegins(ran[j], line.content, named[j])) {
                current = j;
                break;
            }
        }
        if (ran.length > 0)
            out[ran[current].number].push(line.content);
    }
    return {
        "steps": out,
        "all": lines.map(line => line.content)
    };
}

function escapeHtml(text) {
    return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;");
}

function tint(color, html) {
    return "<span style=\"color:" + String(color) + "\">" + html + "</span>";
}

// Log lines as rich text, GitHub's markers styled the way its log view
// shows them; colors: { command, error, warning, muted }.
function logHtml(lines, colors) {
    const out = [];
    for (const line of lines) {
        const marker = line.match(/^##\[(\w+)\](.*)$/);
        if (marker && marker[1] === "endgroup")
            continue;
        if (!marker) {
            out.push(line.indexOf("[command]") === 0 ? tint(colors.command, escapeHtml(line.slice(9))) : escapeHtml(line));
            continue;
        }
        const rest = escapeHtml(marker[2]);
        if (marker[1] === "group")
            out.push("<b>" + rest + "</b>");
        else if (marker[1] === "error")
            out.push(tint(colors.error, "Error: " + rest));
        else if (marker[1] === "warning")
            out.push(tint(colors.warning, "Warning: " + rest));
        else if (marker[1] === "command")
            out.push(tint(colors.command, rest));
        else
            out.push(tint(colors.muted, rest));
    }
    return "<div style=\"white-space:pre-wrap\">" + out.join("<br>") + "</div>";
}

// --------------------------------------------------------------- links
//
// A github.com link to a pull request, an issue, or an Actions run (a job
// page counts as its run) opens in the popout; a label, or an issues or
// pulls page with a q=, opens that repository's list with the search; and
// anything else goes to the browser, as long as it is a web or mail link.
// A pull request's own tabs (Files changed, Commits, Checks) are not its
// conversation, so they go to the browser too; so does a link to a place in
// a page (a comment's #issuecomment-...), which a page here does not scroll
// to: parseLink says where (`anchor`).

function parseLink(url) {
    const text = String(url || "");
    const ref = text.match(/^https:\/\/github\.com\/([\w.-]+)\/([\w.-]+)\/(pull|issues)\/(\d+)\/?(?:\?[^#]*)?(?:#(.*))?$/);
    if (ref)
        return {
            "kind": ref[3] === "pull" ? "pr" : "",
            "owner": ref[1],
            "name": ref[2],
            "repo": ref[1] + "/" + ref[2],
            "number": Number(ref[4]),
            "anchor": String(ref[5] || "")
        };
    const run = text.match(/^https:\/\/github\.com\/([\w.-]+)\/([\w.-]+)\/actions\/runs\/(\d+)(?:[\/?#].*)?$/);
    if (run)
        return {
            "kind": "run",
            "owner": run[1],
            "name": run[2],
            "repo": run[1] + "/" + run[2],
            "databaseId": Number(run[3])
        };
    return null;
}

// { repo, tab, terms } or null. A label names no kind, so it takes
// `labelTab`. The states drop out, since a search here spans them all.
function parseSearchLink(url, labelTab) {
    const text = String(url || "");
    // A body can hold any percent sign; one that decodes to nothing stays.
    const decode = part => {
        try {
            return decodeURIComponent(part);
        } catch (e) {
            return part;
        }
    };
    const label = text.match(/^https:\/\/github\.com\/([\w.-]+\/[\w.-]+)\/labels\/([^\/?#]+)\/?$/);
    if (label) {
        const name = decode(label[2]);
        return {
            "repo": label[1],
            "tab": labelTab || "issues",
            "terms": "label:" + (/[\s"]/.test(name) ? "\"" + name.replace(/"/g, "") + "\"" : name)
        };
    }
    const list = text.match(/^https:\/\/github\.com\/([\w.-]+\/[\w.-]+)\/(issues|pulls)\/?(?:\?([^#]*))?(?:#.*)?$/);
    if (!list)
        return null;
    let q = "";
    for (const pair of String(list[3] || "").split("&")) {
        const at = pair.indexOf("=");
        if (at > 0 && pair.slice(0, at) === "q")
            q = decode(pair.slice(at + 1).replace(/\+/g, " "));
    }
    return {
        "repo": list[1],
        "tab": list[2] === "pulls" ? "prs" : "issues",
        "terms": q.replace(/(^|\s)(is:(issue|pr|pull-request|open|closed|merged|unmerged)|state:\S+|repo:\S+|type:(issue|pr))(?=\s|$)/gi, " ").replace(/\s+/g, " ").trim()
    };
}

// Bodies are written by anyone, and github.com drops links it would not
// follow; so does this: only web and mail links leave for another app.
function externalUrl(url) {
    const text = String(url || "").trim();
    return /^(https?:\/\/|mailto:)/i.test(text) ? text : "";
}

function repoUrl(repo) {
    return "https://github.com/" + repo;
}

// "" for a deleted account (GitHub's ghost), which has no page.
function profileUrl(login) {
    return login && login !== "ghost" ? "https://github.com/" + login : "";
}

function labelUrl(repo, name) {
    return repoUrl(repo) + "/labels/" + encodeURIComponent(name);
}

function branchUrl(repo, branch) {
    return branch ? repoUrl(repo) + "/tree/" + String(branch).split("/").map(encodeURIComponent).join("/") : "";
}

function commitUrl(repo, sha) {
    return sha ? repoUrl(repo) + "/commit/" + sha : "";
}

function workflowUrl(repo, name) {
    return name ? repoUrl(repo) + "/actions?query=" + encodeURIComponent("workflow:\"" + name + "\"") : "";
}

// A requested reviewer: a person's profile, or a team of the repository's
// organization.
function reviewerUrl(repo, reviewer) {
    return reviewer.slug ? "https://github.com/orgs/" + String(repo).split("/")[0] + "/teams/" + reviewer.slug : profileUrl(reviewer.login);
}

// A tab's page on github.com, for the viewer or in a repository.
function tabUrl(scope, tab) {
    if (scope)
        return repoUrl(scope) + ({
                "prs": "/pulls",
                "issues": "/issues",
                "actions": "/actions"
            }[tab] || "");
    return tab === "issues" ? "https://github.com/issues" : (tab === "prs" ? "https://github.com/pulls" : "https://github.com");
}

// #12, or name#12 for another repository's.
function refLabel(item, repo) {
    return (item.repo === repo ? "" : String(item.repo).split("/")[1]) + "#" + item.number;
}

// ------------------------------------------------------------ gh answers

// gh exits 4 when it has no credentials; its message names the fix.
function describeFailure(code, stderr) {
    const text = String(stderr || "").trim();
    if (code === 4 || /gh auth login|not logged in|authentication required/i.test(text))
        return "signedOut";
    return text !== "" ? text.split("\n").filter(line => line.trim() !== "").slice(-3).join("\n") : "gh exited with status " + code;
}

// A failure as a toast or a page says it.
function failureText(failure) {
    return failure === "signedOut" ? "The GitHub CLI is signed out. Run gh auth login." : String(failure || "");
}

function canWrite(permission) {
    return ["WRITE", "MAINTAIN", "ADMIN"].indexOf(String(permission || "")) >= 0;
}

// `gh api graphql` prints GitHub's answer even when it exits 1 over an
// error in part of it: { data, errors: [{ message, type }] }, or null when
// the output is not JSON.
function graphqlAnswer(out) {
    try {
        const parsed = String(out || "").trim() !== "" ? JSON.parse(out) : null;
        if (!parsed || typeof parsed !== "object")
            return null;
        return {
            "data": parsed.data || null,
            "errors": Array.isArray(parsed.errors) ? parsed.errors.map(error => ({
                            "message": String(error && error.message || ""),
                            "type": String(error && error.type || "")
                        })) : []
        };
    } catch (e) {
        return null;
    }
}

// The arguments of `gh api graphql`: the query file by path (-F reads the
// @file), numbers and booleans typed (-F), and every string raw (-f), since
// -F would turn a repository named 123, true, or null into a number or a
// literal.
function graphqlArgs(file, operation, vars) {
    const args = ["api", "graphql", "-F", "query=@" + file];
    if (operation)
        args.push("-f", "operationName=" + operation);
    for (const name in vars) {
        const value = vars[name];
        if (value === null || value === undefined)
            continue;
        if (typeof value === "number" || typeof value === "boolean")
            args.push("-F", name + "=" + value);
        else
            args.push("-f", name + "=" + value);
    }
    return args;
}

// ------------------------------------------------------------ changes

var MERGE_FLAGS = {
    "MERGE": "--merge",
    "SQUASH": "--squash",
    "REBASE": "--rebase"
};

var MERGE_LABELS = {
    "MERGE": "Merge",
    "SQUASH": "Squash and merge",
    "REBASE": "Rebase and merge"
};

// Every change the pages offer, by name: the gh arguments it runs (args,
// given the item, the text, and `extra`: commentId, a thread's first
// comment, for a reply; threadId for resolving; login for assigning; id and
// state for a subscription; mergeMethod for a merge), the toast once it went
// through (done, before the item's name), and what else it moves: `lists`
// when it moves the item between lists, which refresh; `leaves`, the lists
// it leaves at once, before GitHub's search catches up (seconds); `runs`
// for a run's change, after which the runs refresh; `scope`, a token scope
// it needs that gh auth login does not grant; `verify`, the state the item
// must be in afterwards for `done` to be true, since gh also succeeds when
// it only started the change (`started`, while the item is still in the
// `waiting` state: a merge queue, or a merge waiting for its checks), which
// leaves no list, and `unknown` for anything else (GitHub could not be
// asked, or the item went another way, such as closed meanwhile). A comment, a reply, a thread, or a subscription
// changes only its page.
var ACTIONS = {
    "comment": {
        "done": "Comment posted on",
        "args": (item, body) => [item.kind, "comment", item.url, "--body", body]
    },
    "reply": {
        "done": "Reply posted on",
        // -f sends the text as it is; -F would read a leading @ as a file.
        "args": (item, body, extra) => ["api", "-X", "POST", "repos/" + item.repo + "/pulls/" + item.number + "/comments/" + extra.commentId + "/replies", "-f", "body=" + body]
    },
    "resolve": {
        "done": "Resolved a conversation on",
        "args": (item, body, extra) => ["api", "graphql", "-f", "query=mutation($id: ID!) { resolveReviewThread(input: {threadId: $id}) { thread { isResolved } } }", "-f", "id=" + extra.threadId]
    },
    "unresolve": {
        "done": "Reopened a conversation on",
        "args": (item, body, extra) => ["api", "graphql", "-f", "query=mutation($id: ID!) { unresolveReviewThread(input: {threadId: $id}) { thread { isResolved } } }", "-f", "id=" + extra.threadId]
    },
    "approve": {
        "done": "Approved",
        "lists": true,
        "leaves": key => keyName(key) === "prReview",
        "args": item => ["pr", "review", item.url, "--approve"]
    },
    // headSha, the head commit the page showed when the merge was asked
    // for: a commit pushed since makes gh refuse rather than merge it too.
    "merge": {
        "done": "Merged",
        "verify": "MERGED",
        "waiting": "OPEN",
        "started": "Queued to merge",
        "unknown": "Asked to merge",
        "lists": true,
        "leaves": isOpenList,
        "args": (item, body, extra) => ["pr", "merge", item.url, MERGE_FLAGS[extra.mergeMethod] || "--merge"].concat(extra.headSha ? ["--match-head-commit", extra.headSha] : [])
    },
    "ready": {
        "done": "Marked ready for review",
        "lists": true,
        "args": item => ["pr", "ready", item.url]
    },
    "close": {
        "done": "Closed",
        "lists": true,
        "leaves": isOpenList,
        "args": item => [item.kind, "close", item.url]
    },
    "reopen": {
        "done": "Reopened",
        "lists": true,
        "leaves": isClosedList,
        "args": item => [item.kind, "reopen", item.url]
    },
    "assign": {
        "done": "Assigned",
        "lists": true,
        "args": (item, body, extra) => [item.kind, "edit", item.url, "--add-assignee", extra.login]
    },
    "unassign": {
        "done": "Unassigned",
        "lists": true,
        "args": (item, body, extra) => [item.kind, "edit", item.url, "--remove-assignee", extra.login]
    },
    "subscription": {
        "done": "Changed notifications for",
        "scope": "notifications",
        "args": (item, body, extra) => ["api", "graphql", "-f", "query=mutation($id: ID!, $state: SubscriptionState!) { updateSubscription(input: {subscribableId: $id, state: $state}) { subscribable { viewerSubscription } } }", "-f", "id=" + extra.id, "-f", "state=" + extra.state]
    },
    "rerunFailed": {
        "done": "Re-running failed jobs of",
        "runs": true,
        "args": item => ["run", "rerun", String(item.databaseId), "--failed", "-R", item.repo]
    },
    "rerun": {
        "done": "Re-running",
        "runs": true,
        "args": item => ["run", "rerun", String(item.databaseId), "-R", item.repo]
    },
    "cancel": {
        "done": "Cancelling",
        "runs": true,
        "args": item => ["run", "cancel", String(item.databaseId), "-R", item.repo]
    }
};

function mutationArgs(item, action, body, extra) {
    return ACTIONS[action].args(item, body, extra || {});
}

// Whether a change keeps its item out of a list until search catches up.
function hiddenIn(action, key) {
    const def = ACTIONS[action];
    return !!def && !!def.leaves && def.leaves(key);
}

function itemName(item) {
    if (item.kind === "run")
        return String(item.workflowName || "run") + " #" + item.number;
    return item.repo + "#" + item.number;
}

// ----------------------------------------------------------- detail pages

function nodesOf(connection) {
    return connection && Array.isArray(connection.nodes) ? connection.nodes.filter(node => !!node) : [];
}

function totalOf(connection, shown) {
    return connection && typeof connection.totalCount === "number" ? connection.totalCount : shown;
}

function loginOf(entry) {
    return entry && entry.author ? String(entry.author.login || "ghost") : "ghost";
}

function relatedIssue(issue, repo) {
    const summary = issue.subIssuesSummary || {};
    return {
        "kind": "issue",
        "number": Number(issue.number),
        "title": String(issue.title || ""),
        "url": String(issue.url),
        "state": String(issue.state || "OPEN"),
        "stateReason": String(issue.stateReason || ""),
        "repo": issue.repository ? String(issue.repository.nameWithOwner) : repo,
        "subIssuesTotal": Number(summary.total || 0),
        "subIssuesDone": Number(summary.completed || 0)
    };
}

// Whether the viewer gets this page's notifications, why, and what the bell
// does, as github.com's Notifications box says it: { can, on, reason, next }
// with next the subscription state a click asks for. Issues say why; a pull
// request only whether.
function subscriptionOf(node) {
    const can = !!node.viewerCanSubscribe;
    const status = String(node.viewerThreadSubscriptionStatus || "");
    const action = String(node.viewerThreadSubscriptionFormAction || "");
    if (status === "" || action === "") {
        const on = String(node.viewerSubscription || "") === "SUBSCRIBED";
        return {
            "can": can,
            "on": on,
            "reason": on ? "You're receiving notifications from this pull request." : "You're not receiving notifications from this pull request.",
            "next": on ? "UNSUBSCRIBED" : "SUBSCRIBED"
        };
    }
    const reasons = {
        "SUBSCRIBED_TO_THREAD": "You're receiving notifications because you're subscribed to this thread.",
        "SUBSCRIBED_TO_THREAD_EVENTS": "You're receiving notifications because you chose custom settings for this thread.",
        "SUBSCRIBED_TO_THREAD_TYPE": "You're receiving notifications because you chose custom settings for this thread.",
        "SUBSCRIBED_TO_LIST": "You're receiving notifications because you're watching this repository.",
        "IGNORING_THREAD": "You're ignoring this thread.",
        "IGNORING_LIST": "You're ignoring this repository.",
        "NONE": "You're not receiving notifications from this thread."
    };
    return {
        "can": can && action !== "NONE",
        "on": action === "UNSUBSCRIBE",
        "reason": reasons[status] || "",
        // Watching the repository keeps a thread coming unless it is
        // ignored, which is what github.com's Unsubscribe does there.
        "next": action === "UNSUBSCRIBE" ? (status === "SUBSCRIBED_TO_LIST" ? "IGNORED" : "UNSUBSCRIBED") : "SUBSCRIBED"
    };
}

function normalizeChecks(contexts) {
    const out = [];
    for (const check of contexts) {
        if (check.__typename === "StatusContext") {
            out.push({
                "name": String(check.context || "status"),
                "detail": String(check.description || ""),
                "outcome": outcome("", check.state),
                "url": String(check.targetUrl || "")
            });
        } else {
            const run = check.checkSuite && check.checkSuite.workflowRun;
            out.push({
                "name": String(check.name || "check"),
                "detail": run && run.workflow ? String(run.workflow.name || "") : "",
                "outcome": outcome(check.status, check.conclusion),
                "url": String(check.detailsUrl || "")
            });
        }
    }
    const rank = {
        "failure": 0,
        "running": 1,
        "queued": 2,
        "cancelled": 3,
        "success": 4,
        "skipped": 5
    };
    out.sort((a, b) => rank[a.outcome] - rank[b.outcome] || a.name.localeCompare(b.name));
    return out;
}

// How the checks stand, as GitHub's merge box says it: the card's headline
// and its note. The page fetches the first 100 checks; `state` is GitHub's
// verdict over all of them (the commit's rollup) and `total` how many there
// are, so a failure past the fetched ones still reads as one.
function checksReport(checks, state, total) {
    const tally = {};
    for (const check of checks)
        tally[check.outcome] = (tally[check.outcome] || 0) + 1;
    const failing = tally.failure || 0;
    const pending = (tally.running || 0) + (tally.queued || 0);
    const unseen = Math.max(0, Number(total || 0) - checks.length);
    const rollup = String(state || "");
    const headline = (text, outcome) => ({
            "text": text,
            "outcome": outcome
        });
    let head;
    if (failing > 0)
        head = headline(failing + (failing === 1 ? " check failing" : " checks failing"), "failure");
    else if (unseen > 0 && (rollup === "FAILURE" || rollup === "ERROR"))
        head = headline("Some checks failed", "failure");
    else if (pending > 0)
        head = headline(pending + (pending === 1 ? " check running" : " checks running"), "running");
    else if (unseen > 0 && (rollup === "PENDING" || rollup === "EXPECTED"))
        head = headline("Some checks are still running", "running");
    else if (tally.cancelled > 0)
        head = headline("Some checks were not successful", "cancelled");
    else
        head = headline("All checks passed", "success");
    const words = [["failure", "failing"], ["running", "running"], ["queued", "queued"], ["success", "passed"], ["cancelled", "cancelled"], ["skipped", "skipped"]];
    const parts = words.filter(w => tally[w[0]] > 0).map(w => tally[w[0]] + " " + w[1]);
    if (unseen > 0)
        parts.push(unseen + " more on GitHub");
    return {
        "headline": head,
        "summary": parts.join(" · ")
    };
}

// GitHub's merge box line for an open pull request: { text, kind, glyph }
// with kind one of conflict, behind, blocked, clean; or null.
function mergeStatus(detail) {
    if (!detail || detail.kind !== "pr" || detail.state !== "OPEN" || detail.isDraft)
        return null;
    const state = String(detail.mergeStateStatus || "");
    const status = (text, kind, icon, tone) => ({
            "text": text,
            "kind": kind,
            "glyph": glyph(icon, tone)
        });
    if (detail.mergeable === "CONFLICTING" || state === "DIRTY")
        return status("This branch has conflicts that must be resolved", "conflict", "warning", "error");
    if (state === "BEHIND")
        return status("This branch is out of date with the base branch", "behind", "sync_problem", "warning");
    if (state === "BLOCKED")
        return status("Merging is blocked by branch protection", "blocked", "block", "warning");
    if (state === "CLEAN" || state === "HAS_HOOKS" || state === "UNSTABLE")
        return status("No conflicts with the base branch", "clean", "check_circle", "success");
    return null;
}

var REVIEW_WORDS = {
    "APPROVED": {
        "verb": "approved these changes",
        "caption": "approved"
    },
    "CHANGES_REQUESTED": {
        "verb": "requested changes",
        "caption": "requested changes"
    },
    "DISMISSED": {
        "verb": "reviewed (dismissed)",
        "caption": "review dismissed"
    }
};

function reviewVerb(state) {
    return REVIEW_WORDS[state] ? REVIEW_WORDS[state].verb : "reviewed";
}

function reviewCaption(state) {
    return REVIEW_WORDS[state] ? REVIEW_WORDS[state].caption : "commented";
}

var DECISIONS = {
    "APPROVED": "Approved",
    "CHANGES_REQUESTED": "Changes requested",
    "REVIEW_REQUIRED": "Review required"
};

function decisionText(decision) {
    return DECISIONS[String(decision || "")] || "";
}

// An issue closed without being done: not planned, or a duplicate.
function isUnfinished(item) {
    return item.stateReason === "NOT_PLANNED" || item.stateReason === "DUPLICATE";
}

// The state badge: what github.com writes beside a page's title.
function stateLabel(kind, state, stateReason, isDraft, runOutcome) {
    if (kind === "run")
        return RUN_LABELS[runOutcome] || "";
    if (state === "MERGED")
        return "Merged";
    if (state === "CLOSED") {
        if (kind === "issue" && stateReason === "NOT_PLANNED")
            return "Closed as not planned";
        if (kind === "issue" && stateReason === "DUPLICATE")
            return "Closed as duplicate";
        return "Closed";
    }
    return isDraft ? "Draft" : "Open";
}

// A pull request's or an issue's page from queries/detail.graphql: the
// page itself (the fields gh's own view gives, with the checks already
// read, and what it links to: the issues or pull requests that close it, an
// issue's parent, sub-issues, and blockers), what the viewer may change
// there, and the signed URLs of its images. The connections that stop short
// (the newest 100 comments, reviews, and threads) say how many there are in
// all.
function normalizeDetail(kind, repository) {
    const node = repository ? (kind === "pr" ? repository.pullRequest : repository.issue) : null;
    if (!node)
        return null;
    const repo = String(repository.nameWithOwner || "");
    const comments = nodesOf(node.comments).map(comment => ({
                "author": {
                    "login": loginOf(comment)
                },
                "body": String(comment.body || ""),
                "createdAt": String(comment.createdAt || ""),
                "url": String(comment.url || "")
            }));
    const detail = {
        "kind": kind,
        "number": Number(node.number || 0),
        "title": String(node.title || ""),
        "url": String(node.url || ""),
        "state": String(node.state || "OPEN"),
        "stateReason": String(node.stateReason || ""),
        "isDraft": !!node.isDraft,
        "body": String(node.body || ""),
        "createdAt": String(node.createdAt || ""),
        "author": {
            "login": loginOf(node)
        },
        "labels": labelsOf(node.labels),
        "assignees": nodesOf(node.assignees).map(person => ({
                    "login": String(person.login || "")
                })),
        "comments": comments,
        "commentsTotal": totalOf(node.comments, comments.length)
    };
    const images = {};
    imagePairs(node.body, node.bodyHTML, images);
    for (const comment of nodesOf(node.comments))
        imagePairs(comment.body, comment.bodyHTML, images);
    if (kind === "pr") {
        const commits = nodesOf(node.commits);
        const rollup = commits.length > 0 && commits[0].commit ? commits[0].commit.statusCheckRollup : null;
        const contexts = rollup ? nodesOf(rollup.contexts) : [];
        const reviews = nodesOf(node.reviews);
        // Each thread's comments without the ones GitHub could not return.
        const threads = nodesOf(node.reviewThreads).map(thread => Object.assign({}, thread, {
                        "comments": {
                            "totalCount": totalOf(thread.comments, nodesOf(thread.comments).length),
                            "nodes": nodesOf(thread.comments)
                        }
                    }));
        for (const review of reviews)
            imagePairs(review.body, review.bodyHTML, images);
        for (const thread of threads)
            for (const comment of nodesOf(thread.comments))
                imagePairs(comment.body, comment.bodyHTML, images);
        Object.assign(detail, {
            "baseRefName": String(node.baseRefName || ""),
            "headRefName": String(node.headRefName || ""),
            "headRepo": node.headRepository ? String(node.headRepository.nameWithOwner || "") : "",
            "headSha": String(node.headRefOid || ""),
            "additions": Number(node.additions || 0),
            "deletions": Number(node.deletions || 0),
            "changedFiles": Number(node.changedFiles || 0),
            "reviewDecision": String(node.reviewDecision || ""),
            "mergeable": String(node.mergeable || ""),
            "mergeStateStatus": String(node.mergeStateStatus || ""),
            "latestReviews": nodesOf(node.latestReviews).map(review => ({
                        "author": {
                            "login": loginOf(review)
                        },
                        "state": String(review.state || "")
                    })),
            "reviewRequests": nodesOf(node.reviewRequests).map(request => request.requestedReviewer).filter(reviewer => !!reviewer).map(reviewer => ({
                        "type": String(reviewer.__typename || ""),
                        "login": String(reviewer.login || ""),
                        "name": String(reviewer.name || ""),
                        "slug": String(reviewer.slug || "")
                    })),
            "checks": normalizeChecks(contexts),
            "checksState": rollup ? String(rollup.state || "") : "",
            "checksTotal": totalOf(rollup ? rollup.contexts : null, contexts.length),
            "reviews": reviews,
            "reviewsTotal": totalOf(node.reviews, reviews.length),
            "threads": threads,
            "threadsTotal": totalOf(node.reviewThreads, threads.length)
        });
    }
    const summary = node.subIssuesSummary || {};
    const related = list => nodesOf(list).filter(issue => issue.url).map(issue => relatedIssue(issue, repo));
    Object.assign(detail, {
        "linked": nodesOf(node.closedByPullRequestsReferences).map(pr => ({
                    "kind": "pr",
                    "number": Number(pr.number),
                    "url": String(pr.url),
                    "state": String(pr.state || "OPEN"),
                    "isDraft": !!pr.isDraft,
                    "repo": pr.repository ? String(pr.repository.nameWithOwner) : repo
                })).concat(related(node.closingIssuesReferences)),
        "parent": node.parent ? relatedIssue(node.parent, repo) : null,
        "subIssues": related(node.subIssues),
        "subIssuesTotal": Number(summary.total || 0),
        "subIssuesDone": Number(summary.completed || 0),
        "blockedBy": related(node.blockedBy),
        "blocking": related(node.blocking)
    });
    const access = {
        "id": String(node.id || ""),
        "canWrite": canWrite(repository.viewerPermission),
        "canClose": !!node.viewerCanClose,
        "canReopen": !!node.viewerCanReopen,
        "canUpdate": !!node.viewerCanUpdate,
        "canAssign": !!node.viewerCanAssign,
        "locked": !!node.locked,
        "mergeMethod": String(repository.viewerDefaultMergeMethod || "MERGE"),
        "subscription": subscriptionOf(node)
    };
    return {
        "detail": detail,
        "access": access,
        "images": images
    };
}

// The conversation after the description, in time order as on GitHub:
// comments, and reviews with the inline threads they started. A review
// that only answered existing threads is left out, since its replies show
// inside those threads; a thread whose review is past the fetched ones
// stands as its own entry rather than going missing. A reviewer who leaves
// single comments one after another (each its own review with no summary)
// reads as one review with several threads.
function buildTimeline(detail) {
    if (!detail)
        return [];
    const entries = (detail.comments || []).map(comment => ({
                "type": "comment",
                "login": loginOf(comment),
                "at": String(comment.createdAt || ""),
                "url": String(comment.url || ""),
                "body": String(comment.body || ""),
                "state": "",
                "threads": []
            }));
    const reviews = detail.reviews || [];
    const byReview = {};
    const known = {};
    for (const review of reviews)
        known[review.databaseId] = true;
    for (const thread of detail.threads || []) {
        const first = nodesOf(thread.comments)[0] || null;
        const id = first && first.pullRequestReview ? first.pullRequestReview.databaseId : 0;
        if (known[id]) {
            (byReview[id] = byReview[id] || []).push(thread);
        } else if (first) {
            entries.push({
                "type": "review",
                "login": loginOf(first),
                "at": String(first.createdAt || ""),
                "url": String(first.url || ""),
                "body": "",
                "state": "COMMENTED",
                "threads": [thread]
            });
        }
    }
    for (const review of reviews) {
        const threads = byReview[review.databaseId] || [];
        const body = String(review.body || "").trim();
        const verdict = review.state === "APPROVED" || review.state === "CHANGES_REQUESTED";
        if (body === "" && threads.length === 0 && !verdict)
            continue;
        entries.push({
            "type": "review",
            "login": loginOf(review),
            "at": String(review.submittedAt || ""),
            "url": String(review.url || ""),
            "body": body,
            "state": String(review.state || ""),
            "threads": threads
        });
    }
    entries.sort((a, b) => a.at.localeCompare(b.at));
    const grouped = [];
    for (const entry of entries) {
        const last = grouped.length > 0 ? grouped[grouped.length - 1] : null;
        const close = last && Math.abs(new Date(entry.at).getTime() - new Date(last.at).getTime()) < 15 * 60000;
        if (last && close && last.type === "review" && entry.type === "review" && last.login === entry.login && last.state === entry.state && entry.body === "" && last.body === "") {
            last.threads = last.threads.concat(entry.threads);
            last.at = entry.at;
            continue;
        }
        grouped.push(Object.assign({}, entry));
    }
    return grouped;
}

// The code a thread talks about: the end of its diff hunk, the way
// github.com shows it above the first comment.
function hunkLines(hunk) {
    return String(hunk || "").split("\n").filter(line => line.indexOf("@@") !== 0).slice(-4);
}

// Pairs each image a Markdown body names with the signed URL its rendered
// HTML loads, in document order. Emoji images exist only in the HTML and
// are skipped; a body whose counts disagree pairs what GitHub marked with
// its canonical source and leaves the rest as links.
function imagePairs(markdown, html, into) {
    const wanted = [];
    const md = String(markdown || "");
    const pattern = /!\[[^\]]*\]\(\s*<?([^)\s>]+)|<img\b[^>]*\bsrc=["']([^"']+)["']/gi;
    let m;
    while ((m = pattern.exec(md)) !== null)
        wanted.push(m[1] || m[2]);
    const shown = [];
    const tags = String(html || "").match(/<img\b[^>]*>/gi) || [];
    for (const tag of tags) {
        if (/class="[^"]*emoji/i.test(tag))
            continue;
        const src = tag.match(/\bsrc="([^"]+)"/i);
        const canonical = tag.match(/\bdata-canonical-src="([^"]+)"/i);
        if (src)
            shown.push({
                "src": src[1].replace(/&amp;/g, "&"),
                "canonical": canonical ? canonical[1].replace(/&amp;/g, "&") : ""
            });
    }
    for (let i = 0; i < wanted.length; i++) {
        if (wanted.length === shown.length) {
            into[wanted[i]] = shown[i].src;
        } else {
            const match = shown.find(entry => entry.canonical === wanted[i]);
            if (match)
                into[wanted[i]] = match.src;
        }
    }
}

// ------------------------------------------------------------ formatting

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];

// How long ago, as a row says it: now, 5m, 3h, 2d, then the date the way
// github.com writes it (the day always, the year once it is not this one).
function ago(iso, now) {
    const ms = new Date(String(iso || "")).getTime();
    if (!isFinite(ms))
        return "";
    const current = typeof now === "number" ? now : Date.now();
    const minutes = Math.floor((current - ms) / 60000);
    if (minutes < 1)
        return "now";
    if (minutes < 60)
        return minutes + "m";
    const hours = Math.floor(minutes / 60);
    if (hours < 24)
        return hours + "h";
    const days = Math.floor(hours / 24);
    if (days < 30)
        return days + "d";
    const date = new Date(ms);
    const day = MONTHS[date.getMonth()] + " " + date.getDate();
    return date.getFullYear() === new Date(current).getFullYear() ? day : day + ", " + date.getFullYear();
}

// The same, as a post header says it: just now, 5m ago, on Mar 4.
function when(iso, now) {
    const text = ago(iso, now);
    if (text === "" || text === "now")
        return text === "" ? "" : "just now";
    return /^\d+[mhd]$/.test(text) ? text + " ago" : "on " + text;
}

// A time GitHub has not set yet reads 0001-01-01, which gives nothing.
function duration(fromIso, toIso, now) {
    const from = new Date(String(fromIso || "")).getTime();
    const to = toIso ? new Date(String(toIso)).getTime() : (typeof now === "number" ? now : Date.now());
    if (!isFinite(from) || !isFinite(to) || to < from || new Date(from).getFullYear() < 2000)
        return "";
    const seconds = Math.round((to - from) / 1000);
    if (seconds < 60)
        return seconds + "s";
    const minutes = Math.floor(seconds / 60);
    if (minutes < 60)
        return minutes + "m " + (seconds % 60) + "s";
    return Math.floor(minutes / 60) + "h " + (minutes % 60) + "m";
}

// A copy of an object with one key set, or removed when the value is
// undefined, for the properties that must be reassigned to notify.
// `list` with the entries of `more` it does not have yet, by `key` ("url"
// for rows, "id" for threads), in order.
function appendNew(list, more, key) {
    const seen = {};
    for (const entry of list)
        seen[entry[key]] = true;
    return list.concat(more.filter(entry => !seen[entry[key]] && (seen[entry[key]] = true)));
}

function withKey(object, key, value) {
    const next = Object.assign({}, object);
    if (value === undefined)
        delete next[key];
    else
        next[key] = value;
    return next;
}

// ------------------------------------------------------------- Markdown
//
// GitHub-flavored Markdown as the popout carries it, parsed into blocks
// that each render as their own item, with inline markup as rich text in
// the theme's colors. Supported: ATX headings; paragraphs with hard line
// breaks kept; bold, italic, strikethrough (** __ * _ ~~); inline code;
// links, autolinks, and bare URLs; images (a line of images shows them,
// an image inside prose is a link); `#123` and `@user` as GitHub links;
// bullet, numbered, nested, and task lists; block quotes; fenced code
// (``` and ~~~); pipe tables; horizontal rules. HTML comments and the tags
// GitHub bodies use for layout (details, summary, picture, p, div, span,
// kbd, sub, sup, center, headings, ...) are dropped for their text, and
// <img> and <br> become an image and a line break, all outside code:
// fenced code and inline code keep every character. Anything else reads as
// its text.
//
// style: { link, codeFont, codeSize, codeBackground, codeText, border }.

function linkHtml(url, html, style) {
    return "<a href=\"" + escapeHtml(url) + "\" style=\"text-decoration:none\"><span style=\"color:" + String(style.link) + "\">" + html + "</span></a>";
}

// GitHub links read as references (owner/repo#12), other links as their
// host and path.
function linkLabel(url, repo) {
    const ref = url.match(/^https:\/\/github\.com\/([\w.-]+\/[\w.-]+)\/(?:pull|issues)\/(\d+)\/?$/);
    if (ref)
        return (ref[1] === repo ? "" : ref[1]) + "#" + ref[2];
    const bare = url.replace(/^https?:\/\//, "").replace(/\/$/, "");
    return bare.length > 48 ? bare.slice(0, 45) + "…" : bare;
}

function codeSpanHtml(code, style) {
    return "<span style=\"font-family:'" + style.codeFont + "'; font-size:" + Math.round(style.codeSize) + "px; background-color:" + String(style.codeBackground) + "; color:" + String(style.codeText) + "\">&nbsp;" + escapeHtml(code) + "&nbsp;</span>";
}

function emphasis(s) {
    s = s.replace(/\*\*(?=\S)([\s\S]*?\S)\*\*/g, "<b>$1</b>");
    s = s.replace(/__(?=\S)([\s\S]*?\S)__/g, "<b>$1</b>");
    s = s.replace(/(^|[^*\w])\*(?=\S)([^*\n]*?\S)\*(?!\w)/g, "$1<i>$2</i>");
    s = s.replace(/(^|[^_\w])_(?=\S)([^_\n]*?\S)_(?!\w)/g, "$1<i>$2</i>");
    s = s.replace(/~~(?=\S)([\s\S]*?\S)~~/g, "<s>$1</s>");
    return s;
}

// Sets text aside behind a marker no body contains (its index between two
// control characters) while the rest is rewritten, and puts it back.
function stasher() {
    const kept = [];
    return {
        "keep": text => {
            kept.push(text);
            return "\u0001" + (kept.length - 1) + "\u0002";
        },
        "restore": text => text.replace(/\u0001(\d+)\u0002/g, (m, i) => kept[Number(i)])
    };
}

function inlineHtml(text, repo, style) {
    const stash = stasher();
    const keep = stash.keep;
    let s = String(text || "");
    s = s.replace(/(`+)([^`]|[^`][\s\S]*?[^`])\1(?!`)/g, (m, ticks, code) => keep(codeSpanHtml(code.trim(), style)));
    s = s.replace(/!\[([^\]]*)\]\(\s*<?([^)\s>]+)>?[^)]*\)/g, (m, alt, url) => keep(linkHtml(url, escapeHtml(alt || "image"), style)));
    s = s.replace(/\[([^\]]+)\]\(([^)\s]+)(?:\s+"[^"]*")?\)/g, (m, label, url) => keep(linkHtml(url, emphasis(escapeHtml(label)), style)));
    s = s.replace(/<(https?:\/\/[^>\s]+)>/g, (m, url) => keep(linkHtml(url, escapeHtml(linkLabel(url, repo)), style)));
    s = s.replace(/https?:\/\/[^\s<>()]+[^\s<>().,;:!?'"]/g, url => keep(linkHtml(url, escapeHtml(linkLabel(url, repo)), style)));
    s = escapeHtml(s);
    s = s.replace(/(^|[^\w/`])@([A-Za-z0-9](?:[A-Za-z0-9-]{0,38}))(?![\w-])/g, (m, pre, user) => pre + keep(linkHtml(profileUrl(user), "@" + user, style)));
    if (repo !== "")
        s = s.replace(/(^|[^\w&/])#(\d+)\b/g, (m, pre, n) => pre + keep(linkHtml(repoUrl(repo) + "/issues/" + n, "#" + n, style)));
    s = emphasis(s);
    s = s.replace(/\n/g, "<br>");
    return stash.restore(s);
}

// Drops HTML comments and layout tags for their text, outside code: fenced
// blocks and inline code spans are set aside first and put back as written.
function cleanMarkdown(text) {
    const stash = stasher();
    const keep = stash.keep;
    const lines = String(text || "").replace(/\r\n/g, "\n").split("\n");
    const out = [];
    for (let i = 0; i < lines.length; i++) {
        const fence = lines[i].match(/^\s*(`{3,}|~{3,})/);
        if (!fence) {
            out.push(lines[i]);
            continue;
        }
        const block = [lines[i]];
        let j = i + 1;
        while (j < lines.length && lines[j].trim().indexOf(fence[1]) !== 0)
            block.push(lines[j++]);
        if (j < lines.length)
            block.push(lines[j]);
        out.push(keep(block.join("\n")));
        i = j;
    }
    let s = out.join("\n");
    s = s.replace(/(`+)([^`]|[^`][\s\S]*?[^`])\1(?!`)/g, span => keep(span));
    s = s.replace(/<!--[\s\S]*?-->/g, "");
    s = s.replace(/<img\b[^>]*>/gi, tag => {
        const src = tag.match(/\bsrc=["']([^"']+)["']/i);
        const alt = tag.match(/\balt=["']([^"']*)["']/i);
        return src ? "![" + (alt ? alt[1] : "image") + "](" + src[1] + ")" : "";
    });
    s = s.replace(/<br\s*\/?>/gi, "\n");
    s = s.replace(/<\/?(details|summary|picture|source|sub|sup|p|div|span|kbd|b|i|em|strong|a|ins|del|center|h[1-6])\b[^>]*>/gi, "");
    s = s.replace(/\n{3,}/g, "\n\n").trim();
    return stash.restore(s);
}

function isListLine(line) {
    return /^\s*([-*+]|\d+[.)])\s+/.test(line);
}

// A line holding nothing but images (each possibly wrapped in a link) shows
// them as pictures; an image inside prose stays a link.
function isImageLine(line) {
    return /^\s*((\[\s*)?!\[[^\]]*\]\(\s*<?[^)\s>]+>?[^)]*\)(\s*\]\([^)]*\))?\s*)+$/.test(line);
}

function lineImages(line) {
    const found = [];
    const pattern = /(?:\[\s*)?!\[([^\]]*)\]\(\s*<?([^)\s>]+)>?[^)]*\)(?:\s*\]\(([^)\s]+)[^)]*\))?/g;
    let m;
    while ((m = pattern.exec(line)) !== null)
        found.push({
            "type": "image",
            "alt": m[1] || "image",
            "url": m[2],
            "href": m[3] || m[2],
            "size": m[0].length
        });
    return found;
}

function startsBlock(line) {
    return /^\s*(```|~~~|#{1,6}\s|>)/.test(line) || isListLine(line) || isImageLine(line);
}

function tableCells(line) {
    return line.trim().replace(/^\|/, "").replace(/\|$/, "").split("|").map(cell => cell.trim());
}

function tableHtml(rows, repo, style) {
    let html = "<table border=\"1\" cellspacing=\"0\" cellpadding=\"5\" style=\"border-collapse:collapse; border-color:" + String(style.border) + "\">";
    for (let r = 0; r < rows.length; r++) {
        html += "<tr>";
        for (const cell of rows[r]) {
            const inner = inlineHtml(cell, repo, style);
            html += r === 0 ? "<th align=\"left\">" + inner + "</th>" : "<td>" + inner + "</td>";
        }
        html += "</tr>";
    }
    return html + "</table>";
}

// The blocks of a body: { type, html | text | items | url, size }, size
// being how much of the source the block holds (for cutting a long body).
function parseMarkdown(text, repo, style) {
    const lines = cleanMarkdown(text).split("\n");
    const blocks = [];
    const add = (block, source) => {
        block.size = source.length;
        blocks.push(block);
    };
    let i = 0;
    while (i < lines.length) {
        const line = lines[i];
        let m;
        if (line.trim() === "") {
            i++;
            continue;
        }
        if ((m = line.match(/^\s*(`{3,}|~{3,})/))) {
            const fence = m[1];
            const body = [];
            i++;
            while (i < lines.length && lines[i].trim().indexOf(fence) !== 0)
                body.push(lines[i++]);
            i++;
            add({
                "type": "code",
                "text": body.join("\n"),
                "lines": body.length
            }, body.join("\n"));
            continue;
        }
        if ((m = line.match(/^(#{1,6})\s+(.+?)\s*#*\s*$/))) {
            add({
                "type": "heading",
                "level": m[1].length,
                "html": inlineHtml(m[2], repo, style)
            }, line);
            i++;
            continue;
        }
        if (isImageLine(line)) {
            for (const image of lineImages(line))
                blocks.push(image);
            i++;
            continue;
        }
        if (/^\s*([-*_])(\s*\1){2,}\s*$/.test(line)) {
            add({
                "type": "rule"
            }, line);
            i++;
            continue;
        }
        if (/^\s*>/.test(line)) {
            const body = [];
            while (i < lines.length && /^\s*>/.test(lines[i]))
                body.push(lines[i++].replace(/^\s*>\s?/, ""));
            add({
                "type": "quote",
                "html": inlineHtml(body.join("\n").trim(), repo, style)
            }, body.join("\n"));
            continue;
        }
        if (/^\s*\|.*\|\s*$/.test(line) && i + 1 < lines.length && /^\s*\|?\s*:?-{3,}/.test(lines[i + 1])) {
            const source = [line];
            const rows = [tableCells(line)];
            i += 2;
            while (i < lines.length && /^\s*\|.*\|\s*$/.test(lines[i])) {
                source.push(lines[i]);
                rows.push(tableCells(lines[i++]));
            }
            add({
                "type": "table",
                "html": tableHtml(rows, repo, style)
            }, source.join("\n"));
            continue;
        }
        if (isListLine(line)) {
            const items = [];
            const indents = [];
            const source = [];
            while (i < lines.length) {
                const l = lines[i];
                if (l.trim() === "") {
                    let j = i + 1;
                    while (j < lines.length && lines[j].trim() === "")
                        j++;
                    if (j < lines.length && isListLine(lines[j])) {
                        i = j;
                        continue;
                    }
                    break;
                }
                const lm = l.match(/^(\s*)([-*+]|\d+[.)])\s+(.*)$/);
                if (lm) {
                    const indent = lm[1].replace(/\t/g, "    ").length;
                    if (indents.indexOf(indent) < 0)
                        indents.push(indent);
                    let body = lm[3];
                    let task = "";
                    const tm = body.match(/^\[([ xX])\]\s+(.*)$/);
                    if (tm) {
                        task = tm[1] === " " ? "open" : "done";
                        body = tm[2];
                    }
                    items.push({
                        "indent": indent,
                        "marker": /\d/.test(lm[2]) ? lm[2].replace(")", ".") : "",
                        "task": task,
                        "text": body
                    });
                    source.push(l);
                    i++;
                } else if (/^\s+\S/.test(l) && items.length > 0) {
                    items[items.length - 1].text += "\n" + l.trim();
                    source.push(l);
                    i++;
                } else {
                    break;
                }
            }
            indents.sort((a, b) => a - b);
            add({
                "type": "list",
                "items": items.map(item => ({
                            "level": Math.min(indents.indexOf(item.indent), 4),
                            "marker": item.marker,
                            "task": item.task,
                            "html": inlineHtml(item.text, repo, style)
                        }))
            }, source.join("\n"));
            continue;
        }
        const body = [lines[i++]];
        while (i < lines.length && lines[i].trim() !== "" && !startsBlock(lines[i]))
            body.push(lines[i++]);
        add({
            "type": "paragraph",
            "html": inlineHtml(body.join("\n"), repo, style)
        }, body.join("\n"));
    }
    return blocks;
}

// How many leading blocks fit a budget of source characters; at least one.
function blocksWithin(blocks, budget) {
    let used = 0;
    for (let i = 0; i < blocks.length; i++) {
        used += blocks[i].size || 0;
        if (used > budget)
            return Math.max(1, i);
    }
    return blocks.length;
}
