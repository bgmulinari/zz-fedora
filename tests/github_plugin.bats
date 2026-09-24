#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

GITHUB_REL="dotfiles/dms/.config/DankMaterialShell/plugins/GitHub"
GITHUB_PATH="~/.config/DankMaterialShell/plugins/GitHub"

setup() {
  setup_test_env
  source_core
}

# Runs JavaScript from stdin against the plugin's logic library
# (GitHubLogic.js) with `L` bound to it, and prints what it returns as JSON.
github_logic() {
  node "$ROOT_DIR/tests/support/github_logic.js" "$ROOT_DIR/$GITHUB_REL/GitHubLogic.js" "$@"
}

# Node runs the logic tests; it is part of every ZZ install (the nodejs base
# unit), so its absence is a broken environment, not a reason to skip.
need_node() {
  if ! command -v node >/dev/null 2>&1; then
    printf 'node is required for the GitHub plugin logic tests\n' >&2
    return 1
  fi
}

# Quickshell runs the data layer's tests; it comes with the desktop, which a
# build or test host may not have.
need_qs() {
  command -v qs >/dev/null 2>&1 || skip "Quickshell (qs) is not installed"
}

# Runs a scenario (stdin: the body of run(data, toasts)) against the
# plugin's data layer (GitHubData) in a headless Quickshell with gh scripted
# (tests/support/github_data), and prints what it returns as JSON.
github_data() {
  local dir="$BATS_TEST_TMPDIR/github-data" runtime="$BATS_TEST_TMPDIR/runtime" log
  mkdir -p "$dir" "$runtime"
  chmod 700 "$runtime"
  cp -r "$ROOT_DIR/tests/support/github_data/." "$dir/"
  cp "$ROOT_DIR/$GITHUB_REL/GitHubData.qml" "$ROOT_DIR/$GITHUB_REL/GitHubLogic.js" "$dir/"
  {
    cat "$dir/harness.js"
    printf 'function run(data, toasts) {\n'
    cat
    printf '\n}\n'
  } >"$dir/scenario.js"
  # The scenario quits the shell itself; a timeout or a crash fails.
  if ! log="$(QT_QPA_PLATFORM=offscreen XDG_RUNTIME_DIR="$runtime" timeout 30 qs -p "$dir" 2>&1)" || ! grep -q 'RESULT ' <<<"$log"; then
    printf '%s\n' "$log" >&2
    return 1
  fi
  sed -n 's/.*RESULT //p' <<<"$log" | head -n 1
}

@test "github selection plans the plugin link, unit, CLI, and default visibility" {
  build_test_plan "dev=github"

  assert_plan_has "$PLAN_DIR/bundles.list" "dev-github"
  assert_plan_has "$PLAN_DIR/config/components.list" "dms-plugin-github"
  assert_plan_has "$PLAN_DIR/files/managed-files.list" "$GITHUB_PATH"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "gh"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "libnotify"
  run default_choice_ids dev
  [ "$status" -eq 0 ]
  assert_contains "$output" "github"

  run dms_plugin_settings_seed_json
  [ "$status" -eq 0 ]
  assert_equal true "$(jq -r '.github.enabled' <<<"$output")"
  run dms_settings_seed_json
  [ "$status" -eq 0 ]
  run jq -e '.barConfigs[0].rightWidgets | index("github") != null' <<<"$output"
  [ "$status" -eq 0 ]
}

@test "github plugin is one daemon shared by every bar, with a widget per bar" {
  local dir="$ROOT_DIR/$GITHUB_REL"

  assert_equal github "$(jq -r '.id' "$dir/plugin.json")"
  assert_equal composite "$(jq -r '.type' "$dir/plugin.json")"
  assert_equal ./GitHubWidget.qml "$(jq -r '.components.widget' "$dir/plugin.json")"
  assert_equal ./GitHubDaemon.qml "$(jq -r '.components.daemon' "$dir/plugin.json")"
  assert_equal gh,notify-send "$(jq -r '.dependencies | join(",")' "$dir/plugin.json")"
  assert_file_contains "$dir/StartupCheck.qml" 'command -v gh'
  # The data, its background polls, and the windows live once, in the
  # daemon; a bar's widget reads them from there.
  run grep -c 'GitHubData {' "$dir/GitHubDaemon.qml" "$dir/GitHubWidget.qml"
  assert_equal "$dir/GitHubDaemon.qml:1
$dir/GitHubWidget.qml:0" "$output"
  assert_file_contains "$dir/GitHubWidget.qml" 'pluginService.pluginDaemonInstances[pluginId]'
}

@test "github plugin reaches GitHub only through the gh CLI" {
  local dir="$ROOT_DIR/$GITHUB_REL"

  # No HTTP client, token, or direct API endpoint: authentication stays
  # with gh, and every process the data layer starts is gh itself (the
  # daemon's only other process is notify-send, which never sees GitHub).
  run grep -rn -i -E 'curl|wget|XMLHttpRequest|api\.github\.com|GH_TOKEN|GITHUB_TOKEN|Authorization:|oauth_token|secret-tool' "$dir" --include='*.qml' --include='*.js'
  [ "$status" -ne 0 ]
  run grep -l 'Process {' "$dir"/*.qml
  assert_equal "$dir/GitHubDaemon.qml
$dir/GitHubData.qml" "$output"
  assert_file_contains "$dir/GitHubData.qml" 'command: ["gh"].concat(args)'
  assert_file_contains "$dir/GitHubDaemon.qml" 'command: ["notify-send", "--app-name=GitHub"'
}

@test "github queries declare exactly the searches the lists ask" {
  need_node
  local dir="$ROOT_DIR/$GITHUB_REL"

  # Every alias an operation fetches is a list (or a count) the library
  # defines, under a variable the operation declares.
  run github_logic "$dir/queries/inbox.graphql" <<'EOF'
const text = require("fs").readFileSync(args[0], "utf8");
const out = {};
for (const [op, scope] of [["Inbox", ""], ["Repository", "o/r"]]) {
  const body = text.slice(text.indexOf("query " + op + "("), text.indexOf("\n}\n", text.indexOf("query " + op + "(")));
  const aliases = [...body.matchAll(/^  (\w+): search\(/gm)].map(m => m[1]).sort();
  const declared = [...body.slice(0, body.indexOf("{")).matchAll(/\$(\w+): String!/g)].map(m => m[1]).sort();
  out[op] = { aliases: aliases.join(","), declared: declared.join(","), library: Object.keys(L.searchVariables(scope)).sort().join(",") };
}
return out;
EOF
  [ "$status" -eq 0 ]
  assert_equal "$(jq -r '.Inbox.library' <<<"$output")" "$(jq -r '.Inbox.aliases' <<<"$output")"
  assert_equal "$(jq -r '.Inbox.library' <<<"$output")" "$(jq -r '.Inbox.declared' <<<"$output")"
  assert_equal "$(jq -r '.Repository.library' <<<"$output")" "$(jq -r '.Repository.aliases' <<<"$output")"
  assert_equal "$(jq -r '.Repository.library' <<<"$output")" "$(jq -r '.Repository.declared' <<<"$output")"

  # Every operation the data layer asks for is in the file it names.
  local call file op
  while IFS= read -r call; do
    file="$(sed -E 's/graphql\("([a-z]+)", "([A-Za-z]+)".*/\1/' <<<"$call")"
    op="$(sed -E 's/graphql\("([a-z]+)", "([A-Za-z]+)".*/\2/' <<<"$call")"
    assert_file_contains "$dir/queries/$file.graphql" "query $op("
  done < <(grep -o 'graphql("[a-z]*", "[A-Za-z]*"' "$dir/GitHubData.qml")
}

