// Helpers for a GitHubData scenario (tests/github_plugin.bats appends the
// test's run(data) after this file).

// A scripted gh (GitHubData.runner): every call waits in `calls` until the
// scenario answers it, in whatever order the scenario likes.
function fakeGh(data) {
    const gh = {
        "calls": []
    };
    data.runner = (args, done) => gh.calls.push({
            "args": args,
            "line": args.join(" "),
            "done": done
        });
    gh.waiting = text => gh.calls.filter(call => !call.answered && (!text || call.line.indexOf(text) >= 0));
    gh.next = text => {
        const found = gh.waiting(text);
        if (found.length === 0)
            throw new Error("no gh call waiting for: " + text + "\nwaiting: " + gh.waiting().map(call => call.line).join("\n"));
        return found[0];
    };
    gh.answer = (call, out, code, err) => {
        call.answered = true;
        call.done(code || 0, typeof out === "string" ? out : JSON.stringify(out), err || "");
    };
    // The next request for an inbox's first page (not a page before a
    // thread), in the scope's path.
    gh.firstPage = path => {
        const found = gh.waiting((path || "notifications") + "?all=true").filter(call => call.line.indexOf("before=") < 0);
        if (found.length === 0)
            throw new Error("no inbox first page waiting\nwaiting: " + gh.waiting().map(call => call.line).join("\n"));
        return found[0];
    };
    // The next call of a GraphQL operation, answered.
    gh.op = (name, out, code, err) => gh.answer(gh.next("operationName=" + name), out, code, err);
    return gh;
}

// A second before 2026-01-01T12:00:00Z for each step of i.
function stamp(i) {
    return new Date(Date.UTC(2026, 0, 1, 12, 0, 0) - i * 1000).toISOString().replace(".000Z", "Z");
}

function thread(id, at) {
    return {
        "id": String(id),
        "unread": true,
        "reason": "mention",
        "updated_at": at,
        "subject": {
            "title": "t" + id,
            "type": "Issue",
            "url": "https://api.github.com/repos/o/r/issues/" + id
        },
        "repository": {
            "full_name": "o/r"
        }
    };
}

// Threads numbered from..to, newest first, a second apart.
function threads(from, to) {
    const out = [];
    for (let i = from; i <= to; i++)
        out.push(thread(i, stamp(i)));
    return out;
}

// `gh api -i` output of the notifications inbox.
function inbox(list) {
    return "HTTP/2.0 200 OK\r\nLast-Modified: Thu, 01 Jan 2026 12:00:00 GMT\r\nX-Poll-Interval: 60\r\n\r\n" + JSON.stringify(list);
}

function issue(i) {
    return {
        "__typename": "Issue",
        "number": i,
        "title": "i" + i,
        "url": "https://github.com/o/r/issues/" + i,
        "state": "OPEN",
        "updatedAt": stamp(i),
        "author": {
            "login": "a"
        },
        "repository": {
            "nameWithOwner": "o/r"
        },
        "comments": {
            "totalCount": 0
        },
        "labels": {
            "nodes": []
        }
    };
}

// A search answer with issues from..to of `count`.
function results(from, to, count, cursor) {
    const nodes = [];
    for (let i = from; i <= to; i++)
        nodes.push(issue(i));
    return {
        "issueCount": count,
        "pageInfo": {
            "hasNextPage": to < count,
            "endCursor": cursor || "c" + to
        },
        "nodes": nodes
    };
}

function viewerAnswer(login, lists) {
    return {
        "data": Object.assign({
            "viewer": {
                "login": login,
                "repositories": {
                    "nodes": []
                }
            }
        }, lists || {})
    };
}

function badge(login, reviews) {
    return viewerAnswer(login, {
        "prReview": {
            "issueCount": reviews || 0
        },
        "issueAssigned": {
            "issueCount": 0
        },
        "prAssignedOnly": {
            "issueCount": 0
        }
    });
}

function ids(list) {
    return list.map(entry => entry.id || entry.number);
}
