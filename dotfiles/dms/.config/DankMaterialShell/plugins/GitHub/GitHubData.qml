import QtQuick
import Quickshell
import Quickshell.Io
import qs.Common
import qs.Services
import "GitHubLogic.js" as Logic

// Everything the plugin knows about GitHub, all of it through the GitHub
// CLI, kept once for every bar and window (the daemon owns it): the lists
// from GraphQL searches (queries/inbox.graphql), unread notifications from
// the REST notifications endpoint, Actions runs from `gh run list`, a page
// from queries/detail.graphql or `gh run view`, and every change from the
// matching gh subcommand. The plugin never sees a token; signing in is
// `gh auth login`, and a signed-out CLI turns into a readable state here.
// What an answer means lives in GitHubLogic.js; this file asks and keeps.
Item {
    id: data

    property string pluginDir: ""
    property var settings: ({})

    // "unknown" before the first answer, then "ok", "signedOut", or "error".
    property string authState: "unknown"
    property string login: ""
    // Bumped when gh answers for another account: everything kept for the
    // old one goes, and answers to questions asked before are dropped.
    property int accountGen: 0

    signal accountSwitched()
    // A change went through on this page (url); pages showing it reload.
    signal changed(string url)

    readonly property int listSize: 30
    readonly property int runsPerRepo: 10
    readonly property int repoRunsSize: 30
    readonly property int pickerRepos: 12

    // ------------------------------------------------------------ gh runner
    //
    // Proc.runCommand hands back stdout only; a failed gh call explains
    // itself on stderr, which is what a toast or the popout should say, so
    // gh runs through a Process that keeps both streams. Prompts, the update
    // notice, and colors are switched off: nobody can answer a prompt here.
    Component {
        id: ghProcess

        Process {
            id: proc

            property var done: null
            property int timeoutMs: 30000

            environment: ({
                    "GH_PROMPT_DISABLED": "1",
                    "GH_NO_UPDATE_NOTIFIER": "1",
                    "GH_SPINNER_DISABLED": "1",
                    "NO_COLOR": "1",
                    "CLICOLOR": "0"
                })
            stdout: StdioCollector {}
            stderr: StdioCollector {}
            // Both streams are read to their end before gh's exit is told.
            onExited: exitCode => complete(exitCode, String(stdout.text || ""), String(stderr.text || ""))
            // A command that cannot start (gh missing) never exits: it only
            // stops running. After an exit this finds nothing left to do.
            onRunningChanged: {
                if (!running)
                    complete(127, "", "gh could not be started. Install the GitHub CLI (gh).");
            }

            property Timer deadline: Timer {
                interval: proc.timeoutMs
                running: true
                onTriggered: {
                    proc.complete(124, "", "gh did not answer within " + Math.round(interval / 1000) + " seconds");
                    proc.running = false;
                }
            }

            function complete(exitCode, out, err) {
                if (!done)
                    return;
                const callback = done;
                done = null;
                deadline.stop();
                try {
                    callback(exitCode, out, err);
                } catch (e) {
                    console.warn("github: gh callback failed:", e);
                }
                Qt.callLater(() => proc.destroy());
            }
        }
    }

    // Runs gh in place of a process when set: a function (args, done) that
    // calls done(code, stdout, stderr) once. The tests script gh with it.
    property var runner: null

    // options: timeout (ms); owner, an item whose destruction drops the
    // answer; account (default true), false for a change the viewer made,
    // whose answer must arrive even after an account switch. Any answer
    // asked for since the last switch can notice the next one (takeAccount);
    // one asked for before it is stale, the login it names included.
    function gh(args, callback, options) {
        const opts = options || {};
        const owner = opts.owner || null;
        const gen = accountGen;
        const guarded = opts.account !== false;
        const done = (code, out, err) => {
            if (owner && !Qt.isQtObject(owner))
                return;
            if (guarded && gen !== data.accountGen)
                return;
            callback(code, out, err);
        };
        if (runner) {
            runner(args, done);
            return;
        }
        const proc = ghProcess.createObject(data, {
            command: ["gh"].concat(args),
            done: done,
            timeoutMs: opts.timeout || 30000
        });
        proc.running = true;
    }

    // A GraphQL operation from queries/<file>.graphql. The callback gets
    // GitHub's answer ({ data, errors }) whenever it has data, even when gh
    // exits 1 over an error in part of it, and otherwise null and why.
    function graphql(file, operation, vars, callback, options) {
        gh(Logic.graphqlArgs(pluginDir + "/queries/" + file + ".graphql", operation, vars), (code, out, err) => {
            const answer = Logic.graphqlAnswer(out);
            if (answer && answer.data) {
                callback(answer, "");
                return;
            }
            const failure = Logic.describeFailure(code, err);
            callback(null, failure !== "signedOut" && answer && answer.errors.length > 0 ? answer.errors[0].message : failure);
        }, options);
    }

    function repoVars(repo) {
        const parts = String(repo).split("/");
        return {
            "owner": parts[0],
            "name": parts[1]
        };
    }

    // Runs a gh command in a terminal, where it can ask and confirm in the
    // browser (signing in, adding a scope).
    function runInTerminal(title, command) {
        Quickshell.execDetached(["xdg-terminal-exec", "--title=" + title, "--", "sh", "-c", command + "; status=$?; printf '\\nPress Enter to close.'; read _; exit $status"]);
    }

    // Through the shell's clipboard, which keeps it after the popout
    // closes; `toast` says what was copied, when that needs saying.
    function copy(text, toast) {
        Quickshell.execDetached([Proc.dmsBin, "cl", "copy", String(text)]);
        if (toast)
            ToastService.showInfo(toast);
    }

    // ------------------------------------------------------------ watchers
    //
    // The popout and every window say while they are on screen; what only
    // matters to a viewer (the full lists, runs in progress) is fetched only
    // then, and the bar's counts meanwhile.
    property var watchers: []
    readonly property bool watched: watchers.length > 0

    function setWatching(owner, on) {
        const rest = watchers.filter(other => other !== owner && Qt.isQtObject(other));
        watchers = on ? rest.concat([owner]) : rest;
    }

    // Whatever comes on screen first (the popout, or a window opened
    // straight from the menu) finds the lists and the inbox fresh: kept
    // from less than 20 seconds ago, or asked for now.
    onWatchedChanged: {
        if (!watched)
            return;
        if (Date.now() - scopeOf("").at > 20000)
            refreshInbox();
        if (Date.now() - notificationsFullAt > 20000)
            refreshNotifications();
    }

    // ---------------------------------------------------------------- lists
    //
    // lists: key -> { items, cursor, more, count, loading, gen }. A refresh
    // replaces a list's first page; a list scrolled past it is fetched again
    // as a whole, so its pages and cursor always belong to one pass, and gen
    // drops a next page asked for before that.
    property var lists: ({})
    // The counts the bar adds that are no list (Logic.COUNTS).
    property var counted: ({})
    readonly property var emptyList: ({
            "items": [],
            "cursor": "",
            "more": false,
            "count": 0,
            "loading": false,
            "gen": 0
        })
    // key -> the loaded items not hidden by a change made here.
    // A list nothing is hidden from keeps its own items, so a change to
    // another part of its record (loading) rebuilds no rows.
    readonly property var visibleLists: {
        const out = {};
        for (const key in lists) {
            const items = lists[key].items;
            out[key] = items.some(item => isHidden(item, key)) ? items.filter(item => !isHidden(item, key)) : items;
        }
        return out;
    }

    function listOf(key) {
        return lists[key] || emptyList;
    }

    function patchList(key, fields) {
        lists = Logic.withKey(lists, key, Object.assign({}, listOf(key), fields));
    }

    function visibleItems(key) {
        return visibleLists[key] || [];
    }

    // How many results a search has, less the items a change here took out
    // of it while GitHub's count still has them (it has not changed since).
    function total(key) {
        const list = listOf(key);
        let waiting = 0;
        for (const item of list.items) {
            const entry = hidden[item.url];
            if (entry && Logic.hiddenIn(entry.action, key) && entry.counts[key] === list.count)
                waiting++;
        }
        return Math.max(0, list.count - waiting);
    }

    // What a tab's count says, for the tabs and the bar's menu alike: unread
    // notifications, runs in progress, or its first list's total.
    function tabCount(scope, tab) {
        if (tab === "inbox")
            return unreadNotifications.length;
        if (tab === "actions")
            return Logic.filterRuns(scopeOf(scope).runs, "active").length;
        return total(Logic.primaryKey(scope, tab));
    }

    // The count as a badge writes it: "" for none, and a "+" on the unread
    // notifications while there are more than the pages loaded.
    function countText(count, tab) {
        return count > 0 ? String(count) + (tab === "inbox" && moreNotifications ? "+" : "") : "";
    }

    function sameJson(a, b) {
        return JSON.stringify(a) === JSON.stringify(b);
    }

    // The first page of each list of a scope in a GraphQL answer, whose
    // aliases are the list names. `reset` (an explicit refresh) starts every
    // list over from it.
    function takeFirstPages(answer, scope, reset) {
        const next = Object.assign({}, lists);
        const ranges = [];
        let changed = false;
        for (const key of Logic.listKeys(scope)) {
            const current = listOf(key);
            const record = Logic.firstPageRecord(current, Logic.pageOf(answer[Logic.keyName(key)]), reset, listSize);
            if (!record) {
                ranges.push(key);
                continue;
            }
            if (!sameJson(current, record)) {
                next[key] = record;
                changed = true;
            }
        }
        if (changed)
            lists = next;
        for (const key of ranges)
            reloadRange(key, listOf(key).items.length);
    }

    // A list scrolled past its first page, asked for again as far as it was
    // loaded, 100 at a time (GitHub's most). It stays loading until then,
    // so no next page is asked for with the old cursor meanwhile.
    function reloadRange(key, loaded) {
        const gen = listOf(key).gen + 1;
        patchList(key, {
            "gen": gen,
            "loading": true
        });
        let items = [];
        const step = after => {
            graphql("inbox", "Page", {
                "search": Logic.searchFor(key),
                "first": Math.min(100, loaded - items.length),
                "after": after || null
            }, (answer, failure) => {
                if (listOf(key).gen !== gen)
                    return;
                if (!answer) {
                    patchList(key, {
                        "loading": false
                    });
                    return;
                }
                const page = Logic.pageOf(answer.data.search);
                items = Logic.appendNew(items, page.items, "url");
                if (page.more && page.items.length > 0 && items.length < loaded) {
                    step(page.cursor);
                    return;
                }
                patchList(key, {
                    "items": items,
                    "cursor": page.cursor,
                    "more": page.more,
                    "count": page.count,
                    "loading": false
                });
            }, {
                "timeout": 45000
            });
        };
        step("");
    }

    // The next page of one list, as it scrolls to its end.
    function loadMore(key) {
        const list = listOf(key);
        if (!Logic.searchFor(key) || !list.more || list.loading || !list.cursor)
            return;
        const gen = list.gen;
        patchList(key, {
            "loading": true
        });
        graphql("inbox", "Page", {
            "search": Logic.searchFor(key),
            "first": listSize,
            "after": list.cursor
        }, (answer, failure) => {
            const current = listOf(key);
            if (current.gen !== gen)
                return;
            if (!answer) {
                patchList(key, {
                    "loading": false
                });
                ToastService.showError("GitHub: more results", Logic.failureText(failure));
                return;
            }
            const page = Logic.pageOf(answer.data.search);
            patchList(key, {
                "items": Logic.appendNew(current.items, page.items, "url"),
                "cursor": page.cursor,
                "more": page.more,
                "count": page.count || current.count,
                "loading": false
            });
        });
    }

    // What the viewer types in a pull request or issue list goes to GitHub:
    // the list's own search in every state (Logic.searchBase) with the words
    // added, GitHub's search syntax and all. Each panel keeps its own
    // search, so the answer goes back to the caller: { items, cursor, more,
    // count, error }.
    function searchPage(key, words, after, callback, owner) {
        if (!Logic.searchFor(key))
            return;
        graphql("inbox", "Page", {
            "search": Logic.searchBase(key) + " " + words,
            "first": listSize,
            "after": after || null
        }, (answer, failure) => {
            const page = Logic.pageOf(answer ? answer.data.search : null);
            page.error = answer ? "" : Logic.failureText(failure);
            callback(page);
        }, {
            "owner": owner
        });
    }

    // An item that just changed state leaves the lists it no longer belongs
    // in at once (Logic.hiddenIn): search results lag behind a change by
    // several seconds, so the next refresh would otherwise bring it back.
    // Each entry keeps the counts of the lists it left, which still count
    // it until GitHub's own count moves; entries expire after hideMs.
    property var hidden: ({})
    readonly property int hideMs: 120000

    function hide(url, action) {
        const counts = {};
        for (const key in lists)
            if (Logic.hiddenIn(action, key) && lists[key].items.some(item => item.url === url))
                counts[key] = lists[key].count;
        hidden = Logic.withKey(hidden, url, {
            "at": Date.now(),
            "action": action,
            "counts": counts
        });
        expireHidden();
    }

    function isHidden(item, key) {
        const entry = hidden[item.url];
        return !!entry && Logic.hiddenIn(entry.action, key);
    }

    // Drops the entries past hideMs and waits for the next one.
    function expireHidden() {
        const now = Date.now();
        const next = {};
        let soonest = 0;
        for (const url in hidden) {
            const ends = hidden[url].at + hideMs;
            if (ends <= now)
                continue;
            next[url] = hidden[url];
            soonest = soonest === 0 ? ends : Math.min(soonest, ends);
        }
        if (Object.keys(next).length !== Object.keys(hidden).length)
            hidden = next;
        if (soonest > 0) {
            hiddenExpiry.interval = Math.max(100, soonest - now);
            hiddenExpiry.restart();
        }
    }

    Timer {
        id: hiddenExpiry
        onTriggered: data.expireHidden()
    }

    // --------------------------------------------------------------- scopes
    //
    // scopes: "" (what involves the viewer) or "owner/name" -> when its
    // lists last came, whether they are coming, why they failed, and its
    // workflow runs (the viewer's are the watched repositories').
    property var scopes: ({})
    property var pushedRepos: []
    readonly property var emptyScope: ({
            "at": 0,
            "loading": false,
            "error": "",
            "runs": [],
            "runsAt": 0,
            "runsFullAt": 0,
            "runsLoading": false,
            "runsError": ""
        })
    readonly property var watchedRepos: {
        const configured = [];
        const entries = settings && settings.repositories ? settings.repositories : [];
        for (let i = 0; i < entries.length; i++) {
            const name = String((entries[i] && entries[i].repo) || entries[i] || "").trim();
            if (Logic.isRepo(name) && configured.indexOf(name) < 0)
                configured.push(name);
        }
        return configured.length > 0 ? configured : pushedRepos.slice(0, 5);
    }
    function scopeOf(scope) {
        return scopes[scope || ""] || emptyScope;
    }

    function patchScope(scope, fields) {
        scopes = Logic.withKey(scopes, scope || "", Object.assign({}, scopeOf(scope), fields));
    }

    // The repositories the viewer's runs are for. Every settings save
    // rebuilds the list, so only a real change counts: a repository that
    // left takes its runs along at once, and the rest follow GitHub now if
    // someone looks, or when someone next does.
    property var runsRepos: []
    onWatchedReposChanged: {
        if (sameJson(watchedRepos, runsRepos))
            return;
        runsRepos = watchedRepos;
        patchScope("", {
            "runs": scopeOf("").runs.filter(run => watchedRepos.indexOf(run.repo) >= 0)
        });
        if (watched)
            refreshRuns("", {
                "again": true
            });
        else
            patchScope("", {
                "runsAt": 0,
                "runsFullAt": 0
            });
    }

    // A refresh asked for while the same one is on its way runs once more
    // when that one settles, when it matters that the answer is not older
    // than the ask (`again`: the viewer's Refresh, the refresh after a
    // change); a background poll just skips. key -> whether it resets.
    property var again: ({})

    function askAgain(key, reset) {
        again = Logic.withKey(again, key, again[key] === true || reset === true);
    }

    // Whether `key` was asked for again (null if not), and whether to reset.
    function takeAgain(key) {
        if (!(key in again))
            return null;
        const reset = again[key];
        again = Logic.withKey(again, key, undefined);
        return reset;
    }

    // The viewer's lists, login, and recently pushed repositories.
    // options: reset (the viewer's Refresh: every list starts over from its
    // first page, and the notifications and runs come in full too), again.
    function refreshInbox(options) {
        const opts = options || {};
        if (opts.reset) {
            dropNotificationPages();
            refreshNotifications({
                "again": true
            });
            refreshRuns("", {
                "again": true
            });
        }
        if (pluginDir === "")
            return;
        if (scopeOf("").loading) {
            if (opts.reset || opts.again)
                askAgain("inbox", opts.reset);
            return;
        }
        patchScope("", {
            "loading": true
        });
        const vars = Object.assign({
            "first": listSize,
            "repos": pickerRepos
        }, Logic.searchVariables(""));
        const settle = () => {
            const reset = takeAgain("inbox");
            if (reset !== null)
                refreshInbox({
                    "reset": reset
                });
        };
        graphql("inbox", "Inbox", vars, (answer, failure) => {
            if (!answer || !answer.data.viewer) {
                failed(failure);
                settle();
                return;
            }
            const d = answer.data;
            if (!takeAccount(String(d.viewer.login || "")))
                return;
            const repos = Logic.nodesOf(d.viewer.repositories).filter(node => node.nameWithOwner).map(node => String(node.nameWithOwner));
            if (!sameJson(repos, pushedRepos))
                pushedRepos = repos;
            takeFirstPages(d, "", opts.reset === true);
            takeCounts(d);
            patchScope("", {
                "loading": false,
                "error": "",
                "at": Date.now()
            });
            if (scopeOf("").runsFullAt === 0)
                refreshRuns("");
            settle();
        }, {
            "timeout": 45000
        });
    }

    // While nothing is on screen the bar needs counts only, and the account
    // they are for: a switch in gh shows here too.
    property bool loadingBadge: false
    readonly property var badgeLists: ["prReview", "issueAssigned"]

    function refreshBadge() {
        if (loadingBadge || pluginDir === "")
            return;
        loadingBadge = true;
        const vars = {
            "prAssignedOnly": Logic.COUNTS.prAssignedOnly
        };
        for (const name of badgeLists)
            vars[name] = Logic.searchFor(name);
        graphql("inbox", "Badge", vars, (answer, failure) => {
            loadingBadge = false;
            if (!answer || !answer.data.viewer) {
                if (failure === "signedOut")
                    authState = "signedOut";
                return;
            }
            const d = answer.data;
            if (!takeAccount(String(d.viewer.login || "")))
                return;
            const next = Object.assign({}, lists);
            let changed = false;
            for (const name of badgeLists) {
                const count = Number(d[name] ? d[name].issueCount : 0);
                if (listOf(name).count !== count) {
                    next[name] = Object.assign({}, listOf(name), {
                        "count": count
                    });
                    changed = true;
                }
            }
            if (changed)
                lists = next;
            takeCounts(d);
        });
    }

    function takeCounts(d) {
        const next = {};
        for (const name in Logic.COUNTS)
            next[name] = d[name] ? Number(d[name].issueCount || 0) : 0;
        if (!sameJson(next, counted))
            counted = next;
    }

    // The account gh answered for. Another one than before drops everything
    // kept for the old account and says so (false); the caller asks again.
    // The old account's things go before the new login shows, so nothing
    // reading the login sees them as the new account's.
    function takeAccount(who) {
        authState = "ok";
        if (login !== "" && who !== login) {
            resetAccount();
            login = who;
            accountSwitched();
            refreshInbox({
                "reset": true
            });
            return false;
        }
        login = who;
        return true;
    }

    // Answers to questions asked before are dropped (gh's account guard),
    // so whatever waited for one stops waiting too.
    function resetAccount() {
        accountGen++;
        lists = {};
        counted = {};
        scopes = {};
        repoOrder = [];
        hidden = {};
        again = {};
        pushedRepos = [];
        notifications = [];
        dropNotificationPages();
        loadingNotifications = false;
        loadingBadge = false;
        notificationsModified = "";
        notificationsAt = 0;
        notificationsFullAt = 0;
        notificationsError = "";
        readThreads = {};
        tokenScopes = null;
        runAccess = {};
        jobLogs = {};
        jobLogOrder = [];
        drafts = {};
    }

    function failed(failure) {
        if (failure === "signedOut") {
            authState = "signedOut";
            patchScope("", {
                "loading": false,
                "error": ""
            });
        } else {
            authState = authState === "ok" ? "ok" : "error";
            patchScope("", {
                "loading": false,
                "error": Logic.failureText(failure)
            });
        }
    }

    // The repositories whose lists are kept, most recently asked for first:
    // every one a panel on screen shows, and of the rest the latest, up to
    // reposKept in all, so a long session does not keep every repository
    // it ever showed and never empties one on screen.
    property var repoOrder: []
    readonly property int reposKept: 6

    function keepRepo(repo) {
        const shown = watchers.map(owner => String(owner.scope || ""));
        const pinned = other => other === repo || shown.indexOf(other) >= 0;
        const order = [repo].concat(repoOrder.filter(other => other !== repo));
        let room = reposKept - order.filter(pinned).length;
        const kept = order.filter(other => pinned(other) || room-- > 0);
        const dropped = order.filter(other => kept.indexOf(other) < 0);
        repoOrder = kept;
        if (dropped.length === 0)
            return;
        const nextLists = {};
        for (const key in lists)
            if (dropped.indexOf(Logic.keyRepo(key)) < 0)
                nextLists[key] = lists[key];
        lists = nextLists;
        let nextScopes = scopes;
        for (const other of dropped)
            nextScopes = Logic.withKey(nextScopes, other, undefined);
        scopes = nextScopes;
    }

    // One repository's pull requests and issues (open, merged, closed), and
    // its runs, for a panel that picked it. options: reset, again, and
    // runs (default true), false after a change that cannot move them.
    function refreshRepo(repo, options) {
        const opts = options || {};
        if (!Logic.isRepo(repo) || pluginDir === "")
            return;
        keepRepo(repo);
        if (opts.runs !== false)
            refreshRuns(repo, {
                "again": opts.again || opts.reset
            });
        if (scopeOf(repo).loading) {
            if (opts.reset || opts.again)
                askAgain("repo:" + repo, opts.reset);
            return;
        }
        patchScope(repo, {
            "loading": true
        });
        graphql("inbox", "Repository", Object.assign({
            "first": listSize
        }, Logic.searchVariables(repo)), (answer, failure) => {
            // GitHub answers a repository it cannot search (missing, or
            // private to someone else) with an error beside empty lists.
            const problem = !answer ? Logic.failureText(failure) : (answer.errors.length > 0 ? answer.errors[0].message : "");
            if (problem === "")
                takeFirstPages(answer.data, repo, opts.reset === true);
            patchScope(repo, {
                "loading": false,
                "error": problem,
                "at": Date.now()
            });
            const reset = takeAgain("repo:" + repo);
            if (reset !== null)
                refreshRepo(repo, {
                    "reset": reset,
                    "runs": false
                });
        }, {
            "timeout": 45000
        });
    }

    // Repositories on GitHub by name, for the picker: "words" searches
    // every repository, "owner/words" one owner's. Answers [name] or null.
    function searchRepos(text, callback, owner) {
        const words = String(text || "").trim();
        const slash = words.indexOf("/");
        const args = ["search", "repos"];
        if (slash >= 0) {
            const name = words.slice(slash + 1).trim();
            if (name !== "")
                args.push(name);
            args.push("--owner", words.slice(0, slash).trim());
        } else {
            args.push(words);
        }
        args.push("--limit", "8", "--json", "fullName");
        gh(args, (code, out, err) => {
            try {
                callback(code === 0 ? JSON.parse(out || "[]").map(repo => String(repo.fullName)) : null);
            } catch (e) {
                callback(null);
            }
        }, {
            "owner": owner
        });
    }

    // ----------------------------------------------------------------- runs

    // A scope's runs: the watched repositories' for the viewer, or one
    // repository's. options: onlyActive asks again only for the
    // repositories with a run in progress (the quick poll while runs move)
    // and keeps the rest; again. runsAt is the last answer of either kind,
    // runsFullAt the last that looked at every repository (for new runs).
    function refreshRuns(scope, options) {
        const opts = options || {};
        const s = scope || "";
        const record = scopeOf(s);
        if (authState !== "ok")
            return;
        if (record.runsLoading) {
            if (opts.again && !opts.onlyActive)
                askAgain("runs:" + s, false);
            return;
        }
        const watched = s ? [s] : watchedRepos;
        const repos = opts.onlyActive ? watched.filter(repo => record.runs.some(run => run.repo === repo && Logic.isActiveRun(run))) : watched;
        const stamp = opts.onlyActive ? {
            "runsAt": Date.now()
        } : {
            "runsAt": Date.now(),
            "runsFullAt": Date.now()
        };
        if (repos.length === 0) {
            if (!opts.onlyActive)
                patchScope(s, Object.assign({
                    "runs": [],
                    "runsError": ""
                }, stamp));
            return;
        }
        patchScope(s, {
            "runsLoading": true
        });
        const size = s ? repoRunsSize : runsPerRepo;
        const fresh = [];
        const answered = [];
        const errors = [];
        let pending = repos.length;
        for (const repo of repos) {
            listRuns(repo, size, (list, failure) => {
                if (list) {
                    fresh.push(...list);
                    answered.push(repo);
                } else {
                    errors.push(s ? failure : repo + ": " + failure);
                }
                if (--pending > 0)
                    return;
                const before = scopeOf(s).runs;
                const merged = Logic.mergeRuns(before, fresh, answered, s ? [s] : watchedRepos, s ? repoRunsSize : 60);
                patchScope(s, Object.assign({
                    // The same runs keep the same list, so nothing showing
                    // them is rebuilt.
                    "runs": sameJson(merged, before) ? before : merged,
                    "runsLoading": false,
                    "runsError": errors.length === repos.length ? errors.join("\n") : ""
                }, stamp));
                if (takeAgain("runs:" + s) !== null)
                    refreshRuns(s);
            });
        }
    }

    // A repository's latest runs, or null and why not.
    function listRuns(repo, limit, callback) {
        const fields = "databaseId,number,attempt,displayTitle,workflowName,status,conclusion,event,headBranch,createdAt,startedAt,updatedAt,url";
        gh(["run", "list", "-R", repo, "-L", String(limit), "--json", fields], (code, out, err) => {
            if (code !== 0) {
                callback(null, Logic.failureText(Logic.describeFailure(code, err)));
                return;
            }
            try {
                callback(JSON.parse(out || "[]").map(run => Object.assign({
                    "kind": "run",
                    "repo": repo
                }, run)), "");
            } catch (e) {
                callback(null, "unreadable answer");
            }
        });
    }

    // -------------------------------------------------------- notifications
    //
    // The unread threads of the notifications inbox, newest first. The REST
    // API has no search behind it, so a read thread leaves the list the
    // moment it is marked; it comes back only if it changes again.

    property var notifications: []
    property bool loadingNotifications: false
    property double notificationsAt: 0
    // An answer about the inbox came for the account now known, which is
    // what the desktop notifications compare against.
    readonly property bool notificationsReady: login !== "" && notificationsAt > 0
    property string notificationsError: ""
    // Thread id -> the updatedAt it had when it was marked read here.
    property var readThreads: ({})
    readonly property int notificationPage: 50
    // The scopes of gh's token, as the notification polls report them
    // (X-OAuth-Scopes); null when GitHub does not say, as for a
    // fine-grained token. Following a page's notifications needs the
    // notifications scope, which gh auth login does not ask for.
    property var tokenScopes: null
    readonly property bool canSubscribe: tokenScopes === null || tokenScopes.indexOf("notifications") >= 0

    function addNotificationsScope() {
        runInTerminal("GitHub notifications scope", "gh auth refresh -h github.com -s notifications");
    }

    // What GitHub asks a poller to wait between requests (X-Poll-Interval).
    property int notificationPollSeconds: 60
    // Last-Modified of the inbox: a poll that sends it back gets a 304 when
    // nothing changed, which does not count against the rate limit.
    property string notificationsModified: ""
    property double notificationsFullAt: 0
    // Threads from the pages after the first, as the inbox scrolls. Every
    // full answer about the first page checks them again (reconcilePages),
    // so they hold no thread read elsewhere since and leave no gap where new
    // threads pushed others off the first page; pagesGen drops a page asked
    // for before.
    property var extraNotifications: []
    property int notificationPages: 1
    property bool lastPageFull: false
    property bool loadingMoreNotifications: false
    property int pagesGen: 0
    // What the page on its way was asked for (a search's next page), so a
    // refresh that drops it can ask again against the new first page.
    property var pagesThen: null
    readonly property var allNotifications: extraNotifications.length === 0 ? notifications : Logic.appendNew(notifications, extraNotifications, "id")
    readonly property var unreadNotifications: allNotifications.filter(thread => readThreads[thread.id] !== thread.updatedAt)
    // A full last page means there are more.
    readonly property bool moreNotifications: notificationPages > 1 ? lastPageFull : notifications.length >= notificationPage

    // The notifications API has no text search, so searching the inbox
    // fetches the pages after the loaded ones (up to
    // `notificationSearchPages`) and the search filters those.
    readonly property int notificationSearchPages: 10

    function loadAllNotifications() {
        loadNotificationPages(notificationSearchPages);
    }

    // Pages until `pages` are loaded or there are no more.
    function loadNotificationPages(pages) {
        if (!moreNotifications || loadingMoreNotifications || notificationPages >= pages)
            return;
        loadMoreNotifications(() => loadNotificationPages(pages));
    }

    function dropNotificationPages() {
        pagesGen++;
        extraNotifications = [];
        notificationPages = 1;
        lastPageFull = false;
        loadingMoreNotifications = false;
        pagesThen = null;
    }

    // The unread threads of the page before the oldest of `loaded`
    // (Logic.olderThan), so marking threads read meanwhile skips none:
    // done(threads not in `loaded`, whether there may be more), or
    // done(null, why not). More than a page of threads updated in that one
    // second brings the same page back; the next page of the same look then
    // goes on past them.
    function fetchOlder(loaded, done) {
        const before = Logic.olderThan(loaded);
        if (before === "") {
            done([], false);
            return;
        }
        const known = {};
        for (const thread of loaded)
            known[thread.id] = true;
        const step = page => {
            gh(["api", "notifications?per_page=" + notificationPage + "&before=" + encodeURIComponent(before) + (page > 1 ? "&page=" + page : "")], (code, out, err) => {
                let list = null;
                try {
                    list = code === 0 ? JSON.parse(out || "[]") : null;
                } catch (e) {
                    list = null;
                }
                if (!Array.isArray(list)) {
                    done(null, Logic.failureText(Logic.describeFailure(code, err)));
                    return;
                }
                const threads = list.filter(thread => thread && thread.unread).map(thread => Logic.normalizeThread(thread)).filter(thread => !known[thread.id]);
                const full = list.length >= notificationPage;
                if (full && threads.length === 0 && page < notificationSearchPages) {
                    step(page + 1);
                    return;
                }
                done(threads, full && threads.length > 0);
            });
        };
        step(1);
    }

    function loadMoreNotifications(then) {
        if (!moreNotifications || loadingMoreNotifications)
            return;
        const gen = pagesGen;
        loadingMoreNotifications = true;
        pagesThen = then || null;
        fetchOlder(allNotifications, (threads, more) => {
            if (gen !== pagesGen)
                return;
            loadingMoreNotifications = false;
            pagesThen = null;
            if (!threads) {
                ToastService.showError("GitHub: more notifications", more);
                return;
            }
            extraNotifications = extraNotifications.concat(threads);
            notificationPages++;
            lastPageFull = more;
            if (typeof then === "function")
                then();
        });
    }

    // After a full answer about the first page, the later pages come from
    // older answers. A first page that is not full holds every unread
    // thread; otherwise the later pages are fetched again, as far as they
    // went, and take the old ones' place once all came (which stay on
    // screen until then, or when the fetch fails). A next page on its way
    // was asked for against the old first page: it is dropped, and asked
    // for again once the pages agree with the new one.
    function reconcilePages() {
        const pages = notificationPages;
        const interrupted = loadingMoreNotifications;
        const resume = pagesThen;
        const again = () => {
            if (interrupted)
                loadMoreNotifications(resume);
        };
        if (pages <= 1 || notifications.length < notificationPage) {
            if (pages > 1 || interrupted)
                dropNotificationPages();
            again();
            return;
        }
        const gen = ++pagesGen;
        pagesThen = null;
        loadingMoreNotifications = true;
        const staged = [];
        let fetched = 0;
        const step = () => {
            fetchOlder(notifications.concat(staged), (threads, more) => {
                if (gen !== pagesGen)
                    return;
                if (!threads) {
                    loadingMoreNotifications = false;
                    return;
                }
                staged.push(...threads);
                fetched++;
                if (more && fetched < pages - 1) {
                    step();
                    return;
                }
                extraNotifications = staged;
                notificationPages = 1 + fetched;
                lastPageFull = more;
                loadingMoreNotifications = false;
                pruneRead();
                again();
            });
        };
        step();
    }

    // Threads marked read here stay in readThreads only while GitHub still
    // lists them (it can lag behind the mark).
    function pruneRead() {
        const listed = {};
        for (const thread of allNotifications)
            listed[thread.id] = true;
        const next = {};
        for (const id in readThreads)
            if (listed[id])
                next[id] = readThreads[id];
        if (Object.keys(next).length !== Object.keys(readThreads).length)
            readThreads = next;
    }

    // options: conditional polls send Last-Modified back; threads read
    // elsewhere (on github.com) may not move it, so a look the viewer asks
    // for, and any poll ten minutes after the last full answer, asks in
    // full. again.
    function refreshNotifications(options) {
        const opts = options || {};
        if (loadingNotifications) {
            if (opts.again)
                askAgain("notifications", false);
            return;
        }
        loadingNotifications = true;
        const ask = opts.conditional === true && notificationsModified !== "" && Date.now() - notificationsFullAt < 600000;
        const args = ["api", "-i", "notifications?per_page=" + notificationPage];
        if (ask)
            args.push("-H", "If-Modified-Since: " + notificationsModified);
        gh(args, (code, out, err) => {
            loadingNotifications = false;
            takeNotifications(code, out, err);
            if (takeAgain("notifications") !== null)
                refreshNotifications();
        });
    }

    function takeNotifications(code, out, err) {
        // -i puts the status line and headers before the body.
        const text = String(out || "");
        const split = text.search(/\r?\n\r?\n/);
        const head = split >= 0 ? text.slice(0, split) : "";
        const body = split >= 0 ? text.slice(split).trim() : text;
        const header = name => {
            const found = head.match(new RegExp("^" + name + ":\\s*(.+?)\\s*$", "im"));
            return found ? found[1] : "";
        };
        if (/^X-OAuth-Scopes:/im.test(head))
            tokenScopes = header("X-OAuth-Scopes").split(",").map(scope => scope.trim()).filter(scope => scope !== "");
        const poll = Number(header("X-Poll-Interval"));
        if (poll > 0)
            notificationPollSeconds = poll;
        if (/^HTTP\/\S+ 304/.test(head)) {
            notificationsAt = Date.now();
            return;
        }
        let list = null;
        try {
            list = code === 0 ? JSON.parse(body || "[]") : null;
        } catch (e) {
            list = null;
        }
        if (!Array.isArray(list)) {
            const failure = Logic.describeFailure(code, err);
            if (failure === "signedOut")
                authState = "signedOut";
            // A token without the notifications (or repo) scope reads
            // everything else but not this.
            notificationsError = failure === "signedOut" ? "" : (/scope|403|404/i.test(failure) ? "gh cannot read notifications with its current token. Run gh auth refresh -s notifications." : failure);
            return;
        }
        notificationsModified = header("Last-Modified");
        notificationsFullAt = Date.now();
        notificationsError = "";
        // gh reads the inbox again: whatever said it could not (signed out)
        // is past, and the badge query says for which account.
        if (authState !== "ok")
            refreshBadge();
        const threads = list.filter(thread => thread && thread.unread).map(thread => Logic.normalizeThread(thread));
        if (!sameJson(threads, notifications))
            notifications = threads;
        notificationsAt = Date.now();
        reconcilePages();
        pruneRead();
    }

    // Hides threads at once and restores any GitHub refuses.
    function setRead(threads, read) {
        const next = Object.assign({}, readThreads);
        for (const thread of threads) {
            if (read)
                next[thread.id] = thread.updatedAt;
            else
                delete next[thread.id];
        }
        readThreads = next;
    }

    function markRead(thread) {
        if (!thread || readThreads[thread.id] === thread.updatedAt)
            return;
        setRead([thread], true);
        gh(["api", "-X", "PATCH", "notifications/threads/" + thread.id], (code, out, err) => {
            if (code === 0)
                return;
            setRead([thread], false);
            ToastService.showError("GitHub: notification", Logic.failureText(Logic.describeFailure(code, err)));
        });
    }

    // Opening a pull request or an issue reads its notification, as a visit
    // to the page on github.com does.
    function markReadFor(url) {
        for (const thread of unreadNotifications.filter(thread => thread.url === url))
            markRead(thread);
    }

    // Marks notifications read. `everything` is GitHub's "Mark all as
    // read": one request reads every thread up to the newest one given,
    // including those past the fetched page. Otherwise (a filter or a
    // search on screen) exactly the given threads are marked, a few at a
    // time, so nothing off screen is touched. What is hidden is kept first,
    // so a refusal puts back exactly that.
    function markAllRead(threads, everything) {
        const list = threads.filter(thread => readThreads[thread.id] !== thread.updatedAt);
        if (list.length === 0)
            return;
        const affected = everything ? unreadNotifications.slice() : list;
        setRead(affected, true);
        const failed = (restore, code, err) => {
            setRead(restore, false);
            ToastService.showError("GitHub: notifications", Logic.failureText(Logic.describeFailure(code, err)));
        };
        if (everything) {
            const newest = list.reduce((latest, thread) => thread.updatedAt > latest ? thread.updatedAt : latest, "");
            gh(["api", "-X", "PUT", "notifications", "-f", "last_read_at=" + newest], (code, out, err) => {
                if (code !== 0) {
                    failed(affected, code, err);
                    return;
                }
                // GitHub marks a large inbox in the background; look again
                // once it had time to.
                notificationsSoon.restart();
            });
            return;
        }
        let next = 0;
        const worker = () => {
            if (next >= list.length)
                return;
            const thread = list[next++];
            gh(["api", "-X", "PATCH", "notifications/threads/" + thread.id], (code, out, err) => {
                if (code !== 0)
                    failed([thread], code, err);
                worker();
            });
        };
        for (let i = 0; i < Math.min(4, list.length); i++)
            worker();
    }

    // ------------------------------------------------------------- job logs
    //
    // A finished job's log, split into its steps (Logic.splitJobLog). It
    // never changes, so the last few are kept.

    // Job id -> { steps: { number: [line] }, all } for finished jobs.
    property var jobLogs: ({})
    property var jobLogOrder: []
    readonly property int jobLogsKept: 6

    // A log carries terminal colors, which gh prints only when told
    // (--allow-escape-sequences); a gh from before that flag prints them
    // as they are and refuses the flag, so it is asked again without.
    function loadJobLog(repo, job, callback, owner) {
        const key = String(job.databaseId);
        if (jobLogs[key]) {
            callback(jobLogs[key], "");
            return;
        }
        const path = "repos/" + repo + "/actions/jobs/" + key + "/logs";
        gh(["api", "--allow-escape-sequences", path], (code, out, err) => {
            if (code !== 0 && /unknown flag: --allow-escape-sequences/.test(String(err))) {
                gh(["api", path], (plainCode, plainOut, plainErr) => takeJobLog(key, job, plainCode, plainOut, plainErr, callback), {
                    "timeout": 90000,
                    "owner": owner
                });
                return;
            }
            takeJobLog(key, job, code, out, err, callback);
        }, {
            "timeout": 90000,
            "owner": owner
        });
    }

    function takeJobLog(key, job, code, out, err, callback) {
        if (code !== 0) {
            callback(null, Logic.failureText(Logic.describeFailure(code, err)));
            return;
        }
        const log = Logic.splitJobLog(String(out || ""), job.steps || []);
        const order = jobLogOrder.filter(id => id !== key).concat([key]);
        const next = Object.assign({}, jobLogs);
        next[key] = log;
        while (order.length > jobLogsKept)
            delete next[order.shift()];
        jobLogOrder = order;
        jobLogs = next;
        callback(log, "");
    }

    // ---------------------------------------------------------------- pages

    // What a github.com link to #N really is (an issue or a pull request:
    // both answer under /issues/N), as a row would carry it; a run link
    // needs no question.
    function resolveLink(link, callback, owner) {
        if (link.kind === "run") {
            callback({
                "kind": "run",
                "repo": link.repo,
                "databaseId": link.databaseId,
                "url": Logic.repoUrl(link.repo) + "/actions/runs/" + link.databaseId
            }, "");
            return;
        }
        graphql("inbox", "Resolve", {
            "owner": link.owner,
            "name": link.name,
            "number": link.number
        }, (answer, failure) => {
            const node = answer && answer.data.repository ? answer.data.repository.issueOrPullRequest : null;
            if (node && node.url)
                callback(Logic.itemOf(node), "");
            else
                callback(null, failure || "not found");
        }, {
            "owner": owner
        });
    }

    // A pull request's or an issue's page in one request: { detail, access,
    // images } (Logic.normalizeDetail), or null and why not.
    function loadDetail(item, callback, owner) {
        graphql("detail", item.kind === "pr" ? "PullRequest" : "Issue", Object.assign(repoVars(item.repo), {
            "number": Number(item.number)
        }), (answer, failure) => {
            const page = answer ? Logic.normalizeDetail(item.kind, answer.data.repository) : null;
            callback(page, page ? "" : (failure || "not found"));
        }, {
            "owner": owner,
            "timeout": 45000
        });
    }

    // A run's page as gh views it, or null and why not.
    function loadRun(item, callback, owner) {
        gh(["run", "view", String(item.databaseId), "-R", item.repo, "--json", "databaseId,number,attempt,displayTitle,workflowName,event,headBranch,headSha,status,conclusion,createdAt,startedAt,updatedAt,url,jobs"], (code, out, err) => {
            if (code !== 0) {
                callback(null, Logic.describeFailure(code, err));
                return;
            }
            try {
                callback(JSON.parse(out), "");
            } catch (e) {
                callback(null, "gh answered with something that is not JSON");
            }
        }, {
            "owner": owner
        });
    }

    // Whether the viewer may re-run or cancel a repository's runs, asked
    // once per repository and account: repo -> { canWrite }.
    property var runAccess: ({})

    function loadRunAccess(item, callback, owner) {
        if (runAccess[item.repo]) {
            callback(runAccess[item.repo]);
            return;
        }
        graphql("detail", "Permission", repoVars(item.repo), (answer, failure) => {
            const repository = answer ? answer.data.repository : null;
            if (!repository) {
                callback(null);
                return;
            }
            runAccess = Logic.withKey(runAccess, item.repo, {
                "canWrite": Logic.canWrite(repository.viewerPermission)
            });
            callback(runAccess[item.repo]);
        }, {
            "owner": owner
        });
    }

    // People who can be assigned in a repository, whose login or name match
    // `search`: [{ login, name }], or null when gh failed.
    function loadAssignable(repo, search, callback, owner) {
        graphql("assignees", null, Object.assign(repoVars(repo), {
            "search": String(search || "")
        }), (answer, failure) => {
            const users = answer && answer.data.repository ? answer.data.repository.assignableUsers.nodes || [] : null;
            callback(users ? users.filter(user => !!user).map(user => ({
                        "login": String(user.login),
                        "name": String(user.name || "")
                    })) : null);
        }, {
            "owner": owner
        });
    }

    // ----------------------------------------------------------------- drafts
    //
    // What was typed into a page's comment box, by page, so going back, a
    // window taking the page over, or the popout closing loses nothing. A
    // posted comment clears its page's draft only if the draft is still
    // what was posted.
    property var drafts: ({})

    function saveDraft(url, text, replyTo) {
        if (!url)
            return;
        if (String(text || "").trim() === "" && !replyTo)
            delete drafts[url];
        else
            drafts[url] = {
                "text": String(text || ""),
                "replyTo": replyTo || null
            };
    }

    function draftFor(url) {
        return drafts[url] || null;
    }

    function clearDraft(url, sent) {
        const draft = drafts[url];
        if (draft && draft.text.trim() === sent)
            delete drafts[url];
    }

    // -------------------------------------------------------------- changes

    // url -> the change running against it ("approve", "merge", ...), so a
    // row or a page can show that it is busy and refuse a second click.
    property var busy: ({})

    // A change the viewer asked for (Logic.ACTIONS). It finishes whatever
    // happens to the page meanwhile; what the callback does with the page
    // is the page's business. Answered after gh switched accounts, it only
    // says how it went: what it would hide, refresh, or clear belongs to
    // the other account. A change that must be verified (a merge) is busy
    // until GitHub says where the item stands, and says only what it knows:
    // done, started (a merge queue), or asked for, when GitHub cannot say
    // or the item went another way (closed meanwhile).
    function mutate(item, action, body, callback, extra) {
        const def = Logic.ACTIONS[action];
        if (!def || busy[item.url])
            return false;
        const account = accountGen;
        const name = Logic.itemName(item);
        busy = Logic.withKey(busy, item.url, action);
        const finish = outcome => {
            busy = Logic.withKey(busy, item.url, undefined);
            if (outcome === "unknown")
                ToastService.showInfo(def.unknown + " " + name, "GitHub did not say whether it went through; the page shows where it stands.");
            else
                ToastService.showInfo((extra && extra.done ? extra.done : (outcome === "done" ? def.done : def.started)) + " " + name);
            if (account !== accountGen)
                return;
            if (outcome === "done" && def.leaves)
                hide(item.url, action);
            followUp(item, def);
            changed(item.url);
            if (callback)
                callback(true);
        };
        gh(Logic.mutationArgs(item, action, body, extra), (code, out, err) => {
            if (code !== 0) {
                busy = Logic.withKey(busy, item.url, undefined);
                const same = account === accountGen;
                const answer = Logic.graphqlAnswer(out);
                const scopeMissing = !!def.scope && (answer ? answer.errors.some(error => error.type === "INSUFFICIENT_SCOPES") : String(err).indexOf("'" + def.scope + "'") >= 0);
                if (scopeMissing) {
                    if (same)
                        tokenScopes = (tokenScopes || []).filter(scope => scope !== def.scope);
                    ToastService.showError("GitHub: " + name, "Following a page needs gh's " + def.scope + " scope. Click the bell to add it.");
                } else {
                    ToastService.showError("GitHub: " + name, Logic.failureText(Logic.describeFailure(code, err)));
                }
                if (callback && same)
                    callback(false);
                return;
            }
            // Another account cannot say where the old one's change stands.
            if (!def.verify || account !== accountGen) {
                finish(def.verify ? "unknown" : "done");
                return;
            }
            graphql("inbox", "Resolve", Object.assign(repoVars(item.repo), {
                "number": Number(item.number)
            }), answer => {
                const node = answer && answer.data.repository ? answer.data.repository.issueOrPullRequest : null;
                const state = node && account === accountGen ? String(node.state) : "";
                finish(state === def.verify ? "done" : (state === def.waiting ? "started" : "unknown"));
            }, {
                "account": false
            });
        }, {
            "timeout": 60000,
            "account": false
        });
        return true;
    }

    // What a change moves, asked for again a moment later (search results
    // trail a change by seconds): the lists (in full while someone looks,
    // the bar's counts otherwise) or the runs, the viewer's and those of a
    // repository a panel shows.
    function followUp(item, def) {
        const add = (list, value) => list.indexOf(value) >= 0 ? list : list.concat([value]);
        if (def.runs) {
            soon.runs = add(soon.runs, "");
            if (scopeOf(item.repo).runsAt > 0)
                soon.runs = add(soon.runs, item.repo);
        } else if (def.lists) {
            soon.inbox = true;
            if (scopeOf(item.repo).at > 0)
                soon.repos = add(soon.repos, item.repo);
        } else {
            return;
        }
        soon.restart();
    }

    Timer {
        id: soon
        property bool inbox: false
        property var runs: []
        property var repos: []
        interval: 4000
        onTriggered: {
            if (inbox && data.watched)
                data.refreshInbox({
                    "again": true
                });
            else if (inbox)
                data.refreshBadge();
            for (const scope of runs)
                data.refreshRuns(scope, {
                    "again": true
                });
            for (const repo of repos)
                data.refreshRepo(repo, {
                    "again": true,
                    "runs": false
                });
            inbox = false;
            runs = [];
            repos = [];
        }
    }

    // GitHub marks a large inbox read in the background; look again once
    // it had time to.
    Timer {
        id: notificationsSoon
        interval: 5000
        onTriggered: data.refreshNotifications({
            "again": true
        })
    }
}
