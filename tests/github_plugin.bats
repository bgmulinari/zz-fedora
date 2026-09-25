#!/usr/bin/env bats
# zz-test-tags: smoke

load "helpers/common"

GITHUB_REL="dotfiles/dms/.config/DankMaterialShell/plugins/GitHub"
GITHUB_PATH="~/.config/DankMaterialShell/plugins/GitHub"

setup() {
  setup_test_env
  source_core
}

# Runs JavaScript from stdin against the plugin's logic libraries
# (GitHubLogic.js and GitHubMarkdown.js) with `L` bound to their names, and
# prints what it returns as JSON.
github_logic() {
  node "$ROOT_DIR/tests/support/github_logic.js" "$ROOT_DIR/$GITHUB_REL/GitHubLogic.js" "$ROOT_DIR/$GITHUB_REL/GitHubMarkdown.js" "$@"
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
  cp "$ROOT_DIR/$GITHUB_REL/GitHubData.qml" "$ROOT_DIR/$GITHUB_REL/"*.js "$dir/"
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

# Runs a scenario (stdin: the body of run(root)) against the plugin's views
# in a headless Quickshell, the shell's theme and widgets stood in for
# (tests/support/github_views), and prints what it returns as JSON.
github_views() {
  local dir="$BATS_TEST_TMPDIR/github-views" log
  mkdir -p "$dir"
  cp -r "$ROOT_DIR/tests/support/github_views/." "$dir/"
  cp "$ROOT_DIR/$GITHUB_REL/"*.qml "$ROOT_DIR/$GITHUB_REL/"*.js "$dir/"
  {
    printf 'function run(root) {\n'
    cat
    printf '\n}\n'
  } >"$dir/scenario.js"
  if ! log="$(QT_QPA_PLATFORM=offscreen timeout 30 qs -p "$dir" 2>&1)" || ! grep -q 'RESULT ' <<<"$log"; then
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
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "kf6-syntax-highlighting"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "qt6-qtmultimedia"
  assert_plan_has "$PLAN_DIR/packages/dnf.pkgs" "curl"
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
  assert_equal gh,notify-send,curl "$(jq -r '.dependencies | join(",")' "$dir/plugin.json")"
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

  # No HTTP client in the shell, token, or direct API endpoint:
  # authentication stays with gh, and every process the data layer starts
  # is gh itself (the daemon's only other process is notify-send, which
  # never sees GitHub).
  run grep -rn -i -E '\bwget\b|XMLHttpRequest|api\.github\.com|GH_TOKEN|GITHUB_TOKEN|Authorization|setRequestHeader|oauth_token|secret-tool' "$dir" --include='*.qml' --include='*.js'
  [ "$status" -ne 0 ]
  run grep -l 'Process {' "$dir"/*.qml
  assert_equal "$dir/GitHubDaemon.qml
$dir/GitHubData.qml" "$output"
  assert_file_contains "$dir/GitHubData.qml" 'command: ["gh"].concat(args)'
  assert_file_contains "$dir/GitHubDaemon.qml" 'command: ["notify-send", "--app-name=GitHub"'
  # Except the local copy of an animated image (Qt loops a GIF only from a
  # file), which curl makes from the signed URL GitHub rendered for it and
  # nothing else (see the copies' test): the only curl command there is,
  # and the only URL it is ever handed.
  run grep -rn '"curl"' "$dir" --include='*.qml' --include='*.js'
  assert_equal 1 "${#lines[@]}"
  assert_contains "$output" "GitHubLogic.js"
  assert_file_contains "$dir/GitHubData.qml" 'const command = Logic.mediaDownload(url, path, mediaMaxBytes, mediaTimeoutSeconds);'
  run grep -rhoE 'copyMedia\([a-z]+,' "$dir" --include='*.qml'
  assert_equal "copyMedia(url,
copyMedia(signed," "$output"
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
  tabs: L.TABS.map(t => t.id).join(","),
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
  # GitHub's tab order.
  assert_equal "inbox,issues,prs,actions" "$(jq -r '.tabs' <<<"$output")"
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

@test "github pages come from one answer, images apart, and keep every review thread" {
  need_node

  run github_logic <<'EOF'
const who = login => ({ author: { login: login } });
const repository = {
  nameWithOwner: "o/r", viewerPermission: "WRITE", viewerDefaultMergeMethod: "SQUASH",
  pullRequest: Object.assign(who("ann"), {
    id: "PR_1", number: 5, title: "T", url: "https://github.com/o/r/pull/5", state: "OPEN", isDraft: false,
    body: "![shot](https://github.com/user-attachments/assets/a)",
    mergeable: "MERGEABLE", mergeStateStatus: "BLOCKED", viewerCanClose: true, viewerSubscription: "SUBSCRIBED", viewerCanSubscribe: true,
    labels: { nodes: [{ name: "bug", color: "d73a4a" }] },
    comments: { totalCount: 130, nodes: [Object.assign(who("bob"), { id: "C_1", body: "hi", createdAt: "2026-01-01T10:00:00Z", url: "c1" })] },
    commits: { totalCount: 8, nodes: [{ commit: { statusCheckRollup: { contexts: { totalCount: 2, nodes: [
      { __typename: "CheckRun", name: "test", status: "COMPLETED", conclusion: "FAILURE", detailsUrl: "d", checkSuite: { workflowRun: { workflow: { name: "CI" } } } },
      { __typename: "StatusContext", context: "deploy", state: "SUCCESS", description: "ok", targetUrl: "t" }
    ] } } } }] },
    reviews: { totalCount: 1, nodes: [Object.assign(who("cat"), { databaseId: 1, state: "APPROVED", body: "", submittedAt: "2026-01-01T11:00:00Z", url: "r1" })] },
    reviewThreads: { totalCount: 2, nodes: [
      { id: "T1", path: "a.js", comments: { totalCount: 2, nodes: [Object.assign(who("cat"), { id: "RC_10", databaseId: 10, body: "see <img src=\"https://github.com/user-attachments/assets/b\">", createdAt: "2026-01-01T11:00:00Z", url: "t1", pullRequestReview: { databaseId: 1 } }), null] } },
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
  totals: [page.detail.commentsTotal, page.detail.threadsTotal, page.detail.commitsTotal],
  access: [page.access.canWrite, page.access.canClose, page.access.mergeMethod, page.access.subscription.on],
  rendering: page.rendering.map(entry => entry.id),
  images: L.renderedImages([
    { id: "PR_1", bodyHTML: '<img class="emoji" src="e"><img src="https://signed/a" data-canonical-src="x">' },
    { id: "RC_10", bodyHTML: '<p>see <img src="https://signed/b&amp;x=1" data-animated-image=""></p>' },
    null
  ], page.rendering),
  ids: L.variableArgs({ ids: ["A", "B"] }),
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
  assert_equal '[130,2,8]' "$(jq -c '.totals' <<<"$output")"
  assert_equal '[true,true,"SQUASH",true]' "$(jq -c '.access' <<<"$output")"
  # Only the posts that name images have their rendered HTML asked for,
  # and each image takes the signed URL GitHub rendered for it, moving (a
  # GIF) when GitHub marked it so.
  assert_equal '["PR_1","RC_10"]' "$(jq -c '.rendering' <<<"$output")"
  assert_equal '{"PR_1":{"https://github.com/user-attachments/assets/a":{"src":"https://signed/a","animated":false,"raster":false}},"RC_10":{"https://github.com/user-attachments/assets/b":{"src":"https://signed/b&x=1","animated":true,"raster":false}}}' "$(jq -c '.images' <<<"$output")"
  assert_equal '["-f","ids[]=A","-f","ids[]=B"]' "$(jq -c '.ids' <<<"$output")"
  # A thread whose review was not fetched stands on its own, in time
  # order, instead of going missing.
  assert_equal '["review:dan:T2","comment:bob:","review:cat:T1"]' "$(jq -c '.timeline' <<<"$output")"
}

@test "github Markdown keeps code as written and cuts long bodies with a way back" {
  need_node

  run github_logic <<'EOF'
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
  indented: L.parseMarkdown("Para\n\n    <div>hello</div>\n    <!-- kept -->\n\nAfter", "", style).map(b => b.type + ":" + (b.text || b.html)),
  listed: L.parseMarkdown("- ```html\n  <div>a</div>\n  ```\n- item\n\n      <b>deep</b>", "", style)[0].items.map(item => item.blocks.map(b => b.type + ":" + (b.text || b.html)).join("|")),
  angle: L.parseMarkdown("[docs](<https://example.com/a>) and <https://example.com/b>", "", style)[0].html.match(/href="[^"]+"|>[a-z:/.]+<\/span/g),
  fitting: L.blocksWithin(long, 6000),
  all: long.length
};
EOF
  [ "$status" -eq 0 ]
  assert_equal '["paragraph","code","paragraph"]' "$(jq -c '.types' <<<"$output")"
  # Comments outside code drop, and layout markup for its text, a
  # division on a line of its own as a browser shows it...
  assert_equal "Intro<br>kept text" "$(jq -r '.intro' <<<"$output")"
  # ...and code keeps every character.
  assert_equal '<div>hello</div>
<!-- keep -->' "$(jq -r '.code' <<<"$output")"
  assert_equal 2 "$(jq -r '.lines' <<<"$output")"
  assert_equal true "$(jq -r '.inline' <<<"$output")"
  assert_equal '["href=\"https://github.com/o/r/issues/12\"","href=\"https://github.com/ann\""]' "$(jq -c '.refs' <<<"$output")"
  # Indented code, and code in a list item (fenced after its marker, or
  # indented past its text), keeps its tags and comments too.
  assert_equal '["paragraph:Para","code:<div>hello</div>\n<!-- kept -->","paragraph:After"]' "$(jq -c '.indented' <<<"$output")"
  assert_equal '["code:<div>a</div>","paragraph:item|code:<b>deep</b>"]' "$(jq -c '.listed' <<<"$output")"
  # A link's destination in angle brackets is the link's own.
  assert_equal '["href=\"https://example.com/a\"",">docs</span","href=\"https://example.com/b\"",">https://example.com/b</span"]' "$(jq -c '.angle' <<<"$output")"
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
const loaded = () => data.scopeOf("").threads;
data.refreshThreads("");
gh.answer(gh.firstPage(), threads(1, 50));
data.loadMoreThreads("");
gh.answer(gh.next("before="), threads(51, 100));
// A new thread pushes thread 50 off the first page.
data.refreshThreads("");
gh.answer(gh.firstPage(), threads(0, 49));
gh.answer(gh.next("before="), threads(49, 98));
const all = ids(loaded());
// More than a page of threads in one second: the same page comes back,
// and the next page of that look goes on past it.
const tied = [];
for (let i = 101; i <= 150; i++)
  tied.push(thread(i, stamp(100)));
data.patchScope("", { "threadsMore": true });
data.loadMoreThreads("");
gh.answer(gh.next("before="), tied);
data.loadMoreThreads("");
gh.answer(gh.next("before="), tied);
const retry = gh.next("before=").line;
gh.answer(gh.next("page=2"), threads(151, 160));
return {
  count: all.length,
  gap: ["49", "50", "51"].filter(id => all.indexOf(id) < 0),
  retry: /&page=2/.test(retry),
  after: loaded().length
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

@test "github drops later inbox pages that threads marked done elsewhere left behind" {
  need_qs

  run github_data <<'EOF'
const gh = fakeGh(data);
const loaded = () => data.scopeOf("o/r").threads;
const load = () => {
  data.refreshThreads("o/r");
  gh.answer(gh.firstPage("repos/o/r/notifications"), threads(1, 50));
  data.loadMoreThreads("o/r");
  gh.answer(gh.next("before="), threads(51, 100));
};
load();
// 41-100 were marked done on github.com: the first page is short, so it
// is all.
data.refreshThreads("o/r");
gh.answer(gh.firstPage(), threads(1, 40));
const short = [loaded().length, data.scopeOf("o/r").threadsMore, gh.waiting("before=").length];
// The first page stays full, but the pages after it thinned out.
data.refreshThreads("o/r");
gh.answer(gh.firstPage(), threads(1, 50));
data.loadMoreThreads("o/r");
gh.answer(gh.next("before="), threads(51, 100));
data.refreshThreads("o/r");
gh.answer(gh.firstPage(), threads(1, 50));
const during = loaded().length;
gh.answer(gh.next("repos/o/r/notifications?all=true&per_page=50&before="), threads(51, 60));
return { short: short, during: during, after: loaded().length, more: data.scopeOf("o/r").threadsMore };
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
const loaded = () => data.scopeOf("").threads;
data.refreshThreads("");
gh.answer(gh.firstPage(), threads(1, 50));
// The next page is on its way when a refresh finds 40 in all.
data.loadMoreThreads("");
const old = gh.next("before=");
data.refreshThreads("");
gh.answer(gh.firstPage(), threads(1, 40));
gh.answer(old, threads(51, 100));
const short = [loaded().length, gh.waiting("before=").length];
// With a full new first page, the page is asked for again against it.
data.refreshThreads("");
gh.answer(gh.firstPage(), threads(1, 50));
data.loadMoreThreads("");
const stale = gh.next("before=");
data.refreshThreads("");
gh.answer(gh.firstPage(), threads(0, 49));
gh.answer(stale, threads(51, 100));
const fresh = gh.next("before=");
gh.answer(fresh, threads(49, 98));
return { short: short, asked: /before=2026-01-01T11%3A59%3A12Z/.test(fresh.line), all: loaded().length };
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
  # What loads a picture or plays a video is only ever given a signed URL
  # from the page's answer (a GIF's local copy is made from one), or a
  # public avatar: every source the plugin sets is one of these.
  run grep -lw -E '(Animated)?Image \{|MediaPlayer \{' "$dir"/*.qml
  assert_equal "$dir/GitHubAvatar.qml
$dir/GitHubMarkdown.qml
$dir/GitHubVideo.qml" "$output"
  run bash -c "grep -hE '^\\s*(source:|[a-z.]*source = )' '$dir'/GitHub{Avatar,Markdown,Video}.qml | sed -E 's/^\\s+//' | LC_ALL=C sort -u"
  assert_equal 'item.source = Qt.binding(() => videoBox.rendered.src || "");
player.source = source;
source: "GitHubVideo.qml"
source: avatar.login !== "" && avatar.login !== "ghost" ? "https://avatars.githubusercontent.com/" + encodeURIComponent(avatar.login) + "?s=72" : ""
source: tile.moves ? "" : tile.signed
source: tile.moves ? tile.copy : ""' "$output"
  assert_file_contains "$dir/GitHubMarkdown.qml" 'readonly property var rendered: md.images[image.url] || ({})'
  assert_file_contains "$dir/GitHubMarkdown.qml" 'signed = rendered.src;'
}

@test "github inbox filters and searches as github.com's inbox does" {
  need_node

  run github_logic <<'EOF'
const t = (id, reason, type, repo) => ({ kind: "notification", id: id, reason: reason, type: type || "Issue", repo: repo || "o/r", title: { a: "alpha", b: "beta", c: "gamma delta", d: "delta", e: "epsilon" }[id], number: 1 });
const threads = [t("a", "assign"), t("b", "subscribed", "Release"), t("c", "mention", "PullRequest", "x/y"), t("d", "team_mention"), t("e", "ci_activity", "CheckSuite")];
const unread = { a: true, c: true };
const search = text => {
  const q = L.inboxQuery(text);
  return threads.filter(th => L.threadMatches(th, q, !!unread[th.id], th.id === "c" ? "Octo" : "")).map(th => th.id).join(",");
};
return {
  chips: L.filtersFor("", "inbox").map(f => f.key).join(","),
  participating: L.filterThreads(threads, "participating").map(th => th.id).join(","),
  mention: L.filterThreads(threads, "mention").map(th => th.id).join(","),
  unread: search("is:unread"),
  read: search("is:read"),
  reasons: search("reason:team-mention reason:assign"),
  both: search("reason:assign is:read"),
  participatingQuery: search("reason:participating"),
  types: search("is:release is:check_suite"),
  prs: search("is:pr"),
  issues: search("is:issue"),
  bots: ["author:dependabot", "author:dependabot[bot]", "author:app/dependabot"].map(text => L.threadMatches(threads[0], L.inboxQuery(text), false, "dependabot[bot]")),
  place: [search("repo:X/Y"), search("org:o")],
  author: [search("author:octo"), search("author:app/octo")],
  words: search("delta gamma"),
  done: L.inboxQuery("is:done").unsupported !== "",
  urls: [L.tabUrl("", "inbox"), L.tabUrl("o/r", "inbox")]
};
EOF
  [ "$status" -eq 0 ]
  # GitHub's default filters, in its order; participating leaves out what
  # comes from watching a repository.
  assert_equal "all,assign,participating,mention,team_mention,review_requested" "$(jq -r '.chips' <<<"$output")"
  assert_equal "a,c,d" "$(jq -r '.participating' <<<"$output")"
  assert_equal "c" "$(jq -r '.mention' <<<"$output")"
  assert_equal "a,c" "$(jq -r '.unread' <<<"$output")"
  assert_equal "b,d,e" "$(jq -r '.read' <<<"$output")"
  # One qualifier's values widen, different qualifiers narrow.
  assert_equal "a,d" "$(jq -r '.reasons' <<<"$output")"
  assert_equal "" "$(jq -r '.both' <<<"$output")"
  assert_equal "a,c,d" "$(jq -r '.participatingQuery' <<<"$output")"
  assert_equal "b,e" "$(jq -r '.types' <<<"$output")"
  # A subject's type tells pull requests and issues apart, and an app
  # answers to its name, its bot's login, and app/name alike.
  assert_equal "c" "$(jq -r '.prs' <<<"$output")"
  assert_equal "a,d" "$(jq -r '.issues' <<<"$output")"
  assert_equal '[true,true,true]' "$(jq -c '.bots' <<<"$output")"
  assert_equal '["c","a,b,d,e"]' "$(jq -c '.place' <<<"$output")"
  assert_equal '["c","c"]' "$(jq -c '.author' <<<"$output")"
  assert_equal "c" "$(jq -r '.words' <<<"$output")"
  assert_equal true "$(jq -r '.done' <<<"$output")"
  assert_equal '["https://github.com/notifications","https://github.com/notifications?query=repo%3Ao%2Fr"]' "$(jq -c '.urls' <<<"$output")"
}

@test "github looks up notification subjects with names as variables" {
  need_node

  run github_logic <<'EOF'
const t = (repo, number, type) => ({ repo: repo, number: number, type: type, url: "https://github.com/" + repo + "/" + number });
const request = L.subjectsQuery([t("o/r", 1, "Issue"), t("o/r", 2, "PullRequest"), t("o/r", 2, "PullRequest"), t("x/y", 3, "Issue"), t("o/r", 0, "Release")]);
const found = L.subjectsOf({
  "r0": { "r0s0": { "__typename": "Issue", "state": "CLOSED", "stateReason": "NOT_PLANNED", "author": { "login": "a" } }, "r0s1": { "__typename": "PullRequest", "state": "MERGED", "isDraft": false, "author": null } },
  "r1": null
}, request.keys);
return { query: request.query, vars: request.vars, found: found, args: L.variableArgs(request.vars).slice(0, 4) };
EOF
  [ "$status" -eq 0 ]
  # Each repository once, each subject once, and nothing of a name inside
  # the query text.
  assert_equal 'query Subjects($o0: String!, $n0: String!, $kr0s0: Int!, $kr0s1: Int!, $o1: String!, $n1: String!, $kr1s0: Int!)' "$(jq -r '.query | split(" {")[0]' <<<"$output")"
  assert_equal '{"o0":"o","n0":"r","kr0s0":1,"kr0s1":2,"o1":"x","n1":"y","kr1s0":3}' "$(jq -c '.vars' <<<"$output")"
  assert_equal '["-f","o0=o","-f","n0=r"]' "$(jq -c '.args' <<<"$output")"
  # A repository GitHub cannot show leaves its subjects out.
  assert_equal '{"https://github.com/o/r/1":{"kind":"issue","state":"CLOSED","isDraft":false,"stateReason":"NOT_PLANNED","author":"a"},"https://github.com/o/r/2":{"kind":"pr","state":"MERGED","isDraft":false,"stateReason":"","author":""}}' "$(jq -c '.found' <<<"$output")"
}

@test "github marks threads done, read, and unsubscribed, and takes back what GitHub refuses" {
  need_qs

  run github_data <<'EOF'
const gh = fakeGh(data);
data.refreshNotifications();
gh.answer(gh.next("-i notifications"), inbox(threads(1, 3)));
data.refreshThreads("");
const read = thread(4, stamp(4));
read.unread = false;
gh.answer(gh.firstPage(), threads(1, 3).concat([read]));
const shown = () => data.inboxThreads("").map(t => t.id).join(",");
const byId = id => data.scopeOf("").threads.find(t => t.id === id);
// The subjects of the page are looked up once.
const lookups = gh.waiting("query=query Subjects").length;
data.markDone([byId("1"), byId("2")]);
const hidden = [shown(), data.unreadNotifications.length];
gh.answer(gh.next("DELETE notifications/threads/1"), "");
gh.answer(gh.next("DELETE notifications/threads/2"), "", 1, "HTTP 404: Not Found");
const refused = [shown(), toasts.length];
// Unsubscribing ignores the thread, then marks it done.
data.unsubscribe([byId("3")]);
const first = gh.next("threads/3").line;
gh.answer(gh.next("threads/3/subscription"), "");
const then = gh.next("threads/3").line;
gh.answer(gh.next("threads/3"), "");
// Ignored but not done: the toast says it went halfway.
data.unsubscribe([byId("4")]);
gh.answer(gh.next("threads/4/subscription"), "");
gh.answer(gh.next("DELETE notifications/threads/4"), "", 1, "HTTP 502: Bad Gateway");
const halfway = toasts[toasts.length - 1][2];
// A read thread is not marked read again; an unread one is at once.
data.markThreadsRead([byId("4"), byId("2")]);
const reads = gh.waiting("PATCH").map(call => call.line);
return {
  lookups: lookups,
  hidden: hidden,
  refused: refused,
  unsubscribe: [first, then],
  halfway: halfway,
  after: shown(),
  reads: reads,
  unread: data.isUnread(byId("2"))
};
EOF
  [ "$status" -eq 0 ]
  assert_equal 1 "$(jq -r '.lookups' <<<"$output")"
  # Done leaves the inbox and the unread count at once; a refusal puts the
  # thread back and says why.
  assert_equal '["3,4",1]' "$(jq -c '.hidden' <<<"$output")"
  assert_equal '["2,3,4",1]' "$(jq -c '.refused' <<<"$output")"
  assert_equal '["api -X PUT notifications/threads/3/subscription -F ignored=true","api -X DELETE notifications/threads/3"]' "$(jq -c '.unsubscribe' <<<"$output")"
  assert_equal "Unsubscribed, but still in the inbox: HTTP 502: Bad Gateway" "$(jq -r '.halfway' <<<"$output")"
  assert_equal "2,4" "$(jq -r '.after' <<<"$output")"
  assert_equal '["api -X PATCH notifications/threads/2"]' "$(jq -c '.reads' <<<"$output")"
  assert_equal false "$(jq -r '.unread' <<<"$output")"
}

@test "github reads a repository's whole inbox in one request, and follows new activity on screen" {
  need_qs

  run github_data <<'EOF'
const gh = fakeGh(data);
const panel = Qt.createQmlObject('import QtQuick; QtObject { property string scope: "o/r" }', data);
data.setWatching(panel, true);
data.refreshThreads("o/r");
gh.answer(gh.firstPage("repos/o/r/notifications"), threads(1, 3));
data.markAllRead("o/r", data.inboxThreads("o/r"));
const put = gh.next("PUT").line;
const count = data.tabCount("o/r", "inbox");
gh.answer(gh.next("PUT"), "");
// New unread activity refreshes the inbox a panel shows.
const before = gh.waiting("repos/o/r/notifications?all=true").length;
data.refreshNotifications();
gh.answer(gh.next("-i notifications"), inbox(threads(0, 0)));
return { put: put, count: count, before: before, after: gh.waiting("repos/o/r/notifications?all=true").length };
EOF
  [ "$status" -eq 0 ]
  assert_equal "api -X PUT repos/o/r/notifications -f last_read_at=2026-01-01T11:59:59Z" "$(jq -r '.put' <<<"$output")"
  assert_equal 0 "$(jq -r '.count' <<<"$output")"
  assert_equal '[0,1]' "$(jq -c '[.before, .after]' <<<"$output")"
}

@test "github shows unread activity the poll found in the inbox before its next look" {
  need_qs

  run github_data <<'EOF'
const gh = fakeGh(data);
data.refreshThreads("");
const old = thread(2, stamp(9));
old.unread = false;
gh.answer(gh.firstPage(), [old, thread(3, stamp(10))]);
// The poll finds new activity in 2 and a thread 1 the inbox has not
// loaded; another repository's thread stays out of o/r's inbox.
const other = thread(4, stamp(0));
other.repository.full_name = "x/y";
data.refreshNotifications();
gh.answer(gh.next("-i notifications"), inbox([thread(1, stamp(1)), thread(2, stamp(2)), other]));
const shown = data.inboxThreads("");
return {
  viewer: shown.map(t => t.id + (data.isUnread(t) ? "*" : "")).join(","),
  repo: data.inboxThreads("o/r").map(t => t.id).join(",")
};
EOF
  [ "$status" -eq 0 ]
  assert_equal "4*,1*,2*,3*" "$(jq -r '.viewer' <<<"$output")"
  assert_equal "1,2" "$(jq -r '.repo' <<<"$output")"
}

@test "github searches an inbox opened moments before, and freshens only its newest page" {
  need_qs

  run github_data <<'EOF'
const gh = fakeGh(data);
const panel = Qt.createQmlObject('import QtQuick; QtObject { property string scope: "" }', data);
data.setWatching(panel, true);
data.refreshThreads("");
// A search typed while the inbox is still coming keeps the depth it asked.
data.loadAllThreads("");
gh.answer(gh.firstPage(), threads(1, 50));
const older = gh.waiting("before=").length;
gh.answer(gh.next("before="), threads(51, 60));
const pages = data.scopeOf("").threadPages;
// New activity asks for the newest page alone, and the older pages stay.
data.refreshNotifications();
gh.answer(gh.next("-i notifications"), inbox([thread(0, stamp(0))]));
const fresh = gh.waiting("notifications?all=true").map(call => call.line.indexOf("before=") >= 0);
gh.answer(gh.firstPage(), threads(0, 49));
return {
  older: older,
  pages: pages,
  fresh: fresh,
  loaded: data.scopeOf("").threads.length,
  more: gh.waiting("before=").length
};
EOF
  [ "$status" -eq 0 ]
  assert_equal '[1,2]' "$(jq -c '[.older, .pages]' <<<"$output")"
  assert_equal '[false]' "$(jq -c '.fresh' <<<"$output")"
  assert_equal '[61,0]' "$(jq -c '[.loaded, .more]' <<<"$output")"
}

@test "github keeps signed media URLs a few minutes, and asks again for an expired one" {
  need_qs

  run github_data <<'EOF'
const gh = fakeGh(data);
const url = "https://github.com/user-attachments/assets/a";
const posts = [{ "id": "P", "body": "![a](" + url + ")" }];
const rendered = n => ({ "data": { "nodes": [{ "id": "P", "bodyHTML": '<img src="https://signed/a?jwt=' + n + '">' }] } });
const seen = [];
const note = found => seen.push(found[url] ? found[url].src : "");
data.loadMedia(posts, note);
gh.op("Rendered", rendered(1));
// A page opened again meanwhile has them at once, without asking.
data.loadMedia(posts, note);
const cached = gh.waiting("operationName=Rendered").length;
// An expired one is asked for again, and so is an edited post.
data.loadMedia(posts, note, null, true);
gh.op("Rendered", rendered(2));
data.loadMedia([{ "id": "P", "body": posts[0].body + " edited" }], note);
return { seen: seen, cached: cached, edited: gh.waiting("operationName=Rendered").length };
EOF
  [ "$status" -eq 0 ]
  assert_equal '["https://signed/a?jwt=1","https://signed/a?jwt=1","https://signed/a?jwt=2"]' "$(jq -c '.seen' <<<"$output")"
  assert_equal '[0,1]' "$(jq -c '[.cached, .edited]' <<<"$output")"
}

@test "github reads reactions per post and counts the viewer's own as GitHub will" {
  need_node

  run github_logic <<'EOF'
const group = (content, count, mine) => ({ content: content, viewerHasReacted: !!mine, reactors: { totalCount: count } });
const node = { id: "C1", viewerCanReact: true, reactionGroups: [group("THUMBS_UP", 3, true), group("THUMBS_DOWN", 0), group("EYES", 1)] };
const info = L.reactionsOf(node);
const detail = { comments: [{ author: { login: "a" }, createdAt: "2026-01-01T00:00:00Z", body: "hi", reactions: info }], reviews: [
  { databaseId: 1, state: "COMMENTED", body: "looks good", submittedAt: "2026-01-02T00:00:00Z", author: { login: "b" }, id: "R1", viewerCanReact: false, reactionGroups: [group("HEART", 2)] },
  { databaseId: 2, state: "APPROVED", body: "", submittedAt: "2026-01-03T00:00:00Z", author: { login: "c" }, id: "R2", viewerCanReact: true, reactionGroups: [] }
], threads: [] };
return {
  info: info,
  none: L.reactionsOf({ body: "x" }),
  chips: L.reactionChips(L.withReaction(L.withReaction(info.groups, "THUMBS_UP", false), "LAUGH", true)).map(c => c.emoji + c.count + (c.mine ? "*" : "")),
  gone: Object.keys(L.withReaction(info.groups, "EYES", true)).length,
  last: Object.keys(L.withReaction({ "EYES": { count: 1, mine: true } }, "EYES", false)),
  timeline: L.buildTimeline(detail).map(e => e.reactions ? e.reactions.id : null),
  args: L.reactionArgs("C1", "ROCKET", false)
};
EOF
  [ "$status" -eq 0 ]
  # Only the reactions someone gave, with the viewer's marked.
  assert_equal '{"id":"C1","canReact":true,"groups":{"THUMBS_UP":{"count":3,"mine":true},"EYES":{"count":1,"mine":false}}}' "$(jq -c '.info' <<<"$output")"
  assert_equal null "$(jq -c '.none' <<<"$output")"
  # Taking one back lowers its count, a new one starts at 1, in GitHub's
  # picker order; a reaction nobody else gave leaves with the viewer's.
  assert_equal '["👍2","😄1*","👀1"]' "$(jq -c '.chips' <<<"$output")"
  assert_equal 2 "$(jq -r '.gone' <<<"$output")"
  assert_equal '[]' "$(jq -c '.last' <<<"$output")"
  # A review without a summary has nothing to react to.
  assert_equal '["C1","R1",null]' "$(jq -c '.timeline' <<<"$output")"
  assert_equal '"removeReaction(input: {subjectId: $id, content: $content})"' "$(jq -c '.args[3] | capture("(?<m>removeReaction\\(input: [^)]*\\))").m' <<<"$output")"
  assert_equal '["-f","id=C1","-f","content=ROCKET"]' "$(jq -c '.args[4:]' <<<"$output")"
}

@test "github says why GitHub refused a reaction" {
  need_qs

  run github_data <<'EOF'
const gh = fakeGh(data);
const answers = [];
data.react("C1", "HEART", true, ok => answers.push(ok));
gh.answer(gh.next("addReaction"), { "data": { "addReaction": { "reaction": { "content": "HEART" } } } });
data.react("C1", "HEART", false, ok => answers.push(ok));
gh.answer(gh.next("removeReaction"), { "data": null, "errors": [{ "type": "FORBIDDEN", "message": "Locked conversation" }] }, 1);
return { answers: answers, toasts: toasts.map(t => t[2]) };
EOF
  [ "$status" -eq 0 ]
  assert_equal '{"answers":[true,false],"toasts":["Locked conversation"]}' "$(jq -c . <<<"$output")"
}

@test "github asks who reacted once a minute per post, and again after the viewer's change" {
  need_qs

  run github_data <<'EOF'
const gh = fakeGh(data);
const person = (login, name) => ({ "__typename": "User", "login": login, "name": name });
const answer = { "data": { "node": { "reactionGroups": [
  { "content": "THUMBS_UP", "reactors": { "totalCount": 12, "nodes": [person("a", "Ann"), { "__typename": "Bot", "login": "bot" }] } },
  { "content": "EYES", "reactors": { "totalCount": 0, "nodes": [] } }
] } } };
const seen = [];
data.loadReactors("P1", groups => seen.push(groups));
gh.op("Reactors", answer);
data.loadReactors("P1", groups => seen.push(Object.keys(groups)));
const kept = gh.waiting("Reactors").length;
data.react("P1", "EYES", true, null);
gh.answer(gh.next("addReaction"), { "data": { "addReaction": { "reaction": { "content": "EYES" } } } });
data.loadReactors("P1", groups => seen.push(groups));
return { first: seen[0], second: seen[1], kept: kept, again: gh.waiting("Reactors").length };
EOF
  [ "$status" -eq 0 ]
  assert_equal '{"THUMBS_UP":{"total":12,"people":[{"login":"a","name":"Ann"},{"login":"bot","name":""}]}}' "$(jq -c '.first' <<<"$output")"
  assert_equal '["THUMBS_UP"]' "$(jq -c '.second' <<<"$output")"
  assert_equal 0 "$(jq -r '.kept' <<<"$output")"
  assert_equal 1 "$(jq -r '.again' <<<"$output")"
}

@test "github Markdown keeps collapsible sections closed behind their summary" {
  need_node

  run github_logic <<'EOF'
const body = [
  "Intro",
  "<details>",
  "<summary>📥 <b>Commits</b></summary>",
  "",
  "Reviewing files.",
  "",
  "<details open><summary>Nested</summary>",
  "- item",
  "```",
  "<details>kept</details>",
  "```",
  "</details>",
  "",
  "</details>",
  "<details><summary>No end</summary>",
  "",
  "## Setup",
  "tail"
].join("\n");
const blocks = L.parseMarkdown(body, "o/r", style);
const shape = list => list.map(b => b.type + (b.type === "details" ? "#" + b.id + (b.open ? "+" : "") + "=" + b.html + "(" + shape(b.blocks).join(",") + ")" : ""));
const long = "<details><summary>Hidden</summary>\n\n" + "x".repeat(9000) + "\n\n</details>\n\nShown";
const longBlocks = L.parseMarkdown(long, "o/r", style);
return {
  shape: shape(blocks),
  code: blocks[1].blocks[1].blocks[1].text,
  anchor: L.anchorPath(blocks, "setup"),
  fits: [L.blocksWithin(longBlocks, 6000), longBlocks.length]
};
EOF
  [ "$status" -eq 0 ]
  # A section holds what it holds (nested sections too), open or not as
  # the body says; one left unclosed runs to the end, and the tags inside
  # code stay code.
  assert_equal '["paragraph","details#0=📥 <b>Commits</b>(paragraph,details#1+=Nested(list,code))","details#2=No end(heading,paragraph)"]' "$(jq -c '.shape' <<<"$output")"
  assert_equal "<details>kept</details>" "$(jq -r '.code' <<<"$output")"
  # An in-page link to a heading in a closed section knows which sections
  # to open.
  assert_equal '{"index":2,"sections":[2]}' "$(jq -c '.anchor' <<<"$output")"
  # What a closed section hides does not count toward cutting a long body.
  assert_equal '[2,2]' "$(jq -c '.fits' <<<"$output")"
}

@test "github Markdown lets no markup of a body's own through, and reads what it cannot parse as text" {
  need_node

  run github_logic <<'EOF'
// Every rich text a body's blocks carry.
const htmls = list => list.flatMap(b => [b.html || ""].concat(htmls(b.blocks || []), (b.items || []).flatMap(item => item.html ? [item.html] : htmls(item.blocks || [])), [b.header || []].concat(b.rows || []).flatMap(row => row.map(cell => cell.html))));
const hostile = [
  "$$\n\\mathbb{<img src=\"http://127.0.0.1/x\">}\n$$",
  "```math\n\\Bbb{<img src=x>} \\text{<img src=y>}\n```",
  "Inline $\\mathbb{<img src=z>}$ and $\\constructor \\toString x$",
  "<script>alert(1)</script> <iframe src=\"http://h\"></iframe> <style>*{}</style> <img src=\"http://h/p\" onerror=\"x\"> in prose",
  "| a |\n|---|\n| $\\mathbb{<img src=w>}$ <b onclick=\"x\">b</b> |",
  "<details><summary><img src=\"http://h/s\"> sum</summary>\n\nin\n\n</details>",
  "[^n]\n\n[^n]: $\\mathbb{<img src=n>}$",
  "Marks \u00010\u0002 \u0003D1 \u0005 stay out"
];
const leaks = hostile.map(text => htmls(L.parseMarkdown(text, "o/r", style)).filter(html => /<(img|script|iframe|style)\b|\son\w+=|\u0001|\u0003/i.test(html)));
const math = text => L.parseMarkdown(text, "", style)[0].html.replace(/<[^>]+>/g, "");
return {
  leaks: leaks,
  blackboard: math("$$\\mathbb{R} \\mathbb{<b>}$$"),
  unclosed: math("```math\n\\sqrt[3{x}\n```"),
  deep: math("$$" + "{".repeat(50000) + "x$$").length > 0
};
EOF
  [ "$status" -eq 0 ]
  # Math, table cells, summaries, footnotes, and prose alike: what a body
  # writes shows as text, and only what the plugin writes is rich text (a
  # picture loads only from the signed URL GitHub rendered for it).
  assert_equal '[[],[],[],[],[],[],[],[]]' "$(jq -c '.leaks' <<<"$output")"
  assert_equal 'ℝ &lt;b&gt;' "$(jq -r '.blackboard' <<<"$output")"
  # TeX it cannot close or nest that deep shows as far as it reads, never
  # stopping the post from rendering.
  assert_equal '√[3x' "$(jq -r '.unclosed' <<<"$output")"
  assert_equal true "$(jq -r '.deep' <<<"$output")"
}

@test "github Markdown reads the blocks github.com renders, nested as there" {
  need_node

  run github_logic <<'EOF'
const body = [
  "Title",
  "=====",
  "",
  "> [!WARNING]",
  "> Careful",
  "> > inner",
  "",
  "1. one",
  "2. two",
  "   - sub",
  "     ```sh",
  "     echo <b>hi</b>",
  "     ```",
  "   1. roman",
  "3. [x] done",
  "",
  "| L | C | R |",
  "|:--|:-:|--:|",
  "| a \\| b | ![p](https://i/p.png) |",
  "",
  "    indented <code>",
  "",
  "Cite[^n] and [text][ref].",
  "",
  "[ref]: https://x.y/z",
  "[^n]: The note.",
  "",
  "$$",
  "\\frac{a}{b} \\le \\alpha",
  "$$",
  "",
  "<p align=\"center\"><a href=\"https://d\"><picture><source srcset=\"dark.svg\"><img src=\"https://s/light.svg\" width=\"120\" alt=\"Badge\"></picture></a></p>",
  "",
  "<table><tr><th>Before</th><th align=\"right\">After</th></tr><tr><td><p>x</p><p>y</p></td><td>z</td></tr></table>",
  "",
  "<ul><li>top<ol><li>in</li></ol></li></ul>",
  "",
  "https://github.com/user-attachments/assets/abc-123"
].join("\n");
const blocks = L.parseMarkdown(body, "o/r", style);
const shape = list => list.map(b => b.type + (b.blocks ? "(" + shape(b.blocks).join(",") + ")" : "") + (b.type === "list" ? "[" + b.items.map(item => item.marker + (item.task ? ":" + item.task : "") + "(" + shape(item.blocks).join(",") + ")").join(" ") + "]" : ""));
const find = type => blocks.find(b => b.type === type);
const table = blocks.filter(b => b.type === "table");
return {
  shape: shape(blocks),
  heading: [blocks[0].level, blocks[0].anchors],
  alert: find("quote").alert,
  nestedCode: blocks[2].items[1].blocks[1].items[0].blocks[1].text,
  lang: blocks[2].items[1].blocks[1].items[0].blocks[1].lang,
  aligns: table[0].aligns,
  cells: table[0].rows[0].map(c => c.html || c.images.map(i => i.url).join()),
  indented: find("code") && blocks.filter(b => b.type === "code").map(b => b.text),
  cite: blocks.find(b => (b.anchors || []).indexOf("fnref-n") >= 0).html,
  notes: find("footnotes").items.map(n => n.key + ":" + n.html.replace(/<[^>]+>/g, "")),
  math: find("math").html.replace(/<[^>]+>/g, ""),
  badge: blocks.filter(b => b.type === "images").map(b => [b.align, b.images[0].url, b.images[0].href, b.images[0].width]),
  html: [table[1].header.map(c => c.html), table[1].aligns, table[1].rows[0].map(c => c.html)],
  video: find("video").url,
  schemes: [true, false].map(dark => L.parseMarkdown('<picture><source media="(prefers-color-scheme: dark)" srcset="https://s/dark.svg"><img src="https://s/light.svg" alt="B"></picture>', "", Object.assign({}, style, { "dark": dark }))[0].images[0].url),
  paired: (() => {
    const into = {};
    L.imagePairs('<picture><source media="(prefers-color-scheme: dark)" srcset="https://s/dark.svg"><img src="https://s/light.svg"></picture>', '<picture><source srcset="https://camo/d" data-canonical-src="https://s/dark.svg"><img src="https://camo/l" data-canonical-src="https://s/light.svg"></picture>', into);
    return Object.keys(into).map(url => url + " " + into[url].src);
  })()
};
EOF
  [ "$status" -eq 0 ]
  # Quotes and alerts hold blocks, and so do list items: a nested list with
  # its code, roman numerals a level down, and a task's box.
  assert_equal '["heading","quote(paragraph,quote(paragraph))","list[1.(paragraph) 2.(paragraph,list[circle(paragraph,code)],list[i.(paragraph)]) 3.:done(paragraph)]","table","code","paragraph","math","images","table","list[disc(paragraph,list[i.(paragraph)])]","video","footnotes"]' "$(jq -c '.shape' <<<"$output")"
  assert_equal '[1,["title"]]' "$(jq -c '.heading' <<<"$output")"
  assert_equal warning "$(jq -r '.alert' <<<"$output")"
  assert_equal 'echo <b>hi</b>' "$(jq -r '.nestedCode' <<<"$output")"
  assert_equal sh "$(jq -r '.lang' <<<"$output")"
  # Columns keep their alignment; an escaped pipe stays in its cell, and a
  # cell of pictures shows them.
  assert_equal '["left","center","right"]' "$(jq -c '.aligns' <<<"$output")"
  assert_equal '["a | b","https://i/p.png",""]' "$(jq -c '.cells' <<<"$output")"
  assert_equal '["indented <code>"]' "$(jq -c '.indented' <<<"$output")"
  # Reference links resolve and footnotes number as cited, each linking to
  # its note and back.
  assert_equal 'Cite<sup><a href="#fn-n" style="text-decoration:none"><span style="color:L">1</span></a></sup> and <a href="https://x.y/z" style="text-decoration:none"><span style="color:L">text</span></a>.' "$(jq -r '.cite' <<<"$output")"
  assert_equal '["n:The note. ↩"]' "$(jq -c '.notes' <<<"$output")"
  assert_equal 'a/b ≤ α' "$(jq -r '.math' <<<"$output")"
  # HTML reads as github.com shows it: a centered, linked picture at its
  # width; a table with its alignment and paragraphs as lines; nested lists.
  assert_equal '[["center","https://s/light.svg","https://d",120]]' "$(jq -c '.badge' <<<"$output")"
  assert_equal '[["Before","After"],["","right"],["x<br>y","z"]]' "$(jq -c '.html' <<<"$output")"
  assert_equal https://github.com/user-attachments/assets/abc-123 "$(jq -r '.video' <<<"$output")"
  # A picture shows its image for the shell's scheme, as github.com does,
  # each from the URL GitHub signed for it.
  assert_equal '["https://s/dark.svg","https://s/light.svg"]' "$(jq -c '.schemes' <<<"$output")"
  assert_equal '["https://s/dark.svg https://camo/d","https://s/light.svg https://camo/l"]' "$(jq -c '.paired' <<<"$output")"
}

@test "github Markdown links references and keeps inline HTML as github.com does" {
  need_node

  run github_logic <<'EOF'
const html = text => L.parseMarkdown(text, "o/r", style)[0].html;
const hrefs = text => (html(text).match(/href="[^"]+"/g) || []).map(h => h.slice(6, -1));
const text = s => html(s).replace(/<[^>]+>/g, "");
return {
  refs: hrefs("See x/y#5, GH-7, #8, @ann, @org/team, me@mail.io, www.a.io and x/y@0123456789abcdef"),
  sha: text("Fixed in 0123456789abcdef0123456789abcdef01234567"),
  labels: text("https://github.com/o/r/pull/3 https://github.com/x/y/issues/4#issuecomment-9 https://github.com/o/r/commit/0123456789abcdef0123456789abcdef01234567"),
  paren: hrefs("Read https://en.wikipedia.org/wiki/Foo_(bar)."),
  relative: hrefs("[a](/o/r/blob/main/x.md) [b](../pull/2) [c](#setup)"),
  inline: html("<kbd>K</kbd> <b>b</b> <a name=\"x\"></a><a href=\"https://h\">h</a> Vec<T> &copy; \\*lit\\* ***bi*** ~s~ :tada: H<sub>2</sub>O"),
  swatch: html("`#ff8800` and `rgb(0, 128, 255)`").match(/color:#[0-9a-f]{6}/g),
  math: text("Costs $5 and $10, but $x^2$ is math"),
  code: text("Use `<b>` and `a|b`")
};
EOF
  [ "$status" -eq 0 ]
  assert_equal '["https://github.com/x/y/issues/5","https://github.com/o/r/issues/7","https://github.com/o/r/issues/8","https://github.com/ann","https://github.com/orgs/org/teams/team","mailto:me@mail.io","http://www.a.io","https://github.com/x/y/commit/0123456789abcdef"]' "$(jq -c '.refs' <<<"$output")"
  assert_equal 'Fixed in 0123456' "$(jq -r '.sha' <<<"$output")"
  assert_equal '#3 x/y#4 (comment) 0123456' "$(jq -r '.labels' <<<"$output")"
  assert_equal '["https://en.wikipedia.org/wiki/Foo_(bar)"]' "$(jq -c '.paren' <<<"$output")"
  assert_equal '["https://github.com/o/r/blob/main/x.md","https://github.com/o/r/pull/2","#setup"]' "$(jq -c '.relative' <<<"$output")"
  # Kept tags keep their meaning, anchors without a link drop, text that
  # only looks like a tag stays, and entities, escapes, and emoji read.
  assert_equal '<span style="font-family:'"'"'m'"'"'; font-size:11px; background-color:K; color:T">&nbsp;K&nbsp;</span> <b>b</b> <a href="https://h" style="text-decoration:none"><span style="color:L">h</span></a> Vec&lt;T&gt; &copy; *lit* <b><i>bi</i></b> <s>s</s> 🎉 H<sub>2</sub>O' "$(jq -r '.inline' <<<"$output")"
  assert_equal '["color:#ff8800","color:#0080ff"]' "$(jq -c '.swatch' <<<"$output")"
  assert_equal 'Costs $5 and $10, but x2 is math' "$(jq -r '.math' <<<"$output")"
  # Code spans keep what they hold as written.
  assert_equal 'Use &nbsp;&lt;b&gt;&nbsp; and &nbsp;a|b&nbsp;' "$(jq -r '.code' <<<"$output")"
}

@test "github Markdown fits table columns and colors diffs and code" {
  need_node

  run github_logic <<'EOF'
return {
  fit: L.fitColumns([50, 60], 300, 48),
  share: L.fitColumns([40, 400, 500], 300, 48),
  diff: L.diffHtml("@@ -1 +1 @@\n-old\n+new\n same", { added: "G", addedBackground: "g", removed: "R", removedBackground: "r", hunk: "H" }, false),
  lookup: [L.codeLookup("js"), L.codeLookup("Rust"), L.codeLookup("golang"), L.codeLookup("text"), L.codeLookup("")]
};
EOF
  [ "$status" -eq 0 ]
  # Columns keep their width while they fit; narrow ones keep theirs and
  # the rest share what is left.
  assert_equal '[50,60]' "$(jq -c '.fit' <<<"$output")"
  assert_equal '[40,130,130]' "$(jq -c '.share' <<<"$output")"
  assert_equal '<div style="white-space:pre-wrap"><span style="color:H">@@ -1 +1 @@</span><br><span style="color:R; background-color:r">-old</span><br><span style="color:G; background-color:g">+new</span><br> same</div>' "$(jq -r '.diff' <<<"$output")"
  # A fence's language is looked up by its name, then by the file it names
  # (x.<name> unless the library knows it by another).
  assert_equal '[{"name":"js","file":"x.js"},{"name":"rust","file":"x.rust"},{"name":"golang","file":"x.go"},null,null]' "$(jq -c '.lookup' <<<"$output")"
}

@test "github takes back a refused reaction only on the post that asked" {
  need_qs

  run github_views <<'EOF'
// The page it sits on, gh answering only when told.
const asked = [];
const page = {
  "openPicker": null,
  "github": { "react": (id, content, on, done) => asked.push({ "id": id, "done": done }) },
  "showReactors": () => {},
  "hideReactors": () => {}
};
const post = (id, count, mine) => ({ "id": id, "canReact": true, "groups": { "THUMBS_UP": { "count": count, "mine": mine } } });
const component = Qt.createComponent("GitHubReactions.qml");
if (component.status !== Component.Ready)
    return { "error": component.errorString() };
const reactions = component.createObject(root, { "page": page, "info": post("A", 3, true) });
const shown = () => JSON.stringify(reactions.groups);
// Taken back on A; the page moves on to B before GitHub refuses.
reactions.toggle("THUMBS_UP");
const optimistic = shown();
reactions.info = post("B", 8, false);
asked[0].done(false);
const other = [shown(), JSON.stringify(reactions.pending)];
// On the post that asked, a refusal puts the reaction back.
reactions.toggle("THUMBS_UP");
asked[1].done(false);
return { "optimistic": optimistic, "other": other, "same": shown() };
EOF
  [ "$status" -eq 0 ]
  assert_equal '{"THUMBS_UP":{"count":2,"mine":false}}' "$(jq -r '.optimistic' <<<"$output")"
  assert_equal '["{\"THUMBS_UP\":{\"count\":8,\"mine\":false}}","{}"]' "$(jq -c '.other' <<<"$output")"
  assert_equal '{"THUMBS_UP":{"count":8,"mine":false}}' "$(jq -r '.same' <<<"$output")"
}

@test "github Markdown keeps code in quotes and list items whole, and links references anywhere" {
  need_node

  run github_logic <<'EOF'
const md = text => L.parseMarkdown(text, "", style);
const shape = list => list.map(b => b.type + (b.text !== undefined ? ":" + b.text : "") + (b.blocks ? "(" + shape(b.blocks).join(",") + ")" : "") + (b.items ? "[" + b.items.map(item => shape(item.blocks).join(",")).join(" ") + "]" : ""));
const text = html => html.replace(/<[^>]+>/g, "");
return {
  listed: shape(md("- ```md\n  [guide]: https://example.com\n  ```")),
  quoted: shape(md(">     <div>hello</div>\n>     <!-- kept -->")),
  inCode: md("[a]: https://x\n\n    [b]: https://y\n\nSee [a] and [b]").map(b => b.type + ":" + (b.text || text(b.html))),
  shortcut: md("[guide]: https://example.com\n\nRead [guide] and [Guide][guide].")[0].html.match(/href="[^"]+"/g),
  note: md("Cite[^n].\n\n[^n]: Note.\n\n    More of it.")[1].items.map(item => text(item.html))
};
EOF
  [ "$status" -eq 0 ]
  # What looks like a definition or a tag inside code stays code, in a
  # list item's fence or a quote's indented code.
  assert_equal '["list[code:[guide]: https://example.com]"]' "$(jq -c '.listed' <<<"$output")"
  assert_equal '["quote(code:<div>hello</div>\n<!-- kept -->)"]' "$(jq -c '.quoted' <<<"$output")"
  assert_equal '["code:[b]: https://y","paragraph:See a and [b]"]' "$(jq -c '.inCode' <<<"$output")"
  # A reference links after other text too, and a note keeps its indented
  # paragraph.
  assert_equal '["href=\"https://example.com\"","href=\"https://example.com\""]' "$(jq -c '.shortcut' <<<"$output")"
  assert_equal '["Note.More of it. ↩"]' "$(jq -c '.note' <<<"$output")"
}

@test "github freshens an inbox's newest page only where it reaches the loaded ones" {
  need_qs

  run github_data <<'EOF'
const gh = fakeGh(data);
const panel = Qt.createQmlObject('import QtQuick; QtObject { property string scope: "" }', data);
data.setWatching(panel, true);
data.refreshThreads("");
gh.answer(gh.firstPage(), threads(100, 149));
data.loadMoreThreads("");
gh.answer(gh.next("before="), threads(150, 159));
// 99 newer threads come: the newest page does not reach the loaded ones,
// so the inbox comes again as far as it was loaded.
data.refreshNotifications();
gh.answer(gh.next("-i notifications"), inbox([thread(1, stamp(1))]));
gh.answer(gh.firstPage(), threads(1, 50));
const again = gh.waiting("before=").length;
gh.answer(gh.next("before="), threads(51, 100));
const ids = data.scopeOf("").threads.map(t => Number(t.id));
return { again: again, count: ids.length, first: ids[0], last: ids[ids.length - 1], gaps: ids.filter((id, i) => i > 0 && id !== ids[i - 1] + 1).length };
EOF
  [ "$status" -eq 0 ]
  assert_equal 1 "$(jq -r '.again' <<<"$output")"
  # The first page and the one after it, whole: no thread between them
  # goes missing.
  assert_equal '[100,1,100,0]' "$(jq -c '[.count, .first, .last, .gaps]' <<<"$output")"
}

@test "github renews an expired video's URL without playing it out of sight, and falls back without one" {
  need_qs

  run github_views <<'EOF'
const component = Qt.createComponent("GitHubVideo.qml");
if (component.status !== Component.Ready)
    return { "error": component.errorString() };
const asks = [];
const video = component.createObject(root, { "source": "file:///nonexistent/a.mp4", "renew": done => asks.push(done) });
video.toggle();
// Its URL expired: the page is asked, and the popout closes meanwhile.
video.renewSource();
const waiting = [video.renewing, video.failed];
video.active = false;
video.source = "file:///nonexistent/b.mp4";
asks[0]();
const hidden = [video.renewing, video.failed, video.playing, video.wanted];
// No newer URL (the same one, or GitHub not answering): a link to GitHub.
const other = component.createObject(root, { "source": "file:///nonexistent/c.mp4", "renew": done => done() });
other.toggle();
other.renewSource();
const fallback = [other.renewing, other.failed];
// Another renewal brings a new URL after all: play can be pressed again.
other.source = "file:///nonexistent/d.mp4";
return { "waiting": waiting, "hidden": hidden, "fallback": fallback, "recovered": [other.failed, other.started] };
EOF
  [ "$status" -eq 0 ]
  assert_equal '[true,false]' "$(jq -c '.waiting' <<<"$output")"
  assert_equal '[false,false,false,true]' "$(jq -c '.hidden' <<<"$output")"
  assert_equal '[false,true]' "$(jq -c '.fallback' <<<"$output")"
  assert_equal '[false,false]' "$(jq -c '.recovered' <<<"$output")"
}

@test "github copies an animated image with curl, bounded in size, time, and number at once" {
  need_node
  need_qs
  command -v curl >/dev/null 2>&1 || skip "curl is not installed"

  # The command: the signed URL alone, over HTTPS, and a size and a time.
  run github_logic <<'EOF'
return L.mediaDownload("https://private-user-images.githubusercontent.com/1/a.gif?jwt=x", "/run/user/1/dms-github/media/k.gif", 1024, 60);
EOF
  [ "$status" -eq 0 ]
  local command="$output"
  run jq -r '.[0], .[1], (.[2:] | map(select(test("^-")) | select(test("^(-H|--header|-u|--user|-b|--cookie|-n|--netrc|-K|--config|-A|--user-agent|-e|--referer)$"))) | length)' <<<"$command"
  assert_equal "curl
--disable
0" "$output"
  run jq -r '[.[index("--proto") + 1], .[index("--proto-redir") + 1], .[index("--max-filesize") + 1], .[index("--max-time") + 1], .[-1]] | join(" ")' <<<"$command"
  assert_equal "=https =https 1024 60 https://private-user-images.githubusercontent.com/1/a.gif?jwt=x" "$output"

  # A response that does not say its size, small pieces first and then
  # large ones, stops at the limit (the server here is plain HTTP, the
  # one thing the test changes); and a .curlrc that adds a header is not
  # read, so nothing but the URL reaches the server.
  local dir="$BATS_TEST_TMPDIR/stream" port pid
  mkdir -p "$dir/home"
  printf 'header = "Authorization: Bearer planted"\n' >"$dir/home/.curlrc"
  cat >"$dir/server.py" <<'EOF'
import http.server, socketserver, sys
class Pieces(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def do_GET(self):
        with open(sys.argv[1] + self.path.replace("/", "-"), "w") as seen:
            seen.write(str(self.headers))
        self.send_response(200)
        self.send_header("Transfer-Encoding", "chunked")
        self.end_headers()
        try:
            for size in [100] * 8 + [1 << 20] * 8:
                self.wfile.write(b"%x\r\n" % size + b"G" * size + b"\r\n")
                self.wfile.flush()
            self.wfile.write(b"0\r\n\r\n")
        except OSError:
            pass
    def log_message(self, *args):
        pass
server = socketserver.TCPServer(("127.0.0.1", 0), Pieces)
print(server.server_address[1], flush=True)
server.serve_forever()
EOF
  "$SYSTEM_PYTHON" "$dir/server.py" "$dir/headers" >"$dir/port" &
  pid=$!
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$dir/port" ] && break; sleep 0.2; done
  port="$(cat "$dir/port")"
  local limited
  limited="$(jq -r --arg url "http://127.0.0.1:$port/a.gif" --arg file "$dir/copy.gif" '.[index("--proto") + 1] = "=http" | .[index("--proto-redir") + 1] = "=http" | .[index("--max-filesize") + 1] = "2097152" | .[index("--output") + 1] = $file | .[-1] = $url | .[]' <<<"$command")"
  run env HOME="$dir/home" CURL_HOME="$dir/home" XDG_CONFIG_HOME="$dir/home" bash -c 'mapfile -t args <<<"$1"; "${args[@]}"' _ "$limited"
  local status_limited="$status"
  # The planted file is read by curl without --disable, so its absence
  # above is the option's doing.
  env HOME="$dir/home" CURL_HOME="$dir/home" XDG_CONFIG_HOME="$dir/home" curl --silent --max-filesize 1 --output /dev/null "http://127.0.0.1:$port/b.gif" || true
  kill "$pid"
  # curl's own answer to a file too large, and no more of it than allowed.
  [ "$status_limited" -eq 63 ]
  [ "$(stat -c %s "$dir/copy.gif")" -le 2097152 ]
  run grep -c 'Bearer planted' "$dir/headers-a.gif" "$dir/headers-b.gif"
  assert_equal "$dir/headers-a.gif:0
$dir/headers-b.gif:1" "$output"

  # Two copies at a time; a failed one leaves nothing and answers "".
  run github_data <<'EOF'
const gh = fakeGh(data);
const got = {};
for (const name of ["a", "b", "c"])
    data.copyMedia("https://h/" + name + ".gif?jwt=1", file => got[name] = file);
const first = gh.waiting("curl").length;
gh.answer(gh.next("h/a.gif"), "2048");
const next = gh.waiting("curl").length;
gh.answer(gh.next("h/b.gif"), "", 63, "curl: (63) Exceeded the maximum allowed file size");
gh.answer(gh.next("h/c.gif"), "1024");
// Asked again, a copy made is handed over at once, and a failed one is
// not tried again for a while.
data.copyMedia("https://h/a.gif?jwt=2", file => got.again = file);
data.copyMedia("https://h/b.gif?jwt=2", file => got.retry = file);
return { first: first, next: next, got: got, later: gh.waiting("curl").length };
EOF
  [ "$status" -eq 0 ]
  assert_equal '[2,2,0]' "$(jq -c '[.first, .next, .later]' <<<"$output")"
  run jq -r '.got | [(.a | test("^file://.*/dms-github/media/[0-9a-f]{8}\\.gif$")), .b, (.c | startswith("file://")), (.again == .a), .retry] | map(tostring) | join(" ")' <<<"$output"
  assert_equal "true  true true " "$output"
}

@test "github renews a page's media URLs once for everything that asks meanwhile" {
  need_node

  run github_logic <<'EOF'
let now = 0;
const renewals = L.renewals(20000, () => now);
const log = [];
const starts = [];
const start = finished => starts.push(finished);
renewals.ask(() => log.push("video"), start);
// Asked while that one is on its way: it waits, and nothing new starts.
renewals.ask(() => log.push("second video"), start);
renewals.ask(null, start);
const during = [starts.length, log.length];
now = 5000;
starts[0]();
// Just after: the URLs are as new as they get, so the answer is at once.
now = 10000;
renewals.ask(() => log.push("soon after"), start);
// Later, it asks GitHub again.
now = 40000;
renewals.ask(() => log.push("later"), start);
return { during: during, log: log, starts: starts.length };
EOF
  [ "$status" -eq 0 ]
  assert_equal '[1,0]' "$(jq -c '.during' <<<"$output")"
  assert_equal '["video","second video","soon after"]' "$(jq -c '.log' <<<"$output")"
  assert_equal 2 "$(jq -r '.starts' <<<"$output")"
}

@test "github highlights code by KDE's syntax definitions, and knows when one is missing" {
  need_qs
  need_node
  local dir="$BATS_TEST_TMPDIR/highlight" log lookups
  mkdir -p "$dir/Common"
  cp "$ROOT_DIR/$GITHUB_REL/GitHubHighlighter.qml" "$dir/"
  cat >"$dir/Common/Theme.qml" <<'EOF'
pragma Singleton
import QtQuick
import Quickshell

Singleton {
    property bool isLightMode: false
}
EOF
  # A few fences, and every alias the lookup keeps, against the installed
  # definitions: an unknown one says so (the library answers "None").
  lookups="$(github_logic <<'EOF'
return ["sh", "js", "golang", "shellsession", "dockerfile", "notalanguage"].concat(Object.keys(L.CODE_FILES)).map(L.codeLookup);
EOF
)"
  cat >"$dir/shell.qml" <<EOF
import QtQuick
import Quickshell

ShellRoot {
    TextEdit {
        id: edit
    }

    Component.onCompleted: {
        const component = Qt.createComponent("GitHubHighlighter.qml");
        if (component.status !== Component.Ready) {
            console.warn("MISSING " + component.errorString());
        } else {
            const out = $lookups.map(lookup => {
                const highlighter = component.createObject(edit);
                return lookup.name + ":" + (highlighter.use(lookup) ? highlighter.definition.name : "") + ":" + highlighter.theme.name;
            });
            console.warn("RESULT " + JSON.stringify(out));
        }
        Qt.callLater(Qt.quit);
    }
}
EOF
  log="$(QT_QPA_PLATFORM=offscreen timeout 30 qs -p "$dir" 2>&1)" || true
  if grep -q 'MISSING' <<<"$log"; then
    skip "KDE's syntax highlighting module is not installed"
  fi
  run jq -c '.[:6]' <<<"$(sed -n 's/.*RESULT //p' <<<"$log")"
  assert_equal '["sh:Bash:GitHub Dark","js:JavaScript:GitHub Dark","golang:Go:GitHub Dark","shellsession:Bash:GitHub Dark","dockerfile:Dockerfile:GitHub Dark","notalanguage::GitHub Dark"]' "$output"
  run jq -r '.[6:][] | select(test("^[^:]+::"))' <<<"$(sed -n 's/.*RESULT //p' <<<"$log")"
  assert_equal "" "$output"
}