@test "github lists: searches, filters, tabs, and what a change hides" {
  need_node

  run github_logic <<'EOF'
return {
  base: L.searchBase("prAssigned"),
  repo: L.searchFor("prMerged@o/r"),
  repoBase: L.searchBase("issueClosed@o/r"),
  viewerTabs: L.tabsFor("").map(t => t.id).join(","),
  repoTabs: L.tabsFor("o/r").map(t => t.id).join(","),
  repoPrs: L.filtersFor("o/r", "prs").map(f => f.key).join(","),
  primary: [L.primaryKey("", "prs"), L.primaryKey("", "issues"), L.primaryKey("o/r", "issues")].join(","),
  approve: ["prReview", "prAssigned", "prMentioned"].filter(k => L.hiddenIn("approve", k)).join(","),
  close: ["prAssigned", "prOpen@o/r", "prClosed@o/r", "issueClosed@o/r"].filter(k => L.hiddenIn("close", k)).join(","),
  reopen: ["issueAssigned", "issueOpen@o/r", "issueClosed@o/r", "prMerged@o/r"].filter(k => L.hiddenIn("reopen", k)).join(","),
  // Every change says what it did, and a run's names its repository.
  undone: Object.keys(L.ACTIONS).filter(a => !L.ACTIONS[a].done || !Array.isArray(L.mutationArgs({ kind: "pr", url: "u", repo: "o/r", number: 1, databaseId: 2 }, a, "b", { commentId: 1, threadId: "t", login: "l", id: "i", state: "S" }))),
  runs: Object.keys(L.ACTIONS).filter(a => L.ACTIONS[a].runs).map(a => L.mutationArgs({ kind: "run", repo: "o/r", databaseId: 2 }, a).slice(-2).join(" "))
};
EOF
  [ "$status" -eq 0 ]
  # A search spans every state: the viewer's lists drop is:open, and a
  # repository's covers its whole kind.
  assert_equal "is:pr archived:false assignee:@me sort:updated-desc" "$(jq -r '.base' <<<"$output")"
  assert_equal "repo:o/r is:pr is:merged sort:updated-desc" "$(jq -r '.repo' <<<"$output")"
  assert_equal "repo:o/r is:issue sort:updated-desc" "$(jq -r '.repoBase' <<<"$output")"
  # GitHub's tab order, and no inbox in a repository.
  assert_equal "inbox,issues,prs,actions" "$(jq -r '.viewerTabs' <<<"$output")"
  assert_equal "issues,prs,actions" "$(jq -r '.repoTabs' <<<"$output")"
  assert_equal "prOpen@o/r,prMerged@o/r,prClosed@o/r" "$(jq -r '.repoPrs' <<<"$output")"
  assert_equal "prReview,issueAssigned,issueOpen@o/r" "$(jq -r '.primary' <<<"$output")"
  # Approving leaves the review requests only; closing leaves the open
  # lists; reopening leaves the closed and merged ones.
  assert_equal "prReview" "$(jq -r '.approve' <<<"$output")"
  assert_equal "prAssigned,prOpen@o/r" "$(jq -r '.close' <<<"$output")"
  assert_equal "issueClosed@o/r,prMerged@o/r" "$(jq -r '.reopen' <<<"$output")"
  assert_equal '[]' "$(jq -c '.undone' <<<"$output")"
  assert_equal '["-R o/r","-R o/r","-R o/r"]' "$(jq -c '.runs' <<<"$output")"
}

@test "github list pages stay coherent across refreshes" {
  need_node

  run github_logic <<'EOF'
const items = n => Array.from({ length: n }, (_, i) => ({ url: "u" + i }));
const page = { items: items(30), cursor: "c", more: true, count: 80 };
const first = { items: items(30), cursor: "old", more: true, count: 80, loading: true, gen: 3 };
const scrolled = { items: items(60), cursor: "c2", more: true, count: 80, loading: false, gen: 4 };
const moved = Object.assign({}, page, { items: [{ url: "new" }].concat(items(29)) });
return {
  scrolled: L.firstPageRecord(scrolled, moved, false, 30),
  reset: L.firstPageRecord(scrolled, moved, true, 30).gen,
  same: L.firstPageRecord(first, page, false, 30).gen,
  changed: L.firstPageRecord(first, moved, false, 30).gen,
  before: L.olderThan([{ updatedAt: "2026-09-01T10:00:00Z" }, { updatedAt: "2026-08-01T10:00:00Z" }])
};
EOF
  [ "$status" -eq 0 ]
  # A list scrolled past its first page is fetched again whole rather than
  # given a first page from a newer answer than its other pages.
  assert_equal null "$(jq -c '.scrolled' <<<"$output")"
  assert_equal 5 "$(jq -r '.reset' <<<"$output")"
  # New items make a new generation, which drops next pages asked before.
  assert_equal 3 "$(jq -r '.same' <<<"$output")"
  assert_equal 4 "$(jq -r '.changed' <<<"$output")"
  # The inbox's next page continues before its oldest thread, a second of
  # overlap included, not at a page number that reads shift.
  assert_equal "2026-08-01T10:00:01Z" "$(jq -r '.before' <<<"$output")"
}

