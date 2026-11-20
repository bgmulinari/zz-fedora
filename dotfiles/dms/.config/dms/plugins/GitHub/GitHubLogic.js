.pragma library

// The GitHub plugin's pure logic: what each list asks GitHub, how GitHub's
// answers become rows and pages, how links and job logs are read, and the
// rules for what a change hides or announces (GitHubMarkdown.js reads the
// bodies). Nothing here touches QML, gh, or the clock unless handed one, so
// GitHubData and the views call it and tests/support/github_logic.js runs
// it under Node.

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
    // GitHub's default inbox filters, in its order.
    "inbox": [
        {
            "key": "all",
            "label": "All"
        },
        {
            "key": "assign",
            "label": "Assigned"
        },
        {
            "key": "participating",
            "label": "Participating"
        },
        {
            "key": "mention",
            "label": "Mentioned"
        },
        {
            "key": "team_mention",
            "label": "Team mentioned"
        },
        {
            "key": "review_requested",
            "label": "Review requested"
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

// What a search typed over a list asks GitHub (its advanced search, which
// reads AND, OR, and parentheses as github.com does): the list's search
// in every state, then the words. GitHub sorts by the first sort: it
// reads, so a typed one takes the list's place. Words with AND, OR, or
// parentheses go in parentheses of their own: bare, GitHub would read the
// list's qualifiers as one side of an OR and search all of GitHub on the
// other. What is still being written waits until it is whole: a
// qualifier without its value (label:), a lone dash, a quote not closed
// yet, an AND or OR with nothing on one side, a parenthesis not closed.
function listSearch(key, words) {
    const tokens = typedTerms(words);
    const sort = tokens.find(word => /^sort:\S/i.test(word));
    const rest = tokens.filter(word => !/^sort:/i.test(word));
    let base = searchBase(key);
    if (sort)
        base = base.replace(/(^|\s)sort:\S+/g, "") + " " + sort;
    let terms = rest.join(" ");
    if (/(^|\s)(AND|OR)(\s|$)|[()]/.test(terms))
        terms = "(" + terms + ")";
    return (base + " " + terms).trim();
}

// The whole words of a typed search (see listSearch).
function typedTerms(text) {
    const operator = word => word === "AND" || word === "OR";
    const out = searchTokens(text).map(token => token.text).filter(word => word !== "-" && !/^-?[a-zA-Z][\w-]*:"?$/.test(word) && (word.split("\"").length - 1) % 2 === 0);
    while (out.length > 0 && operator(out[0]))
        out.shift();
    while (out.length > 0 && (operator(out[out.length - 1]) || /^-?\($/.test(out[out.length - 1])))
        out.pop();
    const open = out.join(" ").split("(").length - out.join(" ").split(")").length;
    if (open > 0)
        out[out.length - 1] += ")".repeat(open);
    return out;
}

// What a typed search asks of the loaded rows, which can only be read for
// words: [word], lowercased, without a sort: (which narrows nothing), or
// null when the search has qualifiers or operators only GitHub can read,
// and so no loaded row stands for its answer.
function rowWords(text) {
    const words = [];
    for (const word of typedTerms(text)) {
        if (/^sort:/i.test(word))
            continue;
        if (qualifierOf(word) || word === "AND" || word === "OR" || /[()]/.test(word) || word.charAt(0) === "-")
            return null;
        words.push(word.replace(/"/g, "").toLowerCase());
    }
    return words;
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
        "labels": labelsOf(node.labels),
        // The node, for what the rows on screen ask for apart (extrasOf).
        "nodeId": String(node.id || ""),
        // An issue's sub-issues, done and in all, beside its title.
        "subIssues": kind === "issue" && node.subIssuesSummary && node.subIssuesSummary.total > 0 ? {
            "completed": Number(node.subIssuesSummary.completed || 0),
            "total": Number(node.subIssuesSummary.total)
        } : null
    };
}

// Where a row's links stand, for the icon beside their count: the one that
// says most of the first few, as github.com's lists draw it. An issue's
// pull requests: open, then draft, merged, closed; a pull request's
// issues: open, then completed, not planned.
var LINK_GLYPHS = {
    "open": glyph("git-pull-request", "success"),
    "draft": glyph("git-pull-request-draft", "muted"),
    "merged": glyph("git-merge", "accent"),
    "closed": glyph("git-pull-request-closed", "error"),
    "issueOpen": glyph("issue-opened", "success"),
    "completed": glyph("issue-closed", "accent"),
    "notPlanned": glyph("skip", "muted")
};

function linkState(kind, links) {
    const states = links.map(link => {
        const state = String(link.state || "");
        if (kind === "pr")
            return state === "OPEN" ? "issueOpen" : (String(link.stateReason || "") === "NOT_PLANNED" || String(link.stateReason || "") === "DUPLICATE" ? "notPlanned" : "completed");
        if (state === "OPEN")
            return link.isDraft ? "draft" : "open";
        return state === "MERGED" ? "merged" : "closed";
    });
    const order = kind === "pr" ? ["issueOpen", "completed", "notPlanned"] : ["open", "draft", "merged", "closed"];
    return order.find(state => states.indexOf(state) >= 0) || (kind === "pr" ? "issueOpen" : "open");
}

// What queries/inbox.graphql's Extras answers for the rows on screen, by
// url: { updatedAt, assignees (the first three logins), assigneeCount,
// linked (the pull requests an issue is linked to, or the issues a pull
// request closes), linkGlyph (Octicon and tone for where they stand) }.
function extrasOf(data) {
    const out = {};
    for (const node of nodesOf(data ? {
        "nodes": data.nodes
    } : null)) {
        if (!node.url)
            continue;
        const assignees = nodesOf(node.assignees).map(user => String(user.login || "")).filter(login => login !== "");
        const kind = node.__typename === "PullRequest" ? "pr" : "issue";
        const links = kind === "pr" ? node.closingIssuesReferences : node.closedByPullRequestsReferences;
        out[String(node.url)] = {
            "updatedAt": String(node.updatedAt || ""),
            "assignees": assignees,
            "assigneeCount": totalOf(node.assignees, assignees.length),
            "linked": totalOf(links, nodesOf(links).length),
            "linkGlyph": LINK_GLYPHS[linkState(kind, nodesOf(links))]
        };
    }
    return out;
}

// Which of the columns on the right of a list's pull request and issue rows
// any row fills, so each row keeps a slot for them (and only them) and the
// columns line up as on github.com: checks, links, comments, assignees.
// `extras` are the rows' extrasOf answers, by url.
function rowColumns(items, extras) {
    const has = {
        "checks": false,
        "linked": false,
        "comments": false,
        "assignees": false
    };
    for (const item of items || []) {
        if (!item || (item.kind !== "pr" && item.kind !== "issue"))
            continue;
        const extra = (extras || {})[item.url] || {};
        has.checks = has.checks || !!item.checks;
        has.linked = has.linked || extra.linked > 0;
        has.comments = has.comments || item.comments > 0;
        has.assignees = has.assignees || (extra.assignees || []).length > 0;
    }
    return has;
}

// The words of a list search in the loaded rows: every word somewhere in
// what the row shows.
function rowMatches(item, words) {
    const parts = [item.title, item.repo, String(item.number || ""), item.author, item.displayTitle, item.workflowName, item.headBranch, item.event, item.reason ? REASONS[item.reason] : ""];
    const haystack = parts.concat((item.labels || []).map(label => label.name || label)).filter(part => !!part).join(" ").toLowerCase();
    return words.every(word => haystack.indexOf(word) >= 0);
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

// What the inbox does to a thread, in github.com's order: under the pointer
// on a row, in the bar over checked rows, and by key (hint: the footer's
// word for it). `unreadOnly` offers it only for an unread thread.
var INBOX_ACTIONS = [
    {
        "key": "done",
        "icon": "check",
        "label": "Done",
        "shortcut": "Del",
        "hint": "done"
    },
    {
        "key": "read",
        "icon": "drafts",
        "label": "Mark as read",
        "shortcut": "Ctrl+I",
        "hint": "read",
        "unreadOnly": true
    },
    {
        "key": "unsubscribe",
        "icon": "notifications_off",
        "label": "Unsubscribe",
        "shortcut": "Ctrl+M",
        "hint": "unsubscribe"
    }
];

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
        "unread": !!thread.unread,
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

// The reasons that come from watching a repository rather than taking part
// in a thread; every other thread is one the viewer participates in, as
// the notifications API's participating=true answers.
var WATCHING_REASONS = ["subscribed", "ci_activity", "security_alert"];

function isParticipating(thread) {
    return WATCHING_REASONS.indexOf(thread.reason) < 0;
}

function filterThreads(threads, key) {
    if (key === "all")
        return threads;
    if (key === "participating")
        return threads.filter(isParticipating);
    return threads.filter(thread => thread.reason === key);
}

// ------------------------------------------------------ inbox search
//
// github.com's inbox filters by qualifiers rather than text: is: (read,
// unread, or what the subject is), reason:, repo:, org:, and author: (who
// opened the subject). Values of one qualifier widen the search (any of
// them), different qualifiers narrow it (all of them), and the words that
// are left match the row's text, which GitHub's own inbox cannot search.
// The notifications API keeps nothing saved or done, so is:saved and
// is:done have nothing to show here.

var SUBJECT_TYPES = {
    "check-suite": ["CheckSuite"],
    "commit": ["Commit"],
    "gist": ["Gist"],
    "issue-or-pull-request": ["Issue", "PullRequest"],
    "issue": ["Issue"],
    "pr": ["PullRequest"],
    "pull-request": ["PullRequest"],
    "release": ["Release"],
    "repository-invitation": ["RepositoryInvitation"],
    "repository-vulnerability-alert": ["RepositoryVulnerabilityAlert", "RepositoryDependabotAlertsThread"],
    "repository-advisory": ["RepositoryAdvisory"],
    "discussion": ["Discussion"]
};
var INBOX_QUALIFIERS = ["is", "reason", "repo", "org", "author"];

// The words of a search with where each is: [{ start, end, text }]. A
// quoted value is one word, spaces and all (label:"good first issue").
function searchTokens(text) {
    const s = String(text || "");
    const out = [];
    let i = 0;
    while (i < s.length) {
        if (/\s/.test(s[i])) {
            i++;
            continue;
        }
        const start = i;
        let quoted = false;
        while (i < s.length && (quoted || !/\s/.test(s[i]))) {
            if (s[i] === '"')
                quoted = !quoted;
            i++;
        }
        out.push({
            "start": start,
            "end": i,
            "text": s.slice(start, i)
        });
    }
    return out;
}

// A word read as a qualifier: { exclude, name, value } (the name
// lowercased, the value without its quotes), or null for a plain word.
function qualifierOf(word) {
    const match = String(word || "").match(/^(-?)([a-zA-Z][\w-]*):(.*)$/);
    if (!match)
        return null;
    return {
        "exclude": match[1] === "-",
        "name": match[2].toLowerCase(),
        "value": match[3].replace(/"/g, "")
    };
}

// A search over what is loaded, read against the qualifiers it knows:
// { qualifiers: { name: [value] }, excluded: { name: [value] }, words },
// the values lowercased; any other word is a word of the rows. A known
// qualifier still without its value (label: as it is being written)
// narrows nothing yet.
function localQuery(text, known) {
    const out = {
        "qualifiers": {},
        "excluded": {},
        "words": []
    };
    for (const token of searchTokens(text)) {
        const q = qualifierOf(token.text);
        if (!q || known.indexOf(q.name) < 0) {
            out.words.push(token.text.replace(/"/g, "").toLowerCase());
            continue;
        }
        if (q.value === "")
            continue;
        const into = q.exclude ? out.excluded : out.qualifiers;
        into[q.name] = (into[q.name] || []).concat([q.value.toLowerCase()]);
    }
    return out;
}

// Whether a local query's qualifiers pass, given a test per qualifier.
function qualifiersPass(query, tests) {
    for (const name in query.qualifiers)
        if (!query.qualifiers[name].some(tests[name]))
            return false;
    for (const name in query.excluded)
        if (query.excluded[name].some(tests[name]))
            return false;
    return true;
}

// { qualifiers: { name: [value] }, excluded, words: [word], unsupported:
// "" }: the value lowercased, dashes and underscores alike. A qualifier
// with a dash before it (-reason:subscribed) leaves out what it matches.
function inboxQuery(text) {
    const out = Object.assign(localQuery(text, INBOX_QUALIFIERS), {
        "unsupported": ""
    });
    for (const into of [out.qualifiers, out.excluded]) {
        for (const name of ["is", "reason"])
            if (into[name])
                into[name] = into[name].map(value => value.replace(/_/g, "-"));
        const kept = (into.is || []).filter(value => value !== "saved" && value !== "done");
        if (into.is && kept.length < into.is.length) {
            const value = into.is.find(other => kept.indexOf(other) < 0);
            out.unsupported = "GitHub's API does not share " + value + " notifications, so is:" + value + " works on github.com only.";
            if (kept.length > 0)
                into.is = kept;
            else
                delete into.is;
        }
    }
    return out;
}

// Whether a thread passes a query from inboxQuery. `unread` is whether it
// is unread now, and `author` who opened its subject, "" while unknown.
function threadMatches(thread, query, unread, author) {
    const repo = String(thread.repo || "").toLowerCase();
    // An app answers to its name, its bot's login, and app/name alike.
    const person = name => String(name || "").toLowerCase().replace(/^app\//, "").replace(/\[bot\]$/, "");
    const login = person(author);
    const passes = qualifiersPass(query, {
        "is": value => value === "unread" ? unread : (value === "read" ? !unread : (SUBJECT_TYPES[value] || []).indexOf(thread.type) >= 0),
        "reason": value => value === "participating" ? isParticipating(thread) : thread.reason === value.replace(/-/g, "_"),
        "repo": value => repo === value,
        "org": value => repo.split("/")[0] === value,
        "author": value => login !== "" && login === person(value)
    });
    return passes && (query.words.length === 0 || rowMatches(thread, query.words));
}

// What a notification's subject is now (its state and who opened it),
// which the notifications API leaves out. One GraphQL request looks up a
// page of them, each repository once: { query, vars, keys }, where keys
// maps each alias to the subject's url. Names travel as variables, never
// inside the query.
var SUBJECT_FIELDS = "__typename ... on PullRequest { state isDraft author { __typename login } } ... on Issue { state stateReason author { __typename login } }";

function subjectsQuery(threads) {
    const repos = {};
    for (const thread of threads) {
        if ((thread.type !== "PullRequest" && thread.type !== "Issue") || !(thread.number > 0) || !isRepo(thread.repo))
            continue;
        const list = repos[thread.repo] || (repos[thread.repo] = []);
        if (!list.some(other => other.number === thread.number))
            list.push(thread);
    }
    const params = [];
    const parts = [];
    const vars = {};
    const keys = {};
    let r = 0;
    for (const repo in repos) {
        const [owner, name] = repo.split("/");
        vars["o" + r] = owner;
        vars["n" + r] = name;
        params.push("$o" + r + ": String!", "$n" + r + ": String!");
        const inner = repos[repo].map((thread, i) => {
            const alias = "r" + r + "s" + i;
            vars["k" + alias] = thread.number;
            params.push("$k" + alias + ": Int!");
            keys[alias] = thread.url;
            return alias + ": issueOrPullRequest(number: $k" + alias + ") { " + SUBJECT_FIELDS + " }";
        });
        parts.push("r" + r + ": repository(owner: $o" + r + ", name: $n" + r + ") { " + inner.join(" ") + " }");
        r++;
    }
    return {
        "query": parts.length === 0 ? "" : "query Subjects(" + params.join(", ") + ") { " + parts.join(" ") + " }",
        "vars": vars,
        "keys": keys
    };
}

// The answer to subjectsQuery: url -> { kind, state, isDraft, stateReason,
// author }. A repository GitHub cannot show (deleted, or no longer
// readable) leaves its subjects out.
function subjectsOf(data, keys) {
    const out = {};
    for (const repoAlias in (data || {})) {
        const repo = data[repoAlias];
        for (const alias in (repo || {})) {
            const node = repo[alias];
            if (!node || !keys[alias] || (node.__typename !== "PullRequest" && node.__typename !== "Issue"))
                continue;
            out[keys[alias]] = {
                "kind": node.__typename === "PullRequest" ? "pr" : "issue",
                "state": String(node.state || "OPEN"),
                "isDraft": !!node.isDraft,
                "stateReason": String(node.stateReason || ""),
                "author": node.author ? String(node.author.login || "") : ""
            };
        }
    }
    return out;
}

// The next page of an inbox continues before the oldest thread loaded, not
// at a page number: marking threads done shrinks the inbox, which would
// shift numbered pages over threads not yet seen. A
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

// ---------------------------------------------------------- automations
//
// The settings' automations: [{ reason, type, repo, command }], picked in
// the settings rather than typed: why the notification came (a key of
// REASONS), what its subject is (a key of NOTIFICATION_ICONS), and
// optionally where (owner/name, or an owner for any of theirs); an empty
// field matches anything. command is a shell command line, run for each
// thread announce() finds new that matches. The thread travels in the
// environment, never inside the command line, since its title is anyone's
// words.

// The settings' choices, [value, label], "" for anything: the reasons that
// concern you first, then the rest as REASONS names them.
var AUTOMATION_DIRECT_REASONS = ["review_requested", "assign", "mention", "team_mention", "approval_requested", "author", "comment"];
var AUTOMATION_REASONS = [["", "Any reason"]].concat(AUTOMATION_DIRECT_REASONS.concat(Object.keys(REASONS).filter(key => AUTOMATION_DIRECT_REASONS.indexOf(key) < 0).sort((a, b) => REASONS[a].localeCompare(REASONS[b]))).map(key => [key, REASONS[key]]));
var AUTOMATION_TYPES = [["", "Anything"], ["PullRequest", "Pull request"], ["Issue", "Issue"], ["Discussion", "Discussion"], ["Release", "Release"], ["Commit", "Commit"], ["CheckSuite", "Actions run"], ["RepositoryVulnerabilityAlert", "Security alert"]];

function automationLabel(choices, value) {
    const found = choices.find(choice => choice[0] === value);
    return found ? found[1] : String(value || "");
}

// Whether a rule's repository field says where: empty for anywhere,
// owner/name, or an owner for any of theirs.
function automationRepoValid(repo) {
    const value = String(repo || "").trim();
    return value === "" || isRepo(value) || /^[\w.-]+$/.test(value);
}

// The rules worth running, each read once: [{ reason, type, repo,
// command }], the repository lowercased. A rule without a command, or
// with a repository that names neither an owner nor owner/name, does
// nothing.
function automationRules(entries) {
    const rules = [];
    for (const entry of Array.isArray(entries) ? entries : []) {
        if (!entry || typeof entry !== "object")
            continue;
        const command = String(entry.command || "").trim();
        const repo = String(entry.repo || "").trim().toLowerCase();
        if (command === "" || !automationRepoValid(repo))
            continue;
        rules.push({
            "reason": String(entry.reason || ""),
            "type": String(entry.type || ""),
            "repo": repo,
            "command": command
        });
    }
    return rules;
}

// The rules a thread matches. A security alert comes as either type.
function automationsFor(rules, thread) {
    const repo = String(thread.repo || "").toLowerCase();
    const type = thread.type === "RepositoryDependabotAlertsThread" ? "RepositoryVulnerabilityAlert" : thread.type;
    return rules.filter(rule => (rule.reason === "" || rule.reason === thread.reason) && (rule.type === "" || rule.type === type) && (rule.repo === "" || (rule.repo.indexOf("/") >= 0 ? repo === rule.repo : repo.split("/")[0] === rule.repo)));
}

// A rule as the settings list it: "Review requested · Pull request · in
// owner/name".
function automationSummary(rule) {
    const parts = [automationLabel(AUTOMATION_REASONS, String(rule.reason || "")), automationLabel(AUTOMATION_TYPES, String(rule.type || ""))];
    const repo = String(rule.repo || "").trim();
    if (repo !== "")
        parts.push("in " + repo);
    return parts.join(" · ");
}

// The environment a command runs with: the thread, and the account it
// came to.
function automationEnvironment(thread, login) {
    return {
        "GITHUB_NOTIFICATION_ID": String(thread.id || ""),
        "GITHUB_NOTIFICATION_REASON": String(thread.reason || ""),
        "GITHUB_NOTIFICATION_TYPE": String(thread.type || ""),
        "GITHUB_NOTIFICATION_REPO": String(thread.repo || ""),
        "GITHUB_NOTIFICATION_NUMBER": thread.number > 0 ? String(thread.number) : "",
        "GITHUB_NOTIFICATION_TITLE": String(thread.title || ""),
        "GITHUB_NOTIFICATION_URL": String(thread.url || ""),
        "GITHUB_NOTIFICATION_UPDATED_AT": String(thread.updatedAt || ""),
        "GITHUB_NOTIFICATION_ACCOUNT": String(login || "")
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
// notification says what its subject is until its state is known
// (subjectsOf), and then shows as that subject.
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

// The Actions tab's search, as github.com's filter over runs: workflow:,
// branch:, event:, status: (a run's status or its conclusion), and, over
// every repository, repo:; a dash before one leaves out what it matches,
// and the words left match the row's text.
var RUN_QUALIFIERS = ["workflow", "branch", "event", "status", "repo"];

function runsQuery(text) {
    return localQuery(text, RUN_QUALIFIERS);
}

function runMatches(run, query) {
    const lower = value => String(value || "").toLowerCase();
    const passes = qualifiersPass(query, {
        "workflow": value => lower(run.workflowName) === value,
        "branch": value => lower(run.headBranch) === value,
        "event": value => lower(run.event) === value,
        "status": value => lower(run.status) === value || lower(run.conclusion) === value,
        "repo": value => lower(run.repo) === value
    });
    return passes && (query.words.length === 0 || rowMatches(run, query.words));
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

// An HTML fragment's text: tags dropped, the common entities read.
function htmlText(html) {
    return String(html).replace(/<[^>]+>/g, "").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, "\"").replace(/&#39;/g, "'").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&");
}

// A link in rich text, drawn as github.com draws one: no underline until
// the pointer is on it (linksHovered underlines it then). Its color is the
// html's own (GitHubMarkdown's), or the text's linkTint (GitHubRichText).
function anchorOpen(url) {
    return "<a href=\"" + escapeHtml(url) + "\" style=\"text-decoration:none\">";
}

function anchorHtml(url, html) {
    return anchorOpen(url) + html + "</a>";
}

// html's links (anchorOpen's) with the one at href underlined, and each
// colored linkTint when one is given.
function linksHovered(html, href, linkTint) {
    const hovered = href ? escapeHtml(href) : null;
    const color = linkTint ? "color:" + linkTint + ";" : "";
    return String(html).replace(/<a href="([^"]*)" style="text-decoration:none">/g, (m, url) => "<a href=\"" + url + "\" style=\"" + color + "text-decoration:" + (url === hovered ? "underline" : "none") + "\">");
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
// A github.com link to a pull request, an issue, an Actions run (a job
// page counts as its run), a repository's home, its commits or one commit,
// its releases or one release, or a person's or an organization's profile
// opens in the popout; a label, or an issues or pulls page with a q=,
// opens that repository's list with the search; and anything else goes to
// the browser, as long as it is a web or mail link. A pull request's own
// tabs (Files changed, Commits, Checks) are not its conversation, so they
// go to the browser too, as do a profile's other tabs and a history
// filtered by a query; so does a link to a place in a page (a comment's
// #issuecomment-..., a commit's #diff-...), which a page here does not
// scroll to: parseLink says where (`anchor`).

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
    return parsePageLink(text);
}

// The first path segments of github.com that are its own pages rather
// than an account (github.com/settings, /orgs/..., /topics/...).
var RESERVED_OWNERS = ["about", "account", "apps", "blog", "careers", "codespaces", "collections", "contact", "copilot", "customer-stories", "dashboard", "discussions", "edu", "education", "enterprise", "enterprises", "events", "explore", "features", "git-guides", "github-copilot", "home", "issues", "join", "login", "logout", "marketplace", "mobile", "models", "new", "notifications", "open-source", "organizations", "orgs", "partners", "password_reset", "premium-support", "pricing", "pulls", "readme", "resources", "search", "security", "sessions", "settings", "signup", "site", "solutions", "sponsors", "stars", "team", "topics", "trending", "users", "watching"];

function decodePart(part) {
    try {
        return decodeURIComponent(part);
    } catch (e) {
        return part;
    }
}

function encodePath(path) {
    return String(path).split("/").map(encodeURIComponent).join("/");
}

// The pages past pull requests, issues, and runs (see above), or null.
function parsePageLink(text) {
    const m = text.match(/^https:\/\/github\.com\/([\w-]+)(?:\/([\w.-]+))?(\/[^?#]*)?(?:\?([^#]*))?(?:#(.*))?$/);
    if (!m || RESERVED_OWNERS.indexOf(m[1].toLowerCase()) >= 0)
        return null;
    const owner = m[1];
    const rest = String(m[3] || "").replace(/\/+$/, "");
    const query = String(m[4] || "");
    const anchor = String(m[5] || "");
    if (!m[2]) {
        // A profile's Overview, not its other tabs.
        const tab = query.match(/(?:^|&)tab=([^&]*)/);
        if (rest !== "" || (tab && tab[1] !== "" && tab[1] !== "overview"))
            return null;
        return {
            "kind": "user",
            "login": owner,
            "anchor": anchor
        };
    }
    const name = m[2].replace(/\.git$/, "");
    const page = {
        "owner": owner,
        "name": name,
        "repo": owner + "/" + name,
        "anchor": anchor
    };
    if (rest === "")
        return Object.assign(page, {
            "kind": "repo",
            // The README's own place on the home page is the page.
            "anchor": anchor === "readme" ? "" : anchor
        });
    let found;
    if ((found = rest.match(/^\/commit\/([0-9a-fA-F]{7,40})$/)))
        return Object.assign(page, {
            "kind": "commit",
            "sha": found[1].toLowerCase()
        });
    if ((found = rest.match(/^\/commits(?:\/(.+))?$/)) && query === "")
        return Object.assign(page, {
            "kind": "commits",
            "ref": found[1] ? decodePart(found[1]) : ""
        });
    // A file: its ref and path, split once GitHub says where the ref ends
    // (GitHubData.loadFile); the lines an anchor marks (#L10, #L10-L20);
    // Markdown as its code (?plain=1) rather than as it reads.
    if ((found = rest.match(/^\/blob\/(.+)$/))) {
        const lines = anchor.match(/^L(\d+)(?:C\d+)?(?:-L(\d+)(?:C\d+)?)?$/);
        const first = lines ? Number(lines[1]) : 0;
        return Object.assign(page, {
            "kind": "file",
            "target": decodePart(found[1]),
            "line": first,
            "lineEnd": lines ? Math.max(first, Number(lines[2] || first)) : 0,
            "plain": /(?:^|&)plain=1(?:&|$)/.test(query),
            "anchor": lines ? "" : anchor
        });
    }
    if (rest === "/releases")
        return Object.assign(page, {
            "kind": "releases"
        });
    if (rest === "/releases/latest")
        return Object.assign(page, {
            "kind": "release",
            "tag": ""
        });
    if ((found = rest.match(/^\/releases\/tag\/(.+)$/)))
        return Object.assign(page, {
            "kind": "release",
            "tag": decodePart(found[1])
        });
    return null;
}

var PAGE_KINDS = ["repo", "commits", "commit", "releases", "release", "file", "user"];

// Whether a page is one of those (GitHubBrowse) rather than a pull
// request, an issue, or a run (GitHubDetail).
function isPageKind(kind) {
    return PAGE_KINDS.indexOf(String(kind || "")) >= 0;
}

// The item such a link opens, as a row would carry it.
function pageItem(link) {
    const base = repoUrl(link.repo);
    switch (link.kind) {
    case "repo":
        return {
            "kind": "repo",
            "repo": link.repo,
            "url": base
        };
    case "commits":
        return {
            "kind": "commits",
            "repo": link.repo,
            "ref": String(link.ref || ""),
            "url": base + "/commits" + (link.ref ? "/" + encodePath(link.ref) : "")
        };
    case "commit":
        return {
            "kind": "commit",
            "repo": link.repo,
            "sha": link.sha,
            "url": commitUrl(link.repo, link.sha)
        };
    case "releases":
        return {
            "kind": "releases",
            "repo": link.repo,
            "url": base + "/releases"
        };
    case "release":
        return {
            "kind": "release",
            "repo": link.repo,
            "tag": String(link.tag || ""),
            "url": base + "/releases/" + (link.tag ? "tag/" + encodePath(link.tag) : "latest")
        };
    case "file":
        {
            const line = Number(link.line || 0);
            const lineEnd = Number(link.lineEnd || line);
            return {
                "kind": "file",
                "repo": link.repo,
                "target": String(link.target),
                "line": line,
                "lineEnd": lineEnd,
                "plain": !!link.plain,
                "url": base + "/blob/" + encodePath(link.target) + (link.plain ? "?plain=1" : "") + (line > 0 ? "#L" + line + (lineEnd > line ? "-L" + lineEnd : "") : "")
            };
        }
    case "user":
        return {
            "kind": "user",
            "login": link.login,
            "repo": "",
            "url": "https://github.com/" + link.login
        };
    }
    return null;
}

// The item a github.com URL opens here (GitHubBrowse's kinds only), or
// null.
function pageItemFor(url) {
    const link = parsePageLink(String(url || ""));
    return link && !link.anchor ? pageItem(link) : null;
}

// The login a link to a person's or an organization's profile names, which
// opens their hover card from the link; "" for any other link.
function profileLoginOf(url) {
    const item = pageItemFor(url);
    return item && item.kind === "user" ? item.login : "";
}

// What a page is called in "Back to ...".
function pageLabel(item) {
    if (!item)
        return "the list";
    switch (item.kind) {
    case "run":
        return "run";
    case "repo":
        return item.repo;
    case "commits":
        return "commits";
    case "commit":
        return String(item.sha).slice(0, 7);
    case "releases":
        return "releases";
    case "release":
        return item.tag || "the latest release";
    case "file":
        return String(item.target).split("/").pop();
    case "user":
        return "@" + item.login;
    }
    return "#" + item.number;
}

// Whether two items are the same page.
function samePage(a, b) {
    if (!a || !b || a.kind !== b.kind)
        return false;
    if (a.kind === "run")
        return Number(a.databaseId) === Number(b.databaseId);
    if (isPageKind(a.kind))
        return a.url === b.url;
    return a.repo === b.repo && Number(a.number) === Number(b.number);
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
    return reviewer.slug ? teamUrl(String(repo).split("/")[0], reviewer.slug) : profileUrl(reviewer.login);
}

function teamUrl(org, slug) {
    return "https://github.com/orgs/" + org + "/teams/" + slug;
}

// A tab's page on github.com, for the viewer or in a repository.
function tabUrl(scope, tab) {
    if (tab === "inbox")
        return "https://github.com/notifications" + (scope ? "?query=" + encodeURIComponent("repo:" + scope) : "");
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
    return args.concat(variableArgs(vars));
}

// The variables alone, for a query written here (subjectsQuery).
function variableArgs(vars) {
    const args = [];
    for (const name in vars) {
        const value = vars[name];
        if (value === null || value === undefined)
            continue;
        // A list, one entry each (gh's key[]=value).
        if (Array.isArray(value)) {
            for (const entry of value)
                args.push("-f", name + "[]=" + entry);
            continue;
        }
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

// ------------------------------------------------------------ reactions
//
// GitHub's eight reactions, in its picker's order.
var REACTIONS = [
    {
        "content": "THUMBS_UP",
        "emoji": "👍",
        "name": "+1"
    },
    {
        "content": "THUMBS_DOWN",
        "emoji": "👎",
        "name": "-1"
    },
    {
        "content": "LAUGH",
        "emoji": "😄",
        "name": "laugh"
    },
    {
        "content": "HOORAY",
        "emoji": "🎉",
        "name": "hooray"
    },
    {
        "content": "CONFUSED",
        "emoji": "😕",
        "name": "confused"
    },
    {
        "content": "HEART",
        "emoji": "❤️",
        "name": "heart"
    },
    {
        "content": "ROCKET",
        "emoji": "🚀",
        "name": "rocket"
    },
    {
        "content": "EYES",
        "emoji": "👀",
        "name": "eyes"
    }
];

// A post's reactions (queries/detail.graphql's reactions fragment):
// { id, canReact, groups: { content: { count, mine } } } with the reactions
// someone gave, or null for a node without them.
function reactionsOf(node) {
    if (!node || !node.id || !Array.isArray(node.reactionGroups))
        return null;
    const groups = {};
    for (const group of node.reactionGroups) {
        const count = group && group.reactors ? Number(group.reactors.totalCount || 0) : 0;
        if (count > 0)
            groups[String(group.content)] = {
                "count": count,
                "mine": !!group.viewerHasReacted
            };
    }
    return {
        "id": String(node.id),
        "canReact": !!node.viewerCanReact,
        "groups": groups
    };
}

// The groups with the viewer's reaction to `content` given (on) or taken
// back, counted as GitHub will.
function withReaction(groups, content, on) {
    const current = groups[content] || {
        "count": 0,
        "mine": false
    };
    if (current.mine === on)
        return groups;
    const count = current.count + (on ? 1 : -1);
    return withKey(groups, content, count > 0 ? {
        "count": count,
        "mine": on
    } : undefined);
}

// The chips a post shows: the reactions given, in the picker's order.
function reactionChips(groups) {
    return REACTIONS.filter(reaction => groups && groups[reaction.content]).map(reaction => Object.assign({}, reaction, groups[reaction.content]));
}

// Who gave a post's reactions (queries/detail.graphql's Reactors): content
// -> { total, people: [{ login, name }] } (the first 10), or null.
function reactorsOf(node) {
    if (!node || !Array.isArray(node.reactionGroups))
        return null;
    const out = {};
    for (const group of node.reactionGroups) {
        const reactors = group ? group.reactors : null;
        if (!reactors || !(reactors.totalCount > 0))
            continue;
        out[String(group.content)] = {
            "total": Number(reactors.totalCount),
            "people": nodesOf(reactors).filter(person => !!person.login).map(person => ({
                        "login": String(person.login),
                        "name": String(person.name || "")
                    }))
        };
    }
    return out;
}

function reactionArgs(subjectId, content, on) {
    const field = on ? "addReaction" : "removeReaction";
    return ["api", "graphql", "-f", "query=mutation($id: ID!, $content: ReactionContent!) { " + field + "(input: {subjectId: $id, content: $content}) { reaction { content } } }", "-f", "id=" + subjectId, "-f", "content=" + content];
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
// there, and which of its posts name images or videos (renderingOf). The
// connections that stop short (the newest 100 comments, reviews, and
// threads) say how many there are in all.
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
                "url": String(comment.url || ""),
                "reactions": reactionsOf(comment)
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
        "reactions": reactionsOf(node),
        "labels": labelsOf(node.labels),
        "assignees": nodesOf(node.assignees).map(person => ({
                    "login": String(person.login || "")
                })),
        "comments": comments,
        "commentsTotal": totalOf(node.comments, comments.length)
    };
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
        Object.assign(detail, {
            "baseRefName": String(node.baseRefName || ""),
            "headRefName": String(node.headRefName || ""),
            "headRepo": node.headRepository ? String(node.headRepository.nameWithOwner || "") : "",
            "headSha": String(node.headRefOid || ""),
            "commitsTotal": totalOf(node.commits, 0),
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
        "rendering": renderingOf(node)
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
                "reactions": comment.reactions || null,
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
                "reactions": null,
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
            // A review without a summary has nothing to react to on
            // github.com either.
            "reactions": body !== "" ? reactionsOf(review) : null,
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

// The images a Markdown body names, in document order: a picture's
// sources (its image for a scheme) too.
function imagesIn(markdown) {
    const wanted = [];
    const pattern = /!\[[^\]]*\]\(\s*<?([^)\s>]+)|<img\b[^>]*\bsrc=["']([^"']+)["']|<source\b[^>]*\bsrcset=["']\s*([^"'\s,]+)/gi;
    let m;
    while ((m = pattern.exec(String(markdown || ""))) !== null)
        wanted.push(m[1] || m[2] || m[3]);
    return wanted;
}

// A video attachment: its URL on a line of its own.
var VIDEO = /^\s*(https:\/\/github\.com\/user-attachments\/assets\/[\w-]+|https:\/\/user-images\.githubusercontent\.com\/\S+\.(?:mp4|mov|webm))\s*$/i;

// The video attachments a Markdown body names, in document order.
function videosIn(markdown) {
    const wanted = [];
    for (const line of String(markdown || "").split("\n")) {
        const m = line.match(VIDEO);
        if (m)
            wanted.push(m[1]);
    }
    return wanted;
}

// The posts of a page answer whose bodies name images or videos: [{ id,
// body }]. Only their rendered HTML is asked for (queries/detail.graphql's
// Rendered), since GitHub takes a while to render every body and most name
// neither.
function renderingOf(node) {
    const out = [];
    const add = post => {
        if (post && post.id && (imagesIn(post.body).length > 0 || videosIn(post.body).length > 0) && !out.some(entry => entry.id === String(post.id)))
            out.push({
                "id": String(post.id),
                "body": String(post.body || "")
            });
    };
    add(node);
    nodesOf(node.comments).forEach(add);
    nodesOf(node.reviews).forEach(add);
    for (const thread of nodesOf(node.reviewThreads))
        nodesOf(thread.comments).forEach(add);
    return out;
}

// What GitHub rendered for the images and videos of the Rendered answer's
// nodes: post id -> (the URL its body names -> imagePairs' entry).
function renderedImages(nodes, rendering) {
    const posts = {};
    for (const node of (nodes || [])) {
        const entry = node ? rendering.find(other => other.id === node.id) : null;
        if (entry)
            imagePairs(entry.body, node.bodyHTML, posts[entry.id] = {});
    }
    return posts;
}

// Pairs each image a Markdown body names with what its rendered HTML shows
// for it: { src (the signed URL it loads), animated (GitHub marks a GIF or
// another moving picture), raster (its file, or the one GitHub proxies,
// says a picture of pixels: not a drawing such as an SVG, which scales) },
// in document order. Emoji images exist only in
// the HTML and are skipped; a body whose counts disagree pairs what GitHub
// marked with its canonical source and leaves the rest as links. Each video
// pairs with the player GitHub rendered for it, in a section whose summary
// names its file: { src, video: true, name }.
function imagePairs(markdown, html, into) {
    const wanted = imagesIn(markdown);
    const shown = [];
    const text = String(html || "");
    const attr = (tag, name) => {
        const found = tag.match(new RegExp("\\s" + name + "=\"([^\"]*)\"", "i"));
        return found ? found[1].replace(/&amp;/g, "&") : "";
    };
    for (const tag of (text.match(/<img\b[^>]*>|<source\b[^>]*>/gi) || [])) {
        const src = /^<source/i.test(tag) ? attr(tag, "srcset").trim().split(/[\s,]+/)[0] : attr(tag, "src");
        if (/class="[^"]*emoji/i.test(tag) || src === "")
            continue;
        shown.push({
            "src": src,
            "canonical": attr(tag, "data-canonical-src"),
            "animated": /\sdata-animated-image\b/i.test(tag)
        });
    }
    const raster = url => /\.(png|jpe?g|gif|webp|bmp)$/i.test(String(url).split(/[?#]/)[0]);
    const image = entry => ({
            "src": entry.src,
            "animated": entry.animated,
            "raster": raster(entry.src) || raster(entry.canonical)
        });
    for (let i = 0; i < wanted.length; i++) {
        if (wanted.length === shown.length) {
            into[wanted[i]] = image(shown[i]);
        } else {
            const match = shown.find(entry => entry.canonical === wanted[i]);
            if (match)
                into[wanted[i]] = image(match);
        }
    }
    const videos = videosIn(markdown);
    const players = [];
    const pattern = /<video\b[^>]*>/gi;
    let m;
    while ((m = pattern.exec(text)) !== null) {
        const opened = text.lastIndexOf("<details", m.index);
        const section = opened >= 0 ? text.slice(opened, m.index) : "";
        const summaries = section.indexOf("</details") < 0 ? section.match(/<summary\b[^>]*>[\s\S]*?<\/summary>/gi) || [] : [];
        if (attr(m[0], "src") !== "")
            players.push({
                "src": attr(m[0], "src"),
                "name": summaries.length > 0 ? htmlText(summaries[summaries.length - 1]).replace(/\s+/g, " ").trim() : ""
            });
    }
    for (let i = 0; i < videos.length; i++) {
        // The signed URL carries the attachment's id; in order otherwise.
        const id = videos[i].split("/").pop();
        const match = players.find(entry => entry.src.indexOf(id) >= 0) || (videos.length === players.length ? players[i] : null);
        if (match)
            into[videos[i]] = {
                "src": match.src,
                "video": true,
                "name": match.name
            };
    }
}

// The command that copies an animated image (GitHubData.copyMedia): curl
// fetching the signed URL alone (no header or credential of any kind, a
// .curlrc's included, which --disable, first, leaves unread; over HTTPS
// only, redirects included) straight into `file`, and stopping past
// `maxBytes` (a response that does not say its size included) or
// `seconds`; it prints how many bytes came.
function mediaDownload(url, file, maxBytes, seconds) {
    return ["curl", "--disable", "--silent", "--show-error", "--fail", "--location", "--max-redirs", "3", "--proto", "=https", "--proto-redir", "=https", "--max-filesize", String(maxBytes), "--max-time", String(seconds), "--create-dirs", "--output", file, "--write-out", "%{size_download}", "--url", String(url)];
}

// One renewal of a page's media URLs at a time (GitHubDetail.refreshMedia):
// ask(done, start) runs start(finished) unless one is on its way, whose end
// the ask then waits for, or one finished within `quietMs`, which answers
// it at once; done() runs once the URLs are as new as they get. reset()
// forgets both, for another page.
function renewals(quietMs, clock) {
    const now = clock || (() => Date.now());
    let waiting = null;
    let finishedAt = -Infinity;
    return {
        "ask": (done, start) => {
            if (waiting) {
                if (done)
                    waiting.push(done);
                return;
            }
            if (now() - finishedAt < quietMs) {
                if (done)
                    done();
                return;
            }
            const asked = waiting = done ? [done] : [];
            start(() => {
                if (waiting !== asked)
                    return;
                waiting = null;
                finishedAt = now();
                for (const callback of asked)
                    callback();
            });
        },
        "reset": () => {
            waiting = null;
            finishedAt = -Infinity;
        }
    };
}

// The name of a media file's local copy (GitHubData.copyMedia): a hash of
// where it lives, its query (a signature that changes) left out, and its
// kind's extension.
function mediaKey(url) {
    const place = String(url || "").split("?")[0];
    let hash = 0x811c9dc5;
    for (let i = 0; i < place.length; i++) {
        hash ^= place.charCodeAt(i);
        hash = Math.imul(hash, 0x01000193) >>> 0;
    }
    const ext = place.match(/\.(gif|webp|png|apng)$/i);
    return hash.toString(16).padStart(8, "0") + "." + (ext ? ext[1].toLowerCase() : "gif");
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

// `list` with the entries of `more` it does not have yet, by `key` ("url"
// for rows, "id" for threads), in order.
function appendNew(list, more, key) {
    const seen = {};
    for (const entry of list)
        seen[entry[key]] = true;
    return list.concat(more.filter(entry => !seen[entry[key]] && (seen[entry[key]] = true)));
}

// A copy of an object with one key set, or removed when the value is
// undefined, for the properties that must be reassigned to notify.
function withKey(object, key, value) {
    const next = Object.assign({}, object);
    if (value === undefined)
        delete next[key];
    else
        next[key] = value;
    return next;
}

// ------------------------------------------------------ search suggestions
//
// What the search field offers as it is typed, as github.com's search bar
// does: the qualifiers a tab's search understands while a word is typed,
// then the values of the one being written (labels, people, states) once
// its colon is. Pull requests and issues hand the search to GitHub, so
// theirs are GitHub's qualifiers; the inbox and Actions runs filter what is
// loaded, so theirs are the ones inboxQuery and runsQuery read. A value
// comes from here (states, sorts, dates), or from a source the panel fills
// (GitHubSearchHelper): what it has loaded, and what GitHub answers for
// the repository searched or the name typed.
//
// A qualifier: { name, label, icon, values, source, hint, only, where }.
// values are fixed ones ([value, detail, only]); source names the panel's
// ("label", "user", "owner", "repo", "milestone", "type", "branch",
// "workflow", "event", "date", "count"); hint says what to type when
// neither has anything. only keeps it to pull requests ("pr") or issues
// ("issue"), and where to a repository's search ("repo") or the viewer's
// ("viewer").

function qualifier(name, label, icon, extra) {
    return Object.assign({
        "name": name,
        "label": label,
        "icon": icon,
        "values": [],
        "source": "",
        "hint": "",
        "only": "",
        "where": ""
    }, extra || {});
}

var BOOLEAN_VALUES = [["true", "Yes"], ["false", "No"]];
var HAS_VALUES = [["label", "Labels"], ["milestone", "A milestone"], ["assignee", "Assignees"], ["project", "A project"], ["type", "An issue type", "issue"], ["parent-issue", "A parent issue", "issue"]];

var ISSUE_QUALIFIERS = [
    qualifier("is", "Is", "apps", {
        "values": [["open", "Open"], ["closed", "Closed"], ["merged", "Merged", "pr"], ["unmerged", "Closed without merging", "pr"], ["draft", "Draft", "pr"], ["blocked", "Blocked by an issue", "issue"], ["blocking", "Blocking an issue", "issue"], ["locked", "Conversation locked"], ["unlocked", "Conversation not locked"], ["public", "In a public repository"], ["private", "In a private repository"]]
    }),
    qualifier("state", "State", "radio_button_unchecked", {
        "values": [["open", "Open"], ["closed", "Closed"]]
    }),
    qualifier("label", "Label", "sell", {
        "source": "label"
    }),
    qualifier("project", "Project", "table_chart", {
        "hint": "owner/number, as in octo-org/5"
    }),
    qualifier("assignee", "Assignee", "person", {
        "source": "user"
    }),
    qualifier("author", "Author", "person", {
        "source": "user"
    }),
    qualifier("type", "Type", "category", {
        "source": "type",
        "only": "issue"
    }),
    qualifier("milestone", "Milestone", "flag", {
        "source": "milestone"
    }),
    qualifier("involves", "Involves", "group", {
        "source": "user"
    }),
    qualifier("mentions", "Mentions", "alternate_email", {
        "source": "user"
    }),
    qualifier("parent-issue", "Parent issue", "account_tree", {
        "hint": "owner/name#number",
        "only": "issue"
    }),
    qualifier("blocking", "Blocking", "block", {
        "hint": "owner/name#number",
        "only": "issue"
    }),
    qualifier("blocked-by", "Blocked by", "do_not_disturb_on", {
        "hint": "owner/name#number",
        "only": "issue"
    }),
    qualifier("sub-issue", "Sub-issue", "subdirectory_arrow_right", {
        "hint": "owner/name#number",
        "only": "issue"
    }),
    qualifier("updated", "Update date", "calendar_today", {
        "source": "date"
    }),
    qualifier("created", "Creation date", "calendar_today", {
        "source": "date"
    }),
    qualifier("closed", "Closed date", "calendar_today", {
        "source": "date"
    }),
    qualifier("merged", "Merge date", "calendar_today", {
        "source": "date",
        "only": "pr"
    }),
    qualifier("review-requested", "Review requested", "person", {
        "source": "user",
        "only": "pr"
    }),
    qualifier("in", "In", "apps", {
        "values": [["title", "The title"], ["body", "The description"], ["comments", "The comments"]]
    }),
    qualifier("commenter", "Commenter", "person", {
        "source": "user"
    }),
    qualifier("user", "User", "person", {
        "source": "owner",
        "where": "viewer"
    }),
    qualifier("org", "Organization", "domain", {
        "source": "owner",
        "where": "viewer"
    }),
    qualifier("repo", "Repository", "book", {
        "source": "repo",
        "where": "viewer"
    }),
    qualifier("user-review-requested", "User review requested", "alternate_email", {
        "source": "user",
        "only": "pr"
    }),
    qualifier("reviewed-by", "Reviewed by", "person", {
        "source": "user",
        "only": "pr"
    }),
    qualifier("comments", "Comment count", "chat_bubble", {
        "source": "count"
    }),
    qualifier("interactions", "Interactions count", "forum", {
        "source": "count"
    }),
    qualifier("reason", "Closed reason", "task_alt", {
        "values": [["completed", "Completed"], ["\"not planned\"", "Not planned"], ["duplicate", "Duplicate"]],
        "only": "issue"
    }),
    qualifier("linked", "Linked", "link", {
        "values": [["pr", "Linked to a pull request", "issue"], ["issue", "Linked to an issue", "pr"]]
    }),
    qualifier("archived", "Archived", "inventory_2", {
        "values": BOOLEAN_VALUES,
        "where": "viewer"
    }),
    qualifier("reactions", "Reaction count", "add_reaction", {
        "source": "count"
    }),
    qualifier("draft", "Draft", "edit_note", {
        "values": BOOLEAN_VALUES,
        "only": "pr"
    }),
    qualifier("review", "Review state", "rate_review", {
        "values": [["none", "No reviews yet"], ["required", "Review required"], ["approved", "Approved"], ["changes_requested", "Changes requested"]],
        "only": "pr"
    }),
    qualifier("language", "Language", "code", {
        "hint": "a language, as in python"
    }),
    qualifier("sha", "Commit SHA", "commit", {
        "hint": "seven or more characters of a commit SHA",
        "only": "pr"
    }),
    qualifier("base", "Base", "call_split", {
        "source": "branch",
        "only": "pr"
    }),
    qualifier("head", "Head", "call_split", {
        "source": "branch",
        "only": "pr"
    }),
    qualifier("status", "Status", "check_circle", {
        "values": [["success", "Checks passing"], ["failure", "Checks failing"], ["pending", "Checks running"]],
        "only": "pr"
    }),
    qualifier("team", "Team", "groups", {
        "hint": "org/team, as in octo-org/devs"
    }),
    qualifier("team-review-requested", "Team review requested", "groups", {
        "hint": "org/team, as in octo-org/devs",
        "only": "pr"
    }),
    qualifier("has", "Has", "check_box", {
        "values": HAS_VALUES
    }),
    qualifier("no", "Missing", "check_box_outline_blank", {
        "values": HAS_VALUES
    }),
    qualifier("sort", "Sort", "sort", {
        "values": [["updated-desc", "Recently updated"], ["updated-asc", "Least recently updated"], ["created-desc", "Newest"], ["created-asc", "Oldest"], ["comments-desc", "Most commented"], ["comments-asc", "Least commented"], ["reactions-desc", "Most reactions"], ["reactions-+1-desc", "Most 👍"], ["interactions-desc", "Most interactions"]]
    })
];

var SEARCH_QUALIFIERS = {
    "issues": ISSUE_QUALIFIERS,
    "prs": ISSUE_QUALIFIERS,
    "inbox": [
        qualifier("is", "Is", "apps", {
            "values": [["unread", "Unread"], ["read", "Read"], ["pr", "Pull requests"], ["issue", "Issues"], ["issue-or-pull-request", "Issues and pull requests"], ["release", "Releases"], ["discussion", "Discussions"], ["commit", "Commits"], ["check-suite", "Actions runs"], ["gist", "Gists"], ["repository-invitation", "Repository invitations"], ["repository-vulnerability-alert", "Security alerts"], ["repository-advisory", "Security advisories"]]
        }),
        qualifier("reason", "Reason", "help", {
            "values": [["participating", "Participating"]].concat(Object.keys(REASONS).map(key => [key.replace(/_/g, "-"), REASONS[key]]))
        }),
        qualifier("repo", "Repository", "book", {
            "source": "repo"
        }),
        qualifier("org", "Organization", "domain", {
            "source": "owner"
        }),
        qualifier("author", "Author", "person", {
            "source": "user"
        })
    ],
    "actions": [
        qualifier("workflow", "Workflow", "account_tree", {
            "source": "workflow"
        }),
        qualifier("status", "Status", "check_circle", {
            "values": [["success", "Succeeded"], ["failure", "Failed"], ["in_progress", "In progress"], ["queued", "Queued"], ["waiting", "Waiting"], ["cancelled", "Cancelled"], ["skipped", "Skipped"], ["action_required", "Action required"], ["timed_out", "Timed out"], ["completed", "Completed"]]
        }),
        qualifier("branch", "Branch", "call_split", {
            "source": "branch"
        }),
        qualifier("event", "Event", "bolt", {
            "source": "event"
        }),
        qualifier("repo", "Repository", "book", {
            "source": "repo",
            "where": "viewer"
        })
    ]
};

// AND and OR join what GitHub searches; the inbox and runs read every
// word as AND already.
var SEARCH_OPERATORS = [
    {
        "name": "AND",
        "label": "AND",
        "icon": "add_circle",
        "detail": "Both sides"
    },
    {
        "name": "OR",
        "label": "OR",
        "icon": "join",
        "detail": "Either side"
    }
];

// The qualifiers a tab's search offers in a scope ("" or owner/name).
function searchQualifiers(tab, scope) {
    const kind = tab === "prs" ? "pr" : (tab === "issues" ? "issue" : "");
    return (SEARCH_QUALIFIERS[tab] || []).filter(def => (def.only === "" || def.only === kind) && (def.where === "" || (def.where === "repo") === !!scope));
}

// The word under the cursor and what it is: { start, end, text, exclude,
// mode, name, def, value }. mode is "qualifier" for a word that may still
// become one (the start of a name, or nothing yet), "value" once a known
// qualifier has its colon (value is what follows, without quotes), and ""
// for anything else (a URL, an unknown name:).
function searchContext(tab, scope, text, cursor) {
    const s = String(text || "");
    const at = Math.max(0, Math.min(s.length, Number(cursor) || 0));
    const token = searchTokens(s).find(t => t.start <= at && at <= t.end) || {
        "start": at,
        "end": at,
        "text": ""
    };
    const out = Object.assign({}, token, {
        "exclude": token.text.charAt(0) === "-",
        "mode": "",
        "name": "",
        "def": null,
        "value": ""
    });
    const q = qualifierOf(token.text);
    if (q) {
        const def = searchQualifiers(tab, scope).find(other => other.name === q.name);
        if (def)
            Object.assign(out, {
                "mode": "value",
                "name": def.name,
                "def": def,
                "value": q.value,
                "exclude": q.exclude
            });
        return out;
    }
    if (/^-?[a-zA-Z-]*$/.test(token.text))
        out.mode = "qualifier";
    return out;
}

// A value as a qualifier takes it: quoted when it has a space.
function quotedValue(value) {
    const v = String(value || "").replace(/"/g, "");
    return /\s/.test(v) ? "\"" + v + "\"" : v;
}

function isoDay(ms) {
    return new Date(ms).toISOString().slice(0, 10);
}

// The values a source offers whatever is loaded: a date's ranges back
// from `now`, a count's thresholds.
function presetValues(source, now) {
    if (source === "date")
        return [["Past day", 1], ["Past week", 7], ["Past month", 30], ["Past year", 365]].map(preset => ({
                    "value": ">=" + isoDay(now - preset[1] * 86400000),
                    "detail": preset[0]
                }));
    if (source === "count")
        return [["0", "None"], [">0", "Any"], [">5", "More than 5"], [">10", "More than 10"], [">50", "More than 50"]].map(preset => ({
                    "value": preset[0],
                    "detail": preset[1]
                }));
    return [];
}

// What the menu lists for a context from searchContext: entries of {
// label, detail, icon, color, login, insert, final, hint }. insert is the
// word that takes the typed one's place; final says the word is done (a
// space follows it); hint is a line that says what to type, which cannot
// be chosen. `values` are the source's ([{ value, detail, color, login }],
// what the panel has and GitHub answered), `now` dates the presets, and
// `all` lists every qualifier for a word not begun yet (the field's
// filter button).
function searchSuggestions(tab, scope, context, values, now, all) {
    const c = context;
    const kind = tab === "prs" ? "pr" : (tab === "issues" ? "issue" : "");
    const dash = c.exclude ? "-" : "";
    const out = [];
    if (c.mode === "qualifier") {
        const typed = c.text.replace(/^-/, "").toLowerCase();
        if (typed === "" && !all && !c.exclude)
            return out;
        const defs = searchQualifiers(tab, scope);
        const byName = defs.filter(def => def.name.indexOf(typed) === 0);
        const byLabel = defs.filter(def => byName.indexOf(def) < 0 && typed !== "" && def.label.toLowerCase().split(/\s+/).some(word => word.indexOf(typed) === 0));
        for (const def of byName.concat(byLabel))
            out.push({
                "label": def.label,
                "detail": dash + def.name + ":",
                "icon": def.icon,
                "insert": dash + def.name + ":",
                "final": false
            });
        if (c.exclude)
            return out;
        if (kind !== "")
            for (const op of SEARCH_OPERATORS)
                if (op.name.toLowerCase().indexOf(typed) === 0)
                    out.push({
                        "label": op.label,
                        "detail": op.detail,
                        "icon": op.icon,
                        "insert": op.name,
                        "final": true
                    });
        if (typed === "")
            out.push({
                "label": "Exclude",
                "detail": "-qualifier:value",
                "icon": "remove_circle",
                "insert": "-",
                "final": false
            });
        return out;
    }
    if (c.mode !== "value")
        return out;
    const def = c.def;
    const typed = c.value.toLowerCase();
    const candidates = def.values.filter(entry => !entry[2] || entry[2] === kind).map(entry => ({
                "value": entry[0],
                "detail": entry[1]
            })).concat(presetValues(def.source, now), values || []);
    const seen = {};
    const first = [];
    const rest = [];
    for (const entry of candidates) {
        const value = String(entry.value || "");
        const key = value.toLowerCase().replace(/"/g, "");
        if (value === "" || seen[key])
            continue;
        const detail = String(entry.detail || "");
        const where = key.indexOf(typed);
        if (typed !== "" && where < 0 && detail.toLowerCase().indexOf(typed) < 0)
            continue;
        seen[key] = true;
        (where === 0 ? first : rest).push({
                "label": value.replace(/"/g, ""),
                "detail": detail,
                "icon": def.icon,
                "color": String(entry.color || ""),
                "login": String(entry.login || ""),
                "insert": dash + def.name + ":" + (value.charAt(0) === "\"" ? value : quotedValue(value)),
                "final": true
            });
    }
    const found = first.concat(rest).slice(0, 50);
    if (found.length === 0 && def.hint !== "")
        found.push({
            "label": def.hint,
            "detail": "",
            "icon": "info",
            "hint": true
        });
    return found;
}

// The text and cursor once an entry takes the place of the word under the
// cursor: a finished word is followed by a space, and the cursor goes
// after it.
function applySuggestion(text, context, entry) {
    const s = String(text || "");
    const before = s.slice(0, context.start);
    let after = s.slice(context.end);
    let insert = entry.insert;
    if (entry.final) {
        insert += " ";
        after = after.replace(/^\s+/, "");
    }
    return {
        "text": before + insert + after,
        "cursor": before.length + insert.length
    };
}

// GitHub's answers for the suggestions (queries/suggest.graphql) as the
// values each source offers: { label, milestone, type } for "repository",
// { branch } for "branches", { user } for "users"; "labels" is a
// repository's labels by what is typed.
function suggestedValues(what, data) {
    const d = data || {};
    const repo = d.repository || {};
    if (what === "repository" || what === "labels")
        return {
            // More than the first page: the labels are asked for again by
            // what is typed.
            "moreLabels": totalOf(repo.labels, 0) > nodesOf(repo.labels).length,
            "label": nodesOf(repo.labels).map(label => ({
                        "value": String(label.name || ""),
                        "detail": String(label.description || ""),
                        "color": String(label.color || "")
                    })),
            "milestone": nodesOf(repo.milestones).map(milestone => ({
                        "value": String(milestone.title || ""),
                        "detail": milestone.dueOn ? "Due " + String(milestone.dueOn).slice(0, 10) : ""
                    })),
            "type": nodesOf(repo.issueTypes).map(type => ({
                        "value": String(type.name || ""),
                        "detail": String(type.description || "")
                    }))
        };
    if (what === "branches")
        return {
            "branch": nodesOf(repo.refs).map(ref => ({
                        "value": String(ref.name || "")
                    }))
        };
    return {
        "user": nodesOf(d.search).filter(person => person.login).map(person => ({
                    "value": String(person.login),
                    "detail": String(person.name || ""),
                    "login": String(person.login)
                }))
    };
}

// The repository a search names (repo:owner/name), for its labels and
// people when the panel is not on one; "" for none or several.
function searchedRepo(text) {
    const repos = searchTokens(text).map(token => qualifierOf(token.text)).filter(q => q && !q.exclude && q.name === "repo" && isRepo(q.value)).map(q => q.value);
    return repos.length === 1 ? repos[0] : "";
}

// ------------------------------------------------------------ hover cards
//
// A person's card over their avatar (queries/hovercard.graphql), as
// github.com's: { login, name, pronouns, status: { emoji, message, busy }
// or null, bio, location, company, contexts: [{ icon, html }], found,
// app }. A context's html is its line with its teams or organizations as
// links. An app or a bot is no user GitHub can describe, so its card is
// only its name, asked for nothing.

var OCTICONS = {
    "issue-opened": "adjust",
    "issue-closed": "check_circle",
    "git-pull-request": "merge",
    "git-merge": "merge",
    "git-commit": "commit",
    "people": "group",
    "organization": "domain",
    "repo": "book",
    "eye": "visibility",
    "star": "star",
    "comment": "chat_bubble",
    "person": "person",
    "clock": "schedule",
    "check": "check",
    "code-review": "rate_review"
};

function isApp(login) {
    const name = String(login || "");
    return name === "" || name === "ghost" || /\[bot\]$/.test(name) || name.indexOf("app/") === 0;
}

function hovercardContext(context) {
    const link = (url, text) => anchorHtml(String(url || ""), escapeHtml(String(text || "")));
    const more = (shown, total) => total > shown ? " and " + (total - shown) + " more" : "";
    let html = escapeHtml(String(context.message || ""));
    if (context.__typename === "OrganizationTeamsHovercardContext") {
        const teams = nodesOf(context.relevantTeams);
        if (teams.length > 0)
            html = "Member of " + teams.map(team => link(team.url, team.combinedSlug || team.name)).join(", ") + more(teams.length, Number(context.totalTeamCount || 0));
    } else if (context.__typename === "OrganizationsHovercardContext") {
        const orgs = nodesOf(context.relevantOrganizations);
        if (orgs.length > 0)
            html = "Member of " + orgs.map(org => link(org.url, org.name || org.login)).join(", ") + more(orgs.length, Number(context.totalOrganizationCount || 0));
    }
    return {
        "icon": OCTICONS[context.octicon] || "info",
        "html": html
    };
}

// The logins GitHub names as bots anywhere in an answer: GraphQL gives a
// bot's login bare ("dependabot"), and a user may hold the same name, so
// a bot's card must not ask for that user.
function botLogins(data) {
    const out = {};
    const walk = (value, depth) => {
        if (!value || typeof value !== "object" || depth > 30)
            return;
        if (Array.isArray(value)) {
            for (const entry of value)
                walk(entry, depth + 1);
            return;
        }
        if (value.__typename === "Bot" && typeof value.login === "string" && value.login !== "")
            out[value.login] = true;
        for (const key in value)
            walk(value[key], depth + 1);
    };
    walk(data, 0);
    return out;
}

function hovercardOf(data, login) {
    const user = data ? data.user : null;
    const org = !user && data ? data.organization : null;
    const card = {
        "login": String(login || ""),
        "name": "",
        "pronouns": "",
        "status": null,
        "bio": "",
        "location": "",
        "company": "",
        "contexts": [],
        "found": !!user || !!org,
        "isOrg": !!org,
        "app": isApp(login)
    };
    // An organization's card: its name, description, and place.
    if (org)
        return Object.assign(card, {
            "login": String(org.login || login),
            "name": String(org.name || ""),
            "bio": String(org.description || ""),
            "location": String(org.location || "")
        });
    if (!user)
        return card;
    const status = user.status && (user.status.message || user.status.emoji) ? {
        "emoji": String(user.status.emoji || ""),
        "message": String(user.status.message || ""),
        "busy": !!user.status.indicatesLimitedAvailability
    } : null;
    return Object.assign(card, {
        "login": String(user.login || login),
        "name": String(user.name || ""),
        "pronouns": String(user.pronouns || ""),
        "status": status,
        "bio": String(user.bio || ""),
        "location": String(user.location || ""),
        "company": String(user.company || ""),
        "contexts": (user.hovercard && Array.isArray(user.hovercard.contexts) ? user.hovercard.contexts : []).filter(context => !!context && !!context.message).map(hovercardContext)
    });
}

// ----------------------------------------------------------- browse pages
//
// The pages past pull requests, issues, and runs (GitHubBrowse), from
// queries/browse.graphql's answers and the REST endpoints that have what
// GraphQL lacks (a README found whatever its name, a commit's patches).

// A count as github.com abbreviates it beside a star or a fork: 999, then
// 3.7k, 14.5k, 1.2m.
function shortCount(n) {
    const value = Number(n || 0);
    if (value < 1000)
        return String(value);
    // The unit after rounding: 999,960 is 1m, not 1000k.
    const thousands = Math.round(value / 100) / 10;
    if (thousands < 1000)
        return thousands.toFixed(1).replace(/\.0$/, "") + "k";
    return (Math.round(value / 100000) / 10).toFixed(1).replace(/\.0$/, "") + "m";
}

// 48,236 as github.com groups digits, whatever the locale.
function grouped(n) {
    return String(Math.round(Number(n || 0))).replace(/\B(?=(\d{3})+(?!\d))/g, ",");
}

function plural(n, one, many) {
    return grouped(n) + " " + (Number(n) === 1 ? one : (many || one + "s"));
}

// A file size as a release's assets list it.
function fileSize(bytes) {
    const n = Number(bytes || 0);
    if (n < 1024)
        return n + " Bytes";
    const units = ["KB", "MB", "GB", "TB"];
    let value = n / 1024;
    let unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
        value /= 1024;
        unit++;
    }
    return (value >= 100 ? Math.round(value) : Math.round(value * 10) / 10) + " " + units[unit];
}

// A day as github.com heads a group of commits: Nov 17, 2026.
function dayLabel(iso) {
    const date = new Date(String(iso || ""));
    if (!isFinite(date.getTime()))
        return "";
    return MONTHS[date.getMonth()] + " " + date.getDate() + ", " + date.getFullYear();
}

function loginOfActor(actor) {
    return actor && actor.user && actor.user.login ? String(actor.user.login) : "";
}

// A commit as a history row or a commit page shows it.
function commitOf(node, repo) {
    if (!node || !node.oid)
        return null;
    const author = node.author || {};
    const committer = node.committer || {};
    const authors = nodesOf(node.authors).map(entry => ({
                "login": loginOfActor(entry),
                "name": String(entry.name || "")
            }));
    if (authors.length === 0)
        authors.push({
            "login": loginOfActor(author),
            "name": String(author.name || "")
        });
    const committerLogin = loginOfActor(committer);
    return {
        "sha": String(node.oid),
        "short": String(node.abbreviatedOid || String(node.oid).slice(0, 7)),
        "headline": String(node.messageHeadline || ""),
        "body": String(node.messageBody || ""),
        "url": String(node.url || commitUrl(repo, node.oid)),
        "repo": repo,
        "committedAt": String(node.committedDate || committer.date || ""),
        "authoredAt": String(node.authoredDate || author.date || ""),
        "authors": authors,
        "authorsTotal": node.authors && typeof node.authors.totalCount === "number" ? node.authors.totalCount : authors.length,
        // Someone else committed it (a rebase, a cherry-pick); GitHub's own
        // web-flow committer is GitHub merging for its author, which
        // github.com does not name.
        "committer": committerLogin !== "" && committerLogin !== "web-flow" && !authors.some(a => a.login === committerLogin) ? {
            "login": committerLogin,
            "name": String(committer.name || "")
        } : null,
        "verified": !!(node.signature && node.signature.isValid),
        "checks": node.statusCheckRollup ? String(node.statusCheckRollup.state || "") : "",
        "additions": Number(node.additions || 0),
        "deletions": Number(node.deletions || 0),
        "changedFiles": typeof node.changedFilesIfAvailable === "number" ? node.changedFilesIfAvailable : -1,
        "parents": nodesOf(node.parents).map(parent => ({
                    "sha": String(parent.oid),
                    "short": String(parent.abbreviatedOid || String(parent.oid).slice(0, 7))
                }))
    };
}

// Where a commit's checks stand, as the glyph beside it on github.com.
function checksGlyph(state) {
    switch (String(state || "")) {
    case "SUCCESS":
        return glyph("check", "success");
    case "FAILURE":
    case "ERROR":
        return glyph("close", "error");
    case "PENDING":
    case "EXPECTED":
        return glyph("fiber_manual_record", "warning");
    }
    return null;
}

function checksText(state) {
    return ({
            "SUCCESS": "All checks have passed",
            "FAILURE": "Some checks were not successful",
            "ERROR": "Some checks errored",
            "PENDING": "Some checks have not completed yet",
            "EXPECTED": "Some checks have not completed yet"
        })[String(state || "")] || "";
}

// A history page (queries/browse.graphql's Commits or DefaultCommits):
// { commits, total, more, cursor, defaultBranch, ref, path } or null when
// the branch, tag, or commit named is not there. `ref` and `path` say
// what Commits found: the whole name as a branch, tag, or commit, or else
// its first part with the rest as a path in it (/commits/main/src).
function historyOf(repository, repo, asked) {
    if (!repository)
        return null;
    // Commits names its own head, which may not exist; DefaultCommits
    // takes the default branch's.
    let head = "object" in repository ? repository.object : (repository.defaultBranchRef ? repository.defaultBranchRef.target : null);
    let ref = String(asked || "");
    let path = "";
    if ((!head || !head.history) && repository.inPath && repository.inPath.history && ref.indexOf("/") > 0) {
        head = repository.inPath;
        path = ref.slice(ref.indexOf("/") + 1);
        ref = ref.slice(0, ref.indexOf("/"));
    }
    const history = head ? head.history : null;
    if (!history)
        return null;
    return {
        "ref": ref,
        "path": path,
        "commits": nodesOf(history).map(node => commitOf(node, repo)).filter(c => !!c),
        "total": Number(history.totalCount || 0),
        "more": !!(history.pageInfo && history.pageInfo.hasNextPage),
        "cursor": history.pageInfo ? String(history.pageInfo.endCursor || "") : "",
        "defaultBranch": repository.defaultBranchRef ? String(repository.defaultBranchRef.name || "") : ""
    };
}

// Commits by the day they were committed (in local time), newest first,
// as github.com's history groups them under "Commits on <day>".
function commitGroups(commits) {
    const groups = [];
    for (const commit of (commits || [])) {
        const day = dayLabel(commit.committedAt);
        if (groups.length === 0 || groups[groups.length - 1].day !== day)
            groups.push({
                "day": day,
                "commits": []
            });
        groups[groups.length - 1].commits.push(commit);
    }
    return groups;
}

// A tree's entries as github.com lists them: folders first, then files,
// each by name; a submodule ("commit") lists among the folders.
function treeEntries(entries, repo, branch) {
    const ref = encodePath(branch || "HEAD");
    return (entries || []).filter(entry => !!entry && entry.name).map(entry => {
        const folder = entry.type === "tree" || entry.type === "commit";
        return {
            "name": String(entry.name),
            "path": String(entry.path || entry.name),
            "folder": folder,
            "submodule": entry.type === "commit",
            "url": repoUrl(repo) + (folder ? "/tree/" : "/blob/") + ref + "/" + encodePath(String(entry.path || entry.name))
        };
    }).sort((a, b) => a.folder !== b.folder ? (a.folder ? -1 : 1) : a.name.toLowerCase().localeCompare(b.name.toLowerCase()));
}

// The languages bar: each language's share of the code, in tenths of a
// percent as github.com rounds them, the rest after the eighth as Other.
function languageShares(languages) {
    const total = languages ? Number(languages.totalSize || 0) : 0;
    if (!(total > 0) || !Array.isArray(languages.edges))
        return [];
    const shares = languages.edges.filter(edge => edge && edge.node).map(edge => ({
                "name": String(edge.node.name),
                "color": String(edge.node.color || ""),
                "share": Number(edge.size || 0) / total
            }));
    const rest = 1 - shares.reduce((sum, entry) => sum + entry.share, 0);
    if (rest > 0.0005)
        shares.push({
            "name": "Other",
            "color": "",
            "share": rest
        });
    return shares.map(entry => Object.assign(entry, {
                "percent": (Math.round(entry.share * 1000) / 10).toFixed(1) + "%"
            }));
}

// A website as a profile or a repository saves it, with or without its
// scheme ("example.com"), as a web link github.com opens; "" for none.
function siteUrl(text) {
    const site = String(text || "").trim();
    if (site === "")
        return "";
    return externalUrl(/^[a-z][a-z0-9+.-]*:/i.test(site) ? site : "https://" + site);
}

// The file GitHub read a repository's license from, among its root's
// entries (Logic.treeEntries): LICENSE, LICENSE.md, COPYING, and so on.
function licenseFile(entries) {
    return (entries || []).find(entry => !entry.folder && /^(licen[cs]e|copying|unlicense)([.-][\w.-]*)?$/i.test(entry.name)) || null;
}

// A repository's home (queries/browse.graphql's Repository).
function repoHomeOf(repository) {
    if (!repository)
        return null;
    const repo = String(repository.nameWithOwner);
    const branch = repository.defaultBranchRef ? String(repository.defaultBranchRef.name || "") : "";
    const head = repository.defaultBranchRef ? repository.defaultBranchRef.target : null;
    const license = repository.licenseInfo;
    const latest = repository.latestRelease;
    const entries = head && head.tree ? treeEntries(head.tree.entries, repo, branch) : [];
    return {
        "id": String(repository.id || ""),
        "repo": repo,
        "name": String(repository.name || repo.split("/")[1]),
        "owner": repository.owner ? String(repository.owner.login) : repo.split("/")[0],
        "ownerIsOrg": !!repository.owner && repository.owner.__typename === "Organization",
        "description": String(repository.description || ""),
        "homepage": siteUrl(repository.homepageUrl),
        "isPrivate": !!repository.isPrivate,
        "isFork": !!repository.isFork,
        "isArchived": !!repository.isArchived,
        "isTemplate": !!repository.isTemplate,
        "isMirror": !!repository.isMirror,
        "parent": repository.parent ? String(repository.parent.nameWithOwner) : "",
        "template": repository.templateRepository ? String(repository.templateRepository.nameWithOwner) : "",
        "stars": Number(repository.stargazerCount || 0),
        "forks": Number(repository.forkCount || 0),
        "watchers": totalOf(repository.watchers, 0),
        "starred": !!repository.viewerHasStarred,
        "watching": String(repository.viewerSubscription || "") === "SUBSCRIBED",
        "issues": repository.hasIssuesEnabled === false ? -1 : totalOf(repository.issues, 0),
        "pulls": totalOf(repository.pullRequests, 0),
        "discussions": repository.hasDiscussionsEnabled ? totalOf(repository.discussions, 0) : -1,
        "license": license && license.spdxId !== "NOASSERTION" ? String(license.nickname || license.name || "") : (license ? "View license" : ""),
        "topics": nodesOf(repository.repositoryTopics).map(node => node.topic ? String(node.topic.name) : "").filter(name => name !== ""),
        "languages": languageShares(repository.languages),
        "releases": totalOf(repository.releases, 0),
        "latestRelease": latest ? {
            "name": String(latest.name || latest.tagName),
            "tag": String(latest.tagName),
            "publishedAt": String(latest.publishedAt || ""),
            "url": String(latest.url || "")
        } : null,
        "tags": totalOf(repository.refs, 0),
        "branches": totalOf(repository.branches, 0),
        "branch": branch,
        "head": head ? commitOf(head, repo) : null,
        "commits": head && head.history ? Number(head.history.totalCount || 0) : 0,
        "entries": entries,
        "licenseUrl": licenseFile(entries) ? licenseFile(entries).url : ""
    };
}

// The README the REST readme endpoint rendered (Accept: html) names its
// file in the wrapper GitHub puts around it: the folder its relative links
// and pictures start from.
function readmePath(html) {
    const m = String(html || "").match(/\sdata-path="([^"]*)"/);
    return m ? m[1].replace(/&amp;/g, "&") : "README.md";
}

// A README's pictures, as imagePairs pairs them with the rendered HTML; a
// picture the README names by a path in its repository, which GitHub's
// HTML leaves as written, loads from raw.githubusercontent.com when the
// repository is public (no credential), and stays a link otherwise.
function readmeImages(markdown, html, repo, isPublic, branch) {
    const found = {};
    imagePairs(markdown, html, found);
    const dir = readmePath(html).split("/").slice(0, -1);
    for (const url in found) {
        const entry = found[url];
        if (/^https:\/\//i.test(entry.src))
            continue;
        if (!isPublic || /^[a-z][a-z0-9+.-]*:/i.test(entry.src) || entry.src.indexOf("//") === 0) {
            delete found[url];
            continue;
        }
        const parts = entry.src.charAt(0) === "/" ? [] : dir.slice();
        for (const part of entry.src.split(/[?#]/)[0].split("/")) {
            if (part === "..")
                parts.pop();
            else if (part !== "." && part !== "")
                parts.push(part);
        }
        // The path as the README wrote it may be percent-encoded already.
        found[url] = Object.assign({}, entry, {
            "src": "https://raw.githubusercontent.com/" + repo + "/" + encodePath(branch || "HEAD") + "/" + parts.map(part => encodeURIComponent(decodePart(part))).join("/")
        });
    }
    return found;
}

// Where a README's relative links lead: its folder on the default branch,
// as github.com resolves them (GitHubMarkdown's linkBase).
function readmeLinkBase(html, repo, branch) {
    const dir = readmePath(html).split("/").slice(0, -1);
    return [repo, "blob", branch || "HEAD"].concat(dir).join("/");
}

// A file as its page shows it (queries/browse.graphql File, the ref and
// path it was asked as), or null when nothing is there: { repo, ref,
// path, name, dir, isPrivate, folder, size, binary, truncated, text (null
// when GitHub sends none), lines, loc (the lines with something on them),
// markdown, image, imageUrl, commit (the last to change it), url, rawUrl,
// historyUrl, folderUrl }. A picture loads from raw.githubusercontent.com
// while the repository is public (no credential), as a README's does.
var MARKDOWN_FILE = /\.(md|markdown|mdown|mkdn?|mkd)$/i;
var IMAGE_FILE = /\.(png|jpe?g|gif|webp|bmp|ico|svg)$/i;

function fileOf(repository, repo, ref, path) {
    const file = repository ? repository.file : null;
    if (!file)
        return null;
    const parts = String(path).split("/");
    const name = parts.pop();
    const dir = parts.join("/");
    const history = repository.at && repository.at.history ? nodesOf(repository.at.history) : [];
    const isPrivate = !!repository.isPrivate;
    const blob = file.__typename === "Blob";
    const text = blob && typeof file.text === "string" ? file.text : null;
    const rows = text === null || text === "" ? [] : text.replace(/\n$/, "").split("\n");
    const image = blob && IMAGE_FILE.test(name);
    return {
        "repo": repo,
        "ref": ref,
        "path": path,
        "name": name,
        "dir": dir,
        "isPrivate": isPrivate,
        "folder": !blob,
        "size": blob ? Number(file.byteSize || 0) : 0,
        "binary": blob && !!file.isBinary,
        "truncated": blob && !!file.isTruncated,
        "text": text,
        "lines": rows.length,
        "loc": rows.filter(row => /\S/.test(row)).length,
        "markdown": blob && MARKDOWN_FILE.test(name),
        "image": image,
        "imageUrl": image && !isPrivate ? "https://raw.githubusercontent.com/" + repo + "/" + encodePath(ref) + "/" + encodePath(path) : "",
        "commit": history.length > 0 ? commitOf(history[0], repo) : null,
        "url": repoUrl(repo) + "/" + (blob ? "blob" : "tree") + "/" + encodePath(ref) + "/" + encodePath(path),
        "rawUrl": repoUrl(repo) + "/raw/" + encodePath(ref) + "/" + encodePath(path),
        "historyUrl": repoUrl(repo) + "/commits/" + encodePath(ref) + "/" + encodePath(path),
        "folderUrl": repoUrl(repo) + "/tree/" + encodePath(ref) + (dir !== "" ? "/" + encodePath(dir) : "")
    };
}

// One file of a commit (the REST commit endpoint's files).
function commitFileOf(file) {
    const patch = typeof file.patch === "string" ? file.patch : "";
    return {
        "name": String(file.filename || ""),
        "previous": String(file.previous_filename || ""),
        "status": String(file.status || "modified"),
        "additions": Number(file.additions || 0),
        "deletions": Number(file.deletions || 0),
        "changes": Number(file.changes || 0),
        "patch": patch,
        // A binary file and an empty one both come without a patch and
        // without changes, which the API does not tell apart; a diff too
        // large for it has changes and no patch.
        "binary": patch === "" && Number(file.changes || 0) === 0 && file.status !== "renamed",
        "url": String(file.blob_url || "")
    };
}

var FILE_STATUS = {
    "added": {
        "icon": "add_box",
        "tone": "success",
        "label": "Added"
    },
    "removed": {
        "icon": "indeterminate_check_box",
        "tone": "error",
        "label": "Deleted"
    },
    "renamed": {
        "icon": "drive_file_move",
        "tone": "muted",
        "label": "Renamed"
    },
    "copied": {
        "icon": "file_copy",
        "tone": "muted",
        "label": "Copied"
    },
    "changed": {
        "icon": "edit_square",
        "tone": "warning",
        "label": "Changed"
    },
    "modified": {
        "icon": "edit_square",
        "tone": "warning",
        "label": "Modified"
    }
};

function fileStatus(status) {
    return FILE_STATUS[status] || FILE_STATUS.modified;
}

// A unified diff hunk by hunk, as github.com's split-less view draws it:
// [{ type: "hunk"|"add"|"del"|"context"|"note", old, new, text }], each
// line numbered on the side it belongs to (0 where it has none).
function diffLines(patch) {
    const out = [];
    let oldLine = 0;
    let newLine = 0;
    for (const line of String(patch || "").split("\n")) {
        const hunk = line.match(/^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@(.*)$/);
        if (hunk) {
            oldLine = Number(hunk[1]);
            newLine = Number(hunk[2]);
            out.push({
                "type": "hunk",
                "old": 0,
                "new": 0,
                "text": line
            });
        } else if (line.charAt(0) === "+") {
            out.push({
                "type": "add",
                "old": 0,
                "new": newLine++,
                "text": line.slice(1)
            });
        } else if (line.charAt(0) === "-") {
            out.push({
                "type": "del",
                "old": oldLine++,
                "new": 0,
                "text": line.slice(1)
            });
        } else if (line.charAt(0) === "\\") {
            out.push({
                "type": "note",
                "old": 0,
                "new": 0,
                "text": line.slice(1).trim()
            });
        } else if (out.length > 0) {
            out.push({
                "type": "context",
                "old": oldLine++,
                "new": newLine++,
                "text": line.slice(1)
            });
        }
    }
    return out;
}

// The five blocks of a diffstat, as github.com draws them after a count of
// changes: green for additions, red for deletions, grey for the rest, a
// block a change up to five.
function diffstatBlocks(additions, deletions) {
    const a = Number(additions || 0);
    const d = Number(deletions || 0);
    const filled = Math.min(5, a + d);
    const added = filled > 0 ? Math.round(filled * a / (a + d)) : 0;
    const out = [];
    for (let i = 0; i < 5; i++)
        out.push(i < added ? "add" : (i < filled ? "del" : "none"));
    return out;
}

// Which files of a commit show their diff at once: github.com folds a
// large one ("Large diffs are not rendered by default"), and so does this
// page past a budget of lines for the whole commit, so a commit of
// thousands of lines opens at once; each opens on a click.
function diffsShown(files, budget, largest) {
    let left = budget;
    return (files || []).map(file => {
        const lines = file.patch === "" ? 0 : file.patch.split("\n").length;
        if (lines === 0 || file.changes > largest || lines > left)
            return false;
        left -= lines;
        return true;
    });
}

// The pull requests a commit belongs to, as github.com names them under
// its message.
function commitPulls(node) {
    return nodesOf(node ? node.associatedPullRequests : null).map(pr => ({
                "kind": "pr",
                "number": Number(pr.number),
                "title": String(pr.title || ""),
                "url": String(pr.url),
                "state": String(pr.state || "OPEN"),
                "isDraft": !!pr.isDraft,
                "repo": pr.repository ? String(pr.repository.nameWithOwner) : ""
            }));
}

// A release as the releases list shows it: what GitHub also offers as
// assets (the source code archives) after its own.
function releaseOf(node, repo) {
    if (!node || !node.tagName)
        return null;
    const tag = String(node.tagName);
    const archive = repoUrl(repo) + "/archive/refs/tags/" + encodePath(tag);
    const assets = nodesOf(node.releaseAssets).map(asset => ({
                "name": String(asset.name),
                "size": fileSize(asset.size),
                "downloads": Number(asset.downloadCount || 0),
                "url": String(asset.downloadUrl || ""),
                "at": String(asset.updatedAt || ""),
                "source": false
            }));
    return {
        "id": String(node.id || ""),
        "name": String(node.name || tag),
        "tag": tag,
        "url": String(node.url || ""),
        "prerelease": !!node.isPrerelease,
        "draft": !!node.isDraft,
        "latest": !!node.isLatest,
        "createdAt": String(node.createdAt || ""),
        "publishedAt": String(node.publishedAt || node.createdAt || ""),
        "author": node.author ? String(node.author.login || "") : "",
        "body": String(node.description || ""),
        "commit": node.tagCommit ? {
            "sha": String(node.tagCommit.oid),
            "short": String(node.tagCommit.abbreviatedOid || String(node.tagCommit.oid).slice(0, 7))
        } : null,
        "mentions": node.mentions ? Number(node.mentions.totalCount || 0) : 0,
        "assets": assets.concat([
            {
                "name": "Source code (zip)",
                "size": "",
                "downloads": 0,
                "url": archive + ".zip",
                "at": String(node.createdAt || ""),
                "source": true
            },
            {
                "name": "Source code (tar.gz)",
                "size": "",
                "downloads": 0,
                "url": archive + ".tar.gz",
                "at": String(node.createdAt || ""),
                "source": true
            }
        ]),
        "assetsTotal": totalOf(node.releaseAssets, assets.length) + 2,
        // A release takes six of the eight reactions: the picker offers
        // those GitHub lists for it.
        "reactions": reactionsOf(node) ? Object.assign(reactionsOf(node), {
            "contents": node.reactionGroups.map(group => String(group.content))
        }) : null
    };
}

// A page of releases (queries/browse.graphql's Releases).
function releasesOf(repository) {
    if (!repository || !repository.releases)
        return null;
    const repo = String(repository.nameWithOwner);
    return {
        "releases": nodesOf(repository.releases).map(node => releaseOf(node, repo)).filter(r => !!r),
        "total": Number(repository.releases.totalCount || 0),
        "more": !!(repository.releases.pageInfo && repository.releases.pageInfo.hasNextPage),
        "cursor": repository.releases.pageInfo ? String(repository.releases.pageInfo.endCursor || "") : ""
    };
}

// The posts of a page of releases whose notes name pictures or videos,
// for their signed URLs (GitHubData.loadMedia; Rendered reads a release's
// descriptionHTML as its bodyHTML).
function releaseRendering(releases) {
    return (releases || []).filter(r => r.id && (imagesIn(r.body).length > 0 || videosIn(r.body).length > 0)).map(r => ({
                "id": r.id,
                "body": r.body
            }));
}

// A repository on a profile (pinned, popular, or recent).
function repoCardOf(node) {
    return {
        "repo": String(node.nameWithOwner),
        "name": String(node.name),
        "owner": node.owner ? String(node.owner.login) : String(node.nameWithOwner).split("/")[0],
        "description": String(node.description || ""),
        "isPrivate": !!node.isPrivate,
        "isFork": !!node.isFork,
        "isArchived": !!node.isArchived,
        "parent": node.parent ? String(node.parent.nameWithOwner) : "",
        "stars": Number(node.stargazerCount || 0),
        "forks": Number(node.forkCount || 0),
        "pushedAt": String(node.pushedAt || ""),
        "language": node.primaryLanguage ? String(node.primaryLanguage.name) : "",
        "languageColor": node.primaryLanguage ? String(node.primaryLanguage.color || "") : ""
    };
}

var CONTRIBUTION_LEVELS = {
    "NONE": 0,
    "FIRST_QUARTILE": 1,
    "SECOND_QUARTILE": 2,
    "THIRD_QUARTILE": 3,
    "FOURTH_QUARTILE": 4
};

// A person's or an organization's profile (queries/browse.graphql's
// Owner): the repositories it shows are the pinned ones, or the most
// starred when nothing is pinned, as github.com's overview.
function ownerOf(owner) {
    if (!owner || !owner.login)
        return null;
    const isOrg = owner.__typename === "Organization";
    const pinned = nodesOf(owner.pinnedItems).filter(node => !!node.nameWithOwner).map(repoCardOf);
    const calendar = owner.contributionsCollection ? owner.contributionsCollection.contributionCalendar : null;
    const status = owner.status && (owner.status.message || owner.status.emoji) ? {
        "emoji": String(owner.status.emoji || ""),
        "message": String(owner.status.message || "")
    } : null;
    return {
        "login": String(owner.login),
        "isOrg": isOrg,
        "url": String(owner.url || "https://github.com/" + owner.login),
        "name": String(owner.name || ""),
        "bio": String((isOrg ? owner.description : owner.bio) || ""),
        "company": String(owner.company || ""),
        "location": String(owner.location || ""),
        "website": siteUrl(owner.websiteUrl),
        "websiteText": String(owner.websiteUrl || "").replace(/^https?:\/\//i, "").replace(/\/$/, ""),
        "email": String(owner.email || ""),
        "twitter": String(owner.twitterUsername || ""),
        "pronouns": String(owner.pronouns || ""),
        "createdAt": String(owner.createdAt || ""),
        "isViewer": !!owner.isViewer,
        "verified": !!owner.isVerified,
        "status": status,
        "followers": totalOf(owner.followers, 0),
        "following": totalOf(owner.following, 0),
        "stars": totalOf(owner.starredRepositories, 0),
        "members": totalOf(owner.membersWithRole, 0),
        "orgs": nodesOf(owner.organizations).map(org => ({
                    "login": String(org.login),
                    "name": String(org.name || org.login)
                })),
        "social": nodesOf(owner.socialAccounts).map(account => ({
                    "provider": String(account.provider || ""),
                    "text": String(account.displayName || account.url || ""),
                    "url": externalUrl(account.url)
                })).filter(account => account.url !== ""),
        "pinned": pinned.length > 0,
        "repos": pinned.length > 0 ? pinned : nodesOf(owner.popular).map(repoCardOf),
        "recent": nodesOf(owner.recent).map(repoCardOf),
        "reposTotal": totalOf(owner.recent, 0),
        "contributions": calendar ? {
            "total": Number(calendar.totalContributions || 0),
            "weeks": (calendar.weeks || []).map(week => (week.contributionDays || []).map(day => ({
                            "date": String(day.date),
                            "count": Number(day.contributionCount || 0),
                            "level": CONTRIBUTION_LEVELS[day.contributionLevel] || 0
                        })))
        } : null
    };
}

// The month labels over a contribution calendar: a month names the week
// column its first Sunday starts, as github.com labels them; one that
// would crowd the label before it (a month cut short at the start) is
// left out.
function contributionMonths(weeks) {
    const out = [];
    let last = -1;
    (weeks || []).forEach((week, index) => {
        if (!week || week.length === 0)
            return;
        const month = Number(String(week[0].date).slice(5, 7)) - 1;
        if (month === last)
            return;
        last = month;
        if (out.length > 0 && index - out[out.length - 1].week < 3)
            out.pop();
        out.push({
            "week": index,
            "label": MONTHS[month]
        });
    });
    return out;
}

// What the popout header says of such a page (GitHubBrowseHeader), as
// github.com's page heading: { avatar, square (an organization's), owner
// (a link before the title), lead (a commit's SHA, as a pull request's
// number), title, badges: [{ text, tone }], line: [{ text, url, icon,
// mono }] }.
function pageHeader(item, detail) {
    const header = {
        "avatar": "",
        "square": false,
        "owner": "",
        "lead": "",
        "title": "",
        "badges": [],
        "line": []
    };
    if (!item)
        return header;
    const repoLink = {
        "text": String(item.repo || ""),
        "url": repoUrl(item.repo),
        "icon": "repo"
    };
    switch (item.kind) {
    case "repo":
        {
            const parts = String(item.repo).split("/");
            header.avatar = parts[0];
            header.square = !!detail && detail.ownerIsOrg;
            header.owner = parts[0];
            header.title = parts[1];
            if (detail) {
                const visibility = detail.isPrivate ? "Private" : "Public";
                header.badges.push({
                    "text": detail.isArchived ? visibility + " archive" : (detail.isTemplate ? visibility + " template" : (detail.isMirror ? visibility + " mirror" : visibility)),
                    "tone": detail.isArchived ? "warning" : "muted"
                });
                if (detail.parent !== "")
                    header.line.push({
                        "text": "forked from " + detail.parent,
                        "url": repoUrl(detail.parent),
                        "icon": "repo-forked"
                    });
                header.line.push({
                    "text": shortCount(detail.stars),
                    "url": repoUrl(item.repo) + "/stargazers",
                    "icon": detail.starred ? "star-fill" : "star"
                }, {
                    "text": shortCount(detail.forks),
                    "url": repoUrl(item.repo) + "/forks",
                    "icon": "repo-forked"
                }, {
                    "text": shortCount(detail.watchers),
                    "url": repoUrl(item.repo) + "/watchers",
                    "icon": "eye"
                });
            }
            break;
        }
    case "commits":
        {
            const ref = detail && detail.ref ? detail.ref : (item.ref || (detail ? detail.defaultBranch : ""));
            header.title = "Commits";
            header.line.push(repoLink, {
                "text": ref,
                "url": branchUrl(item.repo, ref),
                "icon": "git-branch",
                "mono": true
            });
            if (detail && detail.path)
                header.line.push({
                    "text": detail.path,
                    "url": repoUrl(item.repo) + "/tree/" + encodePath(ref) + "/" + encodePath(detail.path),
                    "icon": "file-directory-fill",
                    "mono": true
                });
        }
        if (detail)
            header.line.push({
                "text": plural(detail.total, "commit")
            });
        break;
    case "commit":
        header.lead = String(item.sha).slice(0, 7);
        header.title = detail ? detail.commit.headline : "Commit " + header.lead;
        header.line.push(repoLink);
        if (detail && detail.commit.verified)
            header.badges.push({
                "text": "Verified",
                "tone": "success"
            });
        break;
    case "releases":
        header.title = "Releases";
        header.line.push(repoLink);
        if (detail)
            header.line.push({
                "text": plural(detail.total, "release"),
                "icon": "tag"
            });
        break;
    case "release":
        header.title = detail ? detail.name : (item.tag || "Latest release");
        if (detail) {
            if (detail.draft)
                header.badges.push({
                    "text": "Draft",
                    "tone": "muted"
                });
            if (detail.prerelease)
                header.badges.push({
                    "text": "Pre-release",
                    "tone": "warning"
                });
            if (detail.latest)
                header.badges.push({
                    "text": "Latest",
                    "tone": "success"
                });
        }
        header.line.push(repoLink);
        if (detail)
            header.line.push({
                "text": detail.tag,
                "url": repoUrl(item.repo) + "/tree/" + encodePath(detail.tag),
                "icon": "tag",
                "mono": true
            });
        break;
    case "file":
        // The file's name, and where it is: the repository, the branch (or
        // tag, or commit), and its folder.
        header.title = detail ? detail.name : String(item.target).split("/").pop();
        header.line.push(repoLink);
        if (detail) {
            header.line.push({
                "text": detail.ref,
                "url": branchUrl(item.repo, detail.ref),
                "icon": "git-branch",
                "mono": true
            });
            if (detail.dir !== "")
                header.line.push({
                    "text": detail.dir,
                    "url": detail.folderUrl,
                    "icon": "file-directory-fill",
                    "mono": true
                });
        }
        break;
    case "user":
        // The login, as github.com's sticky header over a profile; the
        // page has the name, the followers, and the rest.
        header.avatar = item.login;
        header.square = !!detail && detail.isOrg;
        header.title = item.login;
        if (detail && detail.verified)
            header.badges.push({
                "text": "Verified",
                "tone": "success"
            });
        if (detail && detail.isOrg)
            header.line.push({
                "text": "Organization",
                "icon": "organization"
            });
        break;
    }
    return header;
}

// What such a page says while its first answer comes.
function pageLoadingText(item) {
    if (!item)
        return "";
    return "Loading " + ({
            "repo": item.repo,
            "commits": "the commits of " + item.repo,
            "commit": "commit " + String(item.sha).slice(0, 7),
            "releases": "the releases of " + item.repo,
            "release": item.tag ? "release " + item.tag : "the latest release of " + item.repo,
            "file": String(item.target || "").split("/").pop(),
            "user": item.login
        })[item.kind] + "…";
}

// ---------------------------------------------------------------- popout

// Whether the popout, shown again, takes up where it was: opened from the
// bar (not for a tab or a notification) within `resumeSeconds` of going
// away (0: never).
function resumes(initialTab, hiddenAt, now, resumeSeconds) {
    return initialTab === "" && hiddenAt > 0 && now - hiddenAt < resumeSeconds * 1000;
}

// A scroll position a view can take: within its content, the top first.
function scrollClamp(y, originY, contentHeight, height) {
    return Math.max(originY, Math.min(y, originY + contentHeight - height));
}