@test "github pairs a video attachment with the player GitHub rendered for it" {
  need_node

  run github_logic <<'EOF'
const body = "Intro\n\nhttps://github.com/user-attachments/assets/80cd-ff\n\n```\nhttps://github.com/user-attachments/assets/in-code\n```";
const html = '<p>Intro</p><details open=""><summary><svg></svg><span class="m-1">scroll &amp; fling.mp4</span></summary><video src="https://private-user-images.githubusercontent.com/1/2-80cd-ff.mp4?jwt=a&amp;b=1" controls="controls" muted="muted"></video></details>';
const into = {};
L.imagePairs(body, html, into);
return {
  pairs: into,
  rendering: L.renderingOf({ id: "I_1", body: body, comments: { nodes: [{ id: "C_1", body: "no media" }] } }).map(entry => entry.id),
  raster: [["https://private-user-images.githubusercontent.com/1/2-shot.png?jwt=a", ""], ["https://camo.githubusercontent.com/abc/def", "https://img.shields.io/badge/x-y-blue"], ["https://camo.githubusercontent.com/abc/def", "https://s/logo.svg?v=1"], ["https://camo.githubusercontent.com/abc/def", "https://s/photo.JPG"]].map(([src, canonical]) => {
    const into = {};
    L.imagePairs("![x](https://u)", '<img src="' + src + '"' + (canonical ? ' data-canonical-src="' + canonical + '"' : "") + ">", into);
    return into["https://u"].raster;
  }),
  keys: [L.mediaKey("https://h/a.gif?jwt=1"), L.mediaKey("https://h/a.gif?jwt=2"), L.mediaKey("https://h/b"), L.mediaKey("https://h/c.WEBP")]
};
EOF
  [ "$status" -eq 0 ]
  # The player's signed URL carries the attachment's id and its box names
  # the file; a post with only a video still has its HTML asked for.
  assert_equal '{"https://github.com/user-attachments/assets/80cd-ff":{"src":"https://private-user-images.githubusercontent.com/1/2-80cd-ff.mp4?jwt=a&b=1","video":true,"name":"scroll & fling.mp4"}}' "$(jq -c '.pairs' <<<"$output")"
  assert_equal '["I_1"]' "$(jq -c '.rendering' <<<"$output")"
  # A picture of pixels says so by its file (or the one GitHub proxies), and
  # only such a one decodes smaller: a drawing (an SVG, a badge that names
  # no file) would scale up.
  assert_equal '[true,false,false,true]' "$(jq -c '.raster' <<<"$output")"
  # An animated image's local copy is one file whatever signature the URL
  # carries this time.
  run jq -r '.keys | "\(.[0] == .[1]) \(.[0] != .[2]) \(.[2] | test("^[0-9a-f]{8}\\.gif$")) \(.[3] | endswith(".webp"))"' <<<"$output"
  assert_equal "true true true true" "$output"
}