@test "github announces a notification once, and never an old one" {
  need_node

  run github_logic <<'EOF'
const t = (id, at) => ({ id: id, updatedAt: at });
const first = L.announce(null, "me", [t("1", "2026-09-01T10:00:00Z")]);
const later = L.announce(first.state, "me", [t("1", "2026-09-01T10:00:00Z"), t("2", "2026-09-01T11:00:00Z"), t("0", "2026-08-01T10:00:00Z")]);
const again = L.announce(later.state, "me", [t("1", "2026-09-01T12:00:00Z"), t("2", "2026-09-01T11:00:00Z")]);
const other = L.announce(again.state, "you", [t("9", "2026-09-02T10:00:00Z")]);
const back = L.announce(other.state, "me", [t("1", "2026-09-01T12:00:00Z"), t("3", "2026-09-03T10:00:00Z")]);
return {
  first: first.fresh.map(x => x.id),
  later: later.fresh.map(x => x.id),
  again: again.fresh.map(x => x.id),
  other: other.fresh.map(x => x.id),
  back: back.fresh.map(x => x.id),
  since: again.state.me.since,
  accounts: Object.keys(back.state).sort()
};
EOF
  [ "$status" -eq 0 ]
  # The first look records; a new thread is news, a backlog thread moving
  # into the fetched page is not; a thread that changes again is news once;
  # another account starts over.
  assert_equal '[]' "$(jq -c '.first' <<<"$output")"
  assert_equal '["2"]' "$(jq -c '.later' <<<"$output")"
  assert_equal '["1"]' "$(jq -c '.again' <<<"$output")"
  assert_equal '[]' "$(jq -c '.other' <<<"$output")"
  assert_equal "2026-09-01T12:00:00Z" "$(jq -r '.since' <<<"$output")"
  # Each account keeps its own record, so switching back misses nothing
  # that came meanwhile.
  assert_equal '["3"]' "$(jq -c '.back' <<<"$output")"
  assert_equal '["me","you"]' "$(jq -c '.accounts' <<<"$output")"
}

@test "github Actions keeps only the watched repositories' runs" {
  need_node

  run github_logic <<'EOF'
const run = (repo, at, status) => ({ repo: repo, createdAt: at, status: status || "completed", conclusion: "success" });
const current = [run("o/a", "1"), run("o/old", "2", "in_progress"), run("o/b", "3")];
return {
  full: L.mergeRuns(current, [run("o/a", "4")], ["o/a"], ["o/a", "o/b"], 60).map(r => r.repo + r.createdAt),
  active: L.filterRuns([run("o/x", "", "queued"), run("o/x", "", "in_progress"), run("o/x", "", "completed")], "active").length
};
EOF
  [ "$status" -eq 0 ]
  # A repository no longer watched takes its runs (a stuck running one
  # included) along; an unanswered watched one keeps its runs.
  assert_equal '["o/a4","o/b3"]' "$(jq -c '.full' <<<"$output")"
  assert_equal 2 "$(jq -r '.active' <<<"$output")"
}

@test "github passes GitHub strings raw and reads partial GraphQL answers" {
  need_node

  run github_logic <<'EOF'
return {
  args: L.graphqlArgs("/q.graphql", "Page", { owner: "123", name: "null", number: 7, item: true, after: null }),
  subscription: L.mutationArgs({ kind: "issue", url: "u" }, "subscription", "", { id: "I_1", state: "SUBSCRIBED" }).slice(-4),
  merge: L.mutationArgs({ kind: "pr", url: "u" }, "merge", "", { mergeMethod: "SQUASH" }),
  pinned: L.mutationArgs({ kind: "pr", url: "u" }, "merge", "", { mergeMethod: "MERGE", headSha: "abc" }).slice(-2),
  partial: L.graphqlAnswer('{"data":{"viewer":{"login":"me"}},"errors":[{"type":"FORBIDDEN","message":"org"}]}'),
  signedOut: L.describeFailure(4, "")
};
EOF
  [ "$status" -eq 0 ]
  # Strings go as -f (a repository named 123 or null stays a string);
  # numbers and booleans as -F; the query file as -F @file.
  assert_equal '["api","graphql","-F","query=@/q.graphql","-f","operationName=Page","-f","owner=123","-f","name=null","-F","number=7","-F","item=true"]' "$(jq -c '.args' <<<"$output")"
  assert_equal '["-f","id=I_1","-f","state=SUBSCRIBED"]' "$(jq -c '.subscription' <<<"$output")"
  assert_equal '["pr","merge","u","--squash"]' "$(jq -c '.merge' <<<"$output")"
  # A merge insists on the head commit the page showed.
  assert_equal '["--match-head-commit","abc"]' "$(jq -c '.pinned' <<<"$output")"
  # gh exits 1 over an error in part of an answer; the data still counts.
  assert_equal me "$(jq -r '.partial.data.viewer.login' <<<"$output")"
  assert_equal FORBIDDEN "$(jq -r '.partial.errors[0].type' <<<"$output")"
  assert_equal signedOut "$(jq -r '.signedOut' <<<"$output")"
}

@test "github links open in the popout, as searches, or in the browser when safe" {
  need_node

  run github_logic <<'EOF'
return {
  pr: L.parseLink("https://github.com/o/r/pull/12#issuecomment-1"),
  tabs: ["https://github.com/o/r/pull/12/files", "https://github.com/o/r/pull/12/checks"].map(u => L.parseLink(u)),
  run: L.parseLink("https://github.com/o/r/actions/runs/9/job/1").databaseId,
  label: L.parseSearchLink("https://github.com/o/r/labels/good%20first%20issue", "prs"),
  query: L.parseSearchLink("https://github.com/o/r/issues?q=state%3Aopen+label%3Abug+author%3Ame", "prs"),
  page: L.parseSearchLink("https://github.com/o/r/issues/12"),
  external: ["https://example.com/x", "mailto:a@b.c", "file:///home/u/x.desktop", "steam://run/1", "javascript:alert(1)"].map(u => L.externalUrl(u) !== ""),
  // A stray percent sign in a body's link decodes to itself.
  percent: L.parseSearchLink("https://github.com/o/r/issues?q=100%+done").terms,
  urls: [L.tabUrl("", "prs"), L.tabUrl("o/r", "actions"), L.branchUrl("o/r", "a/b c"), L.reviewerUrl("o/r", { slug: "core" }), L.labelUrl("o/r", "good first")]
};
EOF
  [ "$status" -eq 0 ]
  # A link to a place in a page says where, which only the browser shows.
  assert_equal '{"kind":"pr","owner":"o","name":"r","repo":"o/r","number":12,"anchor":"issuecomment-1"}' "$(jq -c '.pr' <<<"$output")"
  assert_equal '100% done' "$(jq -r '.percent' <<<"$output")"
  assert_equal '["https://github.com/pulls","https://github.com/o/r/actions","https://github.com/o/r/tree/a/b%20c","https://github.com/orgs/o/teams/core","https://github.com/o/r/labels/good%20first"]' "$(jq -c '.urls' <<<"$output")"
  # A pull request's own tabs are not its conversation: the browser shows
  # them.
  assert_equal '[null,null]' "$(jq -c '.tabs' <<<"$output")"
  assert_equal 9 "$(jq -r '.run' <<<"$output")"
  # A label or an issues page with a q= is a search of that repository,
  # every state.
  assert_equal '{"repo":"o/r","tab":"prs","terms":"label:\"good first issue\""}' "$(jq -c '.label' <<<"$output")"
  assert_equal '{"repo":"o/r","tab":"issues","terms":"label:bug author:me"}' "$(jq -c '.query' <<<"$output")"
  assert_equal null "$(jq -c '.page' <<<"$output")"
  # Only web and mail links leave for another app.
  assert_equal '[true,true,false,false,false]' "$(jq -c '.external' <<<"$output")"
}

@test "github pages come from one answer and keep every review thread" {
  need_node

  run github_logic <<'EOF'
const who = login => ({ author: { login: login } });
const repository = {
  nameWithOwner: "o/r", viewerPermission: "WRITE", viewerDefaultMergeMethod: "SQUASH",
  pullRequest: Object.assign(who("ann"), {
    id: "PR_1", number: 5, title: "T", url: "https://github.com/o/r/pull/5", state: "OPEN", isDraft: false,
    body: "![shot](https://github.com/user-attachments/assets/a)", bodyHTML: '<img src="https://signed/a" data-canonical-src="x">',
    mergeable: "MERGEABLE", mergeStateStatus: "BLOCKED", viewerCanClose: true, viewerSubscription: "SUBSCRIBED", viewerCanSubscribe: true,
    labels: { nodes: [{ name: "bug", color: "d73a4a" }] },
    comments: { totalCount: 130, nodes: [Object.assign(who("bob"), { body: "hi", createdAt: "2026-01-01T10:00:00Z", url: "c1" })] },
    commits: { nodes: [{ commit: { statusCheckRollup: { contexts: { totalCount: 2, nodes: [
      { __typename: "CheckRun", name: "test", status: "COMPLETED", conclusion: "FAILURE", detailsUrl: "d", checkSuite: { workflowRun: { workflow: { name: "CI" } } } },
      { __typename: "StatusContext", context: "deploy", state: "SUCCESS", description: "ok", targetUrl: "t" }
    ] } } } }] },
    reviews: { totalCount: 1, nodes: [Object.assign(who("cat"), { databaseId: 1, state: "APPROVED", body: "", submittedAt: "2026-01-01T11:00:00Z", url: "r1" })] },
    reviewThreads: { totalCount: 2, nodes: [
      { id: "T1", path: "a.js", comments: { totalCount: 2, nodes: [Object.assign(who("cat"), { databaseId: 10, body: "x", createdAt: "2026-01-01T11:00:00Z", url: "t1", pullRequestReview: { databaseId: 1 } }), null] } },
      { id: "T2", path: "b.js", comments: { totalCount: 1, nodes: [Object.assign(who("dan"), { databaseId: 20, body: "y", createdAt: "2026-01-01T09:00:00Z", url: "t2", pullRequestReview: { databaseId: 99 } })] } }
    ] }
  })
};
const page = L.normalizeDetail("pr", repository);
const timeline = L.buildTimeline(page.detail);
return {
  checks: page.detail.checks.map(c => c.name + ":" + c.outcome + ":" + c.detail),
  report: L.checksReport(page.detail.checks, page.detail.checksState, page.detail.checksTotal).headline.text,
  cancelled: L.checksReport([{ outcome: "cancelled" }, { outcome: "success" }], "FAILURE", 2).headline,
  unseen: L.checksReport([{ outcome: "success" }], "FAILURE", 120),
  replies: page.detail.threads.map(t => t.comments.nodes.length),
  merge: [L.mergeStatus(page.detail).kind, L.mergeStatus(page.detail).glyph.icon, L.mergeStatus(page.detail).glyph.tone].join(":"),
  totals: [page.detail.commentsTotal, page.detail.threadsTotal],
  access: [page.access.canWrite, page.access.canClose, page.access.mergeMethod, page.access.subscription.on],
  images: page.images,
  timeline: timeline.map(e => e.type + ":" + e.login + ":" + e.threads.map(t => t.id).join("+"))
};
EOF
  [ "$status" -eq 0 ]
  assert_equal '["test:failure:CI","deploy:success:ok"]' "$(jq -c '.checks' <<<"$output")"
  assert_equal "1 check failing" "$(jq -r '.report' <<<"$output")"
  # Cancelled checks are no pass, and a failure past the fetched checks
  # still reads as one, from GitHub's verdict over all of them.
  assert_equal '{"text":"Some checks were not successful","outcome":"cancelled"}' "$(jq -c '.cancelled' <<<"$output")"
  assert_equal '{"headline":{"text":"Some checks failed","outcome":"failure"},"summary":"1 passed · 119 more on GitHub"}' "$(jq -c '.unseen' <<<"$output")"
  # A comment GitHub could not return leaves its thread, not a hole in it.
  assert_equal '[1,1]' "$(jq -c '.replies' <<<"$output")"
  assert_equal blocked:block:warning "$(jq -r '.merge' <<<"$output")"
  # The page knows how much of a long conversation it holds.
  assert_equal '[130,2]' "$(jq -c '.totals' <<<"$output")"
  assert_equal '[true,true,"SQUASH",true]' "$(jq -c '.access' <<<"$output")"
  assert_equal '{"https://github.com/user-attachments/assets/a":"https://signed/a"}' "$(jq -c '.images' <<<"$output")"
  # A thread whose review was not fetched stands on its own, in time
  # order, instead of going missing.
  assert_equal '["review:dan:T2","comment:bob:","review:cat:T1"]' "$(jq -c '.timeline' <<<"$output")"
}