@test "github popout keeps its place for a while after it is dismissed" {
  need_node
  local dir="$ROOT_DIR/$GITHUB_REL"

  run github_logic <<'EOF'
const at = 1000000;
return {
  resumes: [
    L.resumes("", at, at + 299000, 300),
    L.resumes("", at, at + 300000, 300),
    L.resumes("inbox", at, at + 1000, 300),
    L.resumes("", at, at + 1000, 0),
    L.resumes("", 0, at, 300)
  ],
  places: [L.scrollClamp(500, 0, 2000, 600), L.scrollClamp(1800, 0, 2000, 600), L.scrollClamp(-40, 0, 300, 600)]
};
EOF
  [ "$status" -eq 0 ]
  # Opened again from the bar within the setting's time, the popout shows
  # what it showed; later, opened for a tab or a notification, with the
  # setting at 0, or never shown before, it starts over.
  assert_equal '[true,false,false,false,false]' "$(jq -c '.resumes' <<<"$output")"
  # A kept place is taken up as far as the content reaches.
  assert_equal '[500,1400,0]' "$(jq -c '.places' <<<"$output")"
  assert_file_contains "$dir/GitHubWidget.qml" 'resumeSeconds: root.resumeSeconds'
  assert_file_contains "$dir/Settings.qml" 'settingKey: "resumeSeconds"'
}