@test "github Markdown keeps code as written and cuts long bodies with a way back" {
  need_node

  run github_logic <<'EOF'
const style = { link: "#00f", codeFont: "mono", codeSize: 12, codeBackground: "#000", codeText: "#fff", border: "#888" };
const text = "Intro <!-- hidden --> <div>kept text</div>\n\n```html\n<div>hello</div>\n<!-- keep -->\n```\n\nUse `<b>bold</b>` here.";
const blocks = L.parseMarkdown(text, "o/r", style);
const long = L.parseMarkdown(Array.from({ length: 20 }, (_, i) => "Paragraph " + i + " " + "x".repeat(500)).join("\n\n"), "", style);
return {
  types: blocks.map(b => b.type),
  intro: blocks[0].html,
  code: blocks[1].text,
  lines: blocks[1].lines,
  inline: blocks[2].html.indexOf("&lt;b&gt;bold&lt;/b&gt;") >= 0,
  refs: L.parseMarkdown("See #12 and @ann", "o/r", style)[0].html.match(/href="[^"]+"/g),
  fitting: L.blocksWithin(long, 6000),
  all: long.length
};
EOF
  [ "$status" -eq 0 ]
  assert_equal '["paragraph","code","paragraph"]' "$(jq -c '.types' <<<"$output")"
  # Layout markup and comments outside code drop for their text...
  assert_equal "Intro  kept text" "$(jq -r '.intro' <<<"$output")"
  # ...and code keeps every character.
  assert_equal '<div>hello</div>
<!-- keep -->' "$(jq -r '.code' <<<"$output")"
  assert_equal 2 "$(jq -r '.lines' <<<"$output")"
  assert_equal true "$(jq -r '.inline' <<<"$output")"
  assert_equal '["href=\"https://github.com/o/r/issues/12\"","href=\"https://github.com/ann\""]' "$(jq -c '.refs' <<<"$output")"
  # A long body shows the blocks that fit, and the view offers the rest.
  assert_equal 11 "$(jq -r '.fitting' <<<"$output")"
  assert_equal 20 "$(jq -r '.all' <<<"$output")"
  assert_file_contains "$ROOT_DIR/$GITHUB_REL/GitHubMarkdown.qml" 'text: "Show the whole post"'
}

@test "github splits a job log into its steps where each one begins" {
  need_node

  run github_logic <<'EOF'
const at = s => new Date(Date.UTC(2026, 0, 1, 12, 0, s)).toISOString().replace(".000Z", "Z");
const line = (s, text) => at(s).replace("Z", ".1234567Z") + " " + text;
const steps = [
  { number: 1, name: "Set up job", conclusion: "success", startedAt: at(0) },
  { number: 2, name: "Initialize containers", conclusion: "success", startedAt: at(1) },
  { number: 3, name: "Skipped check", conclusion: "skipped", startedAt: at(2) },
  { number: 4, name: "Run ./composite", conclusion: "success", startedAt: at(2) },
  // Starts in the same second as the composite's inner group.
  { number: 5, name: "Run npm test", conclusion: "failure", startedAt: at(3) },
  // A name of its own that happens to start with Run.
  { number: 6, name: "Run the linter", conclusion: "success", startedAt: at(5) },
  { number: 7, name: "Post Run ./composite", conclusion: "success", startedAt: at(6) },
  { number: 8, name: "Stop containers", conclusion: "success", startedAt: at(6) },
  { number: 9, name: "Complete job", conclusion: "success", startedAt: at(7) }
];
const log = [
  "﻿" + line(0, "Current runner version: '2.337.0'"),
  line(1, "##[group]Checking docker version"),
  line(1, "docker 27"),
  line(2, "##[group]Run ./composite"),
  line(3, "##[group]Run inner step"),
  line(3, "\u001b[32minner output\u001b[0m"),
  line(3, "##[group]Run npm test"),
  line(4, "##[error]Process completed with exit code 1."),
  line(5, "##[group]Run eslint ."),
  line(6, "Post job cleanup."),
  line(6, "Stop and remove container: abc"),
  line(7, "Cleaning up orphan processes")
].join("\n");
return L.splitJobLog(log, steps);
EOF
  [ "$status" -eq 0 ]
  local steps="$(jq -c '.steps' <<<"$output")"
  assert_equal '["##[group]Checking docker version","docker 27"]' "$(jq -c '.["2"]' <<<"$steps")"
  assert_equal null "$(jq -c '.["3"]' <<<"$steps")"
  # A composite action's inner group stays with its step even when the
  # next step starts in the same second: a step named after its command
  # begins only at that command's line. Colors are stripped.
  assert_equal '["##[group]Run ./composite","##[group]Run inner step","inner output"]' "$(jq -c '.["4"]' <<<"$steps")"
  assert_equal '["##[group]Run npm test","##[error]Process completed with exit code 1."]' "$(jq -c '.["5"]' <<<"$steps")"
  # A step with a name of its own begins at the next Run group, even one
  # that starts with Run.
  assert_equal '["##[group]Run eslint ."]' "$(jq -c '.["6"]' <<<"$steps")"
  assert_equal '["Post job cleanup."]' "$(jq -c '.["7"]' <<<"$steps")"
  assert_equal '["Stop and remove container: abc"]' "$(jq -c '.["8"]' <<<"$steps")"
  assert_equal '["Cleaning up orphan processes"]' "$(jq -c '.["9"]' <<<"$steps")"
  # The whole log stays beside the split.
  assert_equal 12 "$(jq -r '.all | length' <<<"$output")"
}

@test "github states read as github.com writes them" {
  need_node

  run github_logic <<'EOF'
return [
  L.stateLabel("issue", "CLOSED", "NOT_PLANNED", false, ""),
  L.stateLabel("issue", "CLOSED", "DUPLICATE", false, ""),
  L.stateLabel("pr", "CLOSED", "", false, ""),
  L.stateLabel("pr", "OPEN", "", true, ""),
  L.stateLabel("run", "", "", false, L.outcome("completed", "startup_failure")),
  L.when(new Date(Date.now() - 5 * 60000).toISOString()),
  L.ago("2020-03-04T12:00:00Z", Date.parse("2026-01-01T00:00:00Z")),
  [{ kind: "pr", state: "MERGED" }, { kind: "pr", state: "OPEN", isDraft: true }, { kind: "issue", state: "CLOSED", stateReason: "NOT_PLANNED" }, { kind: "issue", state: "CLOSED" }, { kind: "run", status: "in_progress" }].map(i => L.itemGlyph(i).icon + ":" + L.itemGlyph(i).tone).join(" ")
];
EOF
  [ "$status" -eq 0 ]
  assert_equal '["Closed as not planned","Closed as duplicate","Closed","Draft","Failed","5m ago","Mar 4, 2020","merge:accent edit_note:muted block:muted check_circle:accent progress_activity:warning"]' "$(jq -c . <<<"$output")"
}

@test "github drops the old account's answers and keeps asking after a switch" {
  need_qs

  run github_data <<'EOF'
const gh = fakeGh(data);
const atLogin = [];
data.loginChanged.connect(() => atLogin.push(data.notificationsReady));
data.refreshBadge();
gh.op("Badge", badge("me", 2));
data.refreshNotifications({ "conditional": true });
gh.answer(gh.next("notifications?"), inbox(threads(1, 2)));
// A poll and a page are on their way when gh answers for another account.
data.refreshNotifications();
data.refreshInbox();
data.refreshBadge();
gh.op("Badge", badge("you"));
const switched = { login: data.login, threads: data.notifications.length, count: data.total("prReview") };
// The old answers arrive late and change nothing.
gh.answer(gh.next("notifications?"), inbox(threads(7, 8)));
gh.op("Inbox", viewerAnswer("me"));
const late = { login: data.login, threads: data.notifications.length };
// The new account's own inbox was asked for, and polling goes on.
gh.answer(gh.next("notifications?"), inbox(threads(5, 5)));
const mine = ids(data.notifications);
data.refreshNotifications({ "conditional": true });
return {
  atLogin: atLogin,
  switched: switched,
  late: late,
  mine: mine,
  polling: gh.waiting("notifications?").length,
  loading: data.loadingNotifications
};
EOF
  [ "$status" -eq 0 ]
  # The old account's threads are gone before the new login shows, so the
  # desktop notifications never take them as the new account's first look.
  assert_equal '[false,false]' "$(jq -c '.atLogin' <<<"$output")"
  assert_equal '{"login":"you","threads":0,"count":0}' "$(jq -c '.switched' <<<"$output")"
  assert_equal '{"login":"you","threads":0}' "$(jq -c '.late' <<<"$output")"
  assert_equal '["5"]' "$(jq -c '.mine' <<<"$output")"
  assert_equal 1 "$(jq -r '.polling' <<<"$output")"
  assert_equal true "$(jq -r '.loading' <<<"$output")"
}

@test "github waits for the login and the inbox before comparing notifications" {
  need_qs

  run github_data <<'EOF'
const gh = fakeGh(data);
const ready = [];
data.refreshNotifications({ "conditional": true });
data.refreshBadge();
gh.op("Badge", badge("me"));
ready.push(data.notificationsReady);
gh.answer(gh.next("notifications?"), inbox(threads(1, 3)));
ready.push(data.notificationsReady);
return ready;
EOF
  [ "$status" -eq 0 ]
  # The login alone is no look at the inbox.
  assert_equal '[false,true]' "$(jq -c . <<<"$output")"
}

@test "github refreshes a scrolled list whole while no next page can slip in" {
  need_qs

  run github_data <<'EOF'
const gh = fakeGh(data);
const key = "issueAssigned";
data.refreshInbox();
gh.op("Inbox", viewerAnswer("me", { "issueAssigned": results(1, 30, 150) }));
for (const to of [60, 90, 120]) {
  data.loadMore(key);
  gh.op("Page", { "data": { "search": results(to - 29, to, 150) } });
}
// A new issue tops the list: the 120 loaded come again as one pass.
data.refreshInbox();
gh.op("Inbox", viewerAnswer("me", { "issueAssigned": results(0, 29, 151) }));
const during = data.listOf(key).loading;
data.loadMore(key);
const asked = gh.waiting("operationName=Page").map(call => call.line.match(/first=\d+/)[0]);
gh.op("Page", { "data": { "search": results(0, 99, 151) } });
const next = gh.next("operationName=Page").line;
gh.op("Page", { "data": { "search": results(100, 119, 151) } });
const list = data.listOf(key);
return {
  during: during,
  asked: asked,
  next: [/first=20/.test(next), /after=c99/.test(next)],
  items: [list.items.length, list.items[0].number, list.items[119].number],
  cursor: list.cursor,
  loading: list.loading
};
EOF
  [ "$status" -eq 0 ]
  assert_equal true "$(jq -r '.during' <<<"$output")"
  # One request at a time, 100 at most, and no page from the old cursor.
  assert_equal '["first=100"]' "$(jq -c '.asked' <<<"$output")"
  assert_equal '[true,true]' "$(jq -c '.next' <<<"$output")"
  assert_equal '[120,0,119]' "$(jq -c '.items' <<<"$output")"
  assert_equal c119 "$(jq -r '.cursor' <<<"$output")"
  assert_equal false "$(jq -r '.loading' <<<"$output")"
}

@test "github keeps the loaded inbox without gaps as threads arrive" {
  need_qs

  run github_data <<'EOF'
const gh = fakeGh(data);
data.refreshNotifications();
gh.answer(gh.next("notifications?"), inbox(threads(1, 50)));
data.loadMoreNotifications();
gh.answer(gh.next("before="), JSON.stringify(threads(51, 100)));
// A new thread pushes thread 50 off the first page.
data.refreshNotifications();
gh.answer(gh.next("notifications?"), inbox(threads(0, 49)));
gh.answer(gh.next("before="), JSON.stringify(threads(49, 98)));
const all = ids(data.allNotifications);
// More than a page of threads in one second: the same page comes back,
// and the next page of that look goes on past it.
const tied = [];
for (let i = 101; i <= 150; i++)
  tied.push(thread(i, stamp(100)));
data.lastPageFull = true;
data.loadMoreNotifications();
gh.answer(gh.next("before="), JSON.stringify(tied));
data.loadMoreNotifications();
gh.answer(gh.next("before="), JSON.stringify(tied));
const retry = gh.next("before=").line;
gh.answer(gh.next("page=2"), JSON.stringify(threads(151, 160)));
return {
  count: all.length,
  gap: ["49", "50", "51"].filter(id => all.indexOf(id) < 0),
  retry: /&page=2/.test(retry),
  after: data.allNotifications.length
};
EOF
  [ "$status" -eq 0 ]
  assert_equal 99 "$(jq -r '.count' <<<"$output")"
  assert_equal '[]' "$(jq -c '.gap' <<<"$output")"
  assert_equal true "$(jq -r '.retry' <<<"$output")"
  assert_equal 159 "$(jq -r '.after' <<<"$output")"
}

@test "github freshens what comes on screen and notices gh signing back in" {
  need_qs

  run github_data <<'EOF'
const gh = fakeGh(data);
// A window opened straight from the menu, before any list was fetched.
data.setWatching(data, true);
const onScreen = [gh.waiting("operationName=Inbox").length, gh.waiting("notifications?").length];
gh.op("Inbox", viewerAnswer("me"));
gh.answer(gh.next("notifications?"), "", 4, "To get started with GitHub CLI, please run:  gh auth login");
const out = data.authState;
data.refreshNotifications();
gh.answer(gh.next("notifications?"), inbox([]));
gh.op("Badge", badge("me"));
return { onScreen: onScreen, out: out, back: data.authState };
EOF
  [ "$status" -eq 0 ]
  assert_equal '[1,1]' "$(jq -c '.onScreen' <<<"$output")"
  assert_equal signedOut "$(jq -r '.out' <<<"$output")"
  assert_equal ok "$(jq -r '.back' <<<"$output")"
}

@test "github counts an item a change took out only until GitHub's count moves" {
  need_qs

  run github_data <<'EOF'
const gh = fakeGh(data);
data.refreshInbox();
gh.op("Inbox", viewerAnswer("me", { "prReview": results(1, 3, 3) }));
data.mutate(data.listOf("prReview").items[0], "approve", "", null);
gh.answer(gh.next("--approve"), "");
const hidden = [data.total("prReview"), data.visibleItems("prReview").length];
// GitHub's count catches up before its search results do.
data.refreshBadge();
gh.op("Badge", badge("me", 2));
return { hidden: hidden, caughtUp: data.total("prReview") };
EOF
  [ "$status" -eq 0 ]
  assert_equal '[2,2]' "$(jq -c '.hidden' <<<"$output")"
  assert_equal 2 "$(jq -r '.caughtUp' <<<"$output")"
}

@test "github applies a change answered after a switch to nobody's account" {
  need_qs

  run github_data <<'EOF'
const gh = fakeGh(data);
data.refreshInbox();
gh.op("Inbox", viewerAnswer("me", { "prReview": results(1, 3, 3) }));
const answers = [];
data.mutate(data.listOf("prReview").items[0], "approve", "", ok => answers.push(ok));
data.refreshBadge();
gh.op("Badge", badge("you", 3));
gh.op("Inbox", viewerAnswer("you", { "prReview": results(1, 3, 3) }));
// The old account's approval comes back after the switch.
gh.answer(gh.next("--approve"), "");
return {
  shown: data.visibleItems("prReview").length,
  total: data.total("prReview"),
  answers: answers,
  busy: Object.keys(data.busy).length
};
EOF
  [ "$status" -eq 0 ]
  # Nothing of the new account's is hidden, and the page that asked is not
  # told (it would clear a draft); the change is no longer busy either way.
  assert_equal '{"shown":3,"total":3,"answers":[],"busy":0}' "$(jq -c . <<<"$output")"
}

@test "github drops later inbox pages that threads read elsewhere left behind" {
  need_qs

  run github_data <<'EOF'
const gh = fakeGh(data);
const load = () => {
  data.refreshNotifications();
  gh.answer(gh.next("notifications?"), inbox(threads(1, 50)));
  data.loadMoreNotifications();
  gh.answer(gh.next("before="), JSON.stringify(threads(51, 100)));
};
load();
// 41-100 were read on github.com: the first page is short, so it is all.
data.refreshNotifications();
gh.answer(gh.next("notifications?"), inbox(threads(1, 40)));
const short = [data.allNotifications.length, data.moreNotifications, gh.waiting("before=").length];
// The first page stays full, but the pages after it thinned out.
data.refreshNotifications();
gh.answer(gh.next("notifications?"), inbox(threads(1, 50)));
data.loadMoreNotifications();
gh.answer(gh.next("before="), JSON.stringify(threads(51, 100)));
data.refreshNotifications();
gh.answer(gh.next("notifications?"), inbox(threads(1, 50)));
const during = data.allNotifications.length;
gh.answer(gh.next("before="), JSON.stringify(threads(51, 60)));
return { short: short, during: during, after: data.allNotifications.length, more: data.moreNotifications };
EOF
  [ "$status" -eq 0 ]
  assert_equal '[40,false,0]' "$(jq -c '.short' <<<"$output")"
  # The old pages stay on screen until the new ones came.
  assert_equal 100 "$(jq -r '.during' <<<"$output")"
  assert_equal 60 "$(jq -r '.after' <<<"$output")"
  assert_equal false "$(jq -r '.more' <<<"$output")"
}

@test "github keeps looking for new runs while one runs, and asks again after a change" {
  need_qs

  run github_data <<'EOF'
const gh = fakeGh(data);
const run = (id, status) => ({ "databaseId": id, "status": status, "conclusion": "", "createdAt": stamp(id) });
data.settings = { "repositories": ["o/a", "o/b"] };
data.refreshBadge();
gh.op("Badge", badge("me"));
data.refreshRuns("");
gh.answer(gh.next("-R o/a"), [run(1, "in_progress")]);
gh.answer(gh.next("-R o/b"), []);
// The quick poll asks only the repository with a run going, and leaves
// the time of the last look at every repository alone.
data.patchScope("", { "runsFullAt": 1 });
data.refreshRuns("", { "onlyActive": true });
const asked = gh.waiting("run list").map(call => call.line.match(/-R (\S+)/)[1]);
gh.answer(gh.next("-R o/a"), [run(1, "in_progress")]);
const times = [data.scopeOf("").runsFullAt, data.scopeOf("").runsAt > 1];
// A refresh asked while one is on its way after a change comes after it;
// a background poll that finds one on its way just skips.
data.refreshInbox();
data.refreshInbox();
data.refreshInbox({ "again": true });
gh.op("Inbox", viewerAnswer("me"));
return { asked: asked, times: times, again: gh.waiting("operationName=Inbox").length };
EOF
  [ "$status" -eq 0 ]
  assert_equal '["o/a"]' "$(jq -c '.asked' <<<"$output")"
  assert_equal '[1,true]' "$(jq -c '.times' <<<"$output")"
  assert_equal 1 "$(jq -r '.again' <<<"$output")"
}

@test "github reads job logs with a gh from before --allow-escape-sequences" {
  need_qs

  run github_data <<'EOF'
const gh = fakeGh(data);
let log = null;
data.loadJobLog("o/r", { "databaseId": 7, "steps": [] }, answer => log = answer);
gh.answer(gh.next("--allow-escape-sequences"), "", 1, "unknown flag: --allow-escape-sequences\n\nUsage:  gh api <endpoint> [flags]");
const plain = gh.next("jobs/7/logs").line;
gh.answer(gh.next("jobs/7/logs"), "2026-01-01T12:00:00.1234567Z hello");
return { plain: plain, all: log ? log.all : null };
EOF
  [ "$status" -eq 0 ]
  assert_equal '{"plain":"api repos/o/r/actions/jobs/7/logs","all":["hello"]}' "$(jq -c . <<<"$output")"
}

@test "github drops a next inbox page that a refresh overtook, and asks again" {
  need_qs

  run github_data <<'EOF'
const gh = fakeGh(data);
data.refreshNotifications();
gh.answer(gh.next("-i notifications"), inbox(threads(1, 50)));
// The next page is on its way when a refresh finds 40 unread in all.
data.loadMoreNotifications();
const old = gh.next("before=");
data.refreshNotifications();
gh.answer(gh.next("-i notifications"), inbox(threads(1, 40)));
gh.answer(old, JSON.stringify(threads(51, 100)));
const short = [data.allNotifications.length, gh.waiting("before=").length];
// With a full new first page, the page is asked for again against it.
data.refreshNotifications();
gh.answer(gh.next("-i notifications"), inbox(threads(1, 50)));
data.loadMoreNotifications();
const stale = gh.next("before=");
data.refreshNotifications();
gh.answer(gh.next("-i notifications"), inbox(threads(0, 49)));
gh.answer(stale, JSON.stringify(threads(51, 100)));
const fresh = gh.next("before=");
gh.answer(fresh, JSON.stringify(threads(49, 98)));
return { short: short, asked: /before=2026-01-01T11%3A59%3A12Z/.test(fresh.line), all: data.allNotifications.length };
EOF
  [ "$status" -eq 0 ]
  assert_equal '{"short":[40,0],"asked":true,"all":99}' "$(jq -c . <<<"$output")"
}

@test "github says Merged only once GitHub has merged, and only what it knows" {
  need_qs

  run github_data <<'EOF'
const gh = fakeGh(data);
data.refreshInbox();
gh.op("Inbox", viewerAnswer("me", { "prReview": results(1, 5, 5) }));
const state = s => ({ "data": { "repository": { "issueOrPullRequest": Object.assign(issue(1), { "state": s }) } } });
const merge = item => {
  data.mutate(item, "merge", "", null, { "mergeMethod": "MERGE" });
  gh.answer(gh.next("pr merge"), "");
  return !!data.busy[item.url];
};
const items = data.listOf("prReview").items;
const busy = merge(items[0]);
gh.op("Resolve", state("OPEN"));
const queued = data.visibleItems("prReview").length;
merge(items[1]);
gh.op("Resolve", state("MERGED"));
const merged = data.visibleItems("prReview").length;
// GitHub cannot say.
merge(items[2]);
gh.op("Resolve", "", 1, "HTTP 502");
// Someone closed it before the check came back.
merge(items[4]);
gh.op("Resolve", state("CLOSED"));
// gh switches accounts while the merge is being checked.
merge(items[3]);
data.refreshBadge();
gh.op("Badge", badge("you"));
gh.op("Resolve", state("MERGED"));
return {
  busy: busy,
  queued: queued,
  merged: merged,
  idle: Object.keys(data.busy).length,
  again: data.mutate(items[3], "merge", "", null, { "mergeMethod": "MERGE" }),
  said: toasts.map(toast => toast[1].split(" ").slice(0, 3).join(" "))
};
EOF
  [ "$status" -eq 0 ]
  # Queued, the pull request stays in the open lists; merged, it leaves.
  assert_equal '[true,5,4]' "$(jq -c '[.busy, .queued, .merged]' <<<"$output")"
  # Nothing stays busy, whatever happened to the check, and each toast
  # says only what GitHub confirmed.
  assert_equal '[0,true]' "$(jq -c '[.idle, .again]' <<<"$output")"
  assert_equal '["Queued to merge","Merged o/r#2","Asked to merge","Asked to merge","Asked to merge"]' "$(jq -c '.said' <<<"$output")"
}

@test "github keeps every repository a panel shows when it drops old ones" {
  need_qs

  run github_data <<'EOF'
const gh = fakeGh(data);
const shown = Qt.createQmlObject('import QtQuick; QtObject { property string scope: "o/r0" }', data);
data.setWatching(shown, true);
for (let i = 0; i <= 7; i++) {
  data.refreshRepo("o/r" + i);
  gh.op("Repository", { "data": { "issueOpen": results(1, 2, 2) } });
}
return { kept: data.repoOrder, shown: data.listOf("issueOpen@o/r0").items.length, dropped: data.listOf("issueOpen@o/r1").items.length };
EOF
  [ "$status" -eq 0 ]
  assert_equal '["o/r7","o/r6","o/r5","o/r4","o/r3","o/r0"]' "$(jq -c '.kept' <<<"$output")"
  assert_equal 2 "$(jq -r '.shown' <<<"$output")"
  assert_equal 0 "$(jq -r '.dropped' <<<"$output")"
}

@test "github polls within GitHub's limits" {
  local dir="$ROOT_DIR/$GITHUB_REL"

  # Background notification polls are conditional (a 304 is free) at
  # GitHub's X-Poll-Interval, never faster than a minute. With nothing on
  # screen the lists poll only the bar's counts.
  assert_file_contains "$dir/GitHubData.qml" 'args.push("-H", "If-Modified-Since: " + notificationsModified);'
  assert_file_contains "$dir/GitHubDaemon.qml" 'interval: Math.max(60, githubData.notificationPollSeconds) * 1000'
  assert_file_contains "$dir/GitHubDaemon.qml" 'readonly property int refreshSeconds: Math.max(60, Number(pluginData.refreshIntervalSec || 300))'
  assert_file_contains "$dir/GitHubDaemon.qml" 'githubData.refreshBadge();'
  assert_file_contains "$dir/Settings.qml" 'minimum: 60'
  [[ -f "$dir/notification-icon.svg" ]]
}

@test "github windows and sizes are the daemon's, and pages load images only from GitHub" {
  local dir="$ROOT_DIR/$GITHUB_REL"

  # Every pop-out is a DMS window of its own, which the seeded rules open
  # floating; sizes and scope are plugin state, not settings.
  assert_file_contains "$dir/GitHubDaemon.qml" 'DankFloatingWindow {'
  assert_file_contains "$ROOT_DIR/templates/niri/dms-windowrules.kdl" 'match app-id="^com.danklinux.dms$"'
  assert_file_contains "$dir/GitHubDaemon.qml" 'pluginService.savePluginState(pluginId, key, value)'
  # A picture's source is only ever a signed URL from the page's answer or
  # a public avatar.
  assert_file_contains "$dir/GitHubMarkdown.qml" 'readonly property string signed: md.images[block.url] || ""'
  run grep -c 'Image {' "$dir/GitHubMarkdown.qml" "$dir/GitHubPost.qml"
  assert_equal "$dir/GitHubMarkdown.qml:1
$dir/GitHubPost.qml:1" "$output"
  assert_file_contains "$dir/GitHubPost.qml" 'source: avatar.login !== "" && avatar.login !== "ghost" ? "https://avatars.githubusercontent.com/"'
}
