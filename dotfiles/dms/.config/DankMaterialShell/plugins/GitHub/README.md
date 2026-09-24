# GitHub

A GitHub mark in the bar and a popout for the notifications, pull requests,
issues, and Actions runs that concern you. Everything goes through the GitHub
CLI: the plugin never asks for, stores, or reads a token, so the account and
its credentials are whatever `gh auth login` set up.

A dot on the mark, like the one on the notification bell, says there are
unread notifications. The number beside it counts pull requests waiting for
your review (Settings can widen it to assignments, switch it to unread
notifications, or hide it; the dot has its own switch). The mark dims while
gh is signed out or GitHub cannot be reached.

## The popout

- **Inbox**: unread notifications, all, mentioned, review requests,
  assigned. Opening one reads it: a pull request or an issue opens its page
  here, anything else (a release, a commit, a discussion) the browser. The
  edge button or Delete marks a thread read without opening it, and the
  header's Mark all as read (a second click confirms) reads the whole inbox,
  as GitHub's own button does, or only the rows a filter or search shows.
  Opening a pull request or an issue from anywhere also reads its
  notification, as a visit to the page does. Notifications refresh every
  minute, whatever the lists' refresh interval.

  New notifications can also appear as desktop notifications (Settings:
  assignments, review requests, and mentions by default; everything; or
  none). Clicking one opens the thread in the popout on the focused screen.
  Each thread is announced once, whatever the number of bars and across
  restarts; the first look only records the inbox instead of replaying it,
  and an old thread that moves up as others are read is not news.
- **Issues**: assigned, created, mentioned.
- **Pull requests**: review requests, created, assigned, mentioned.
- **Actions**: the latest runs of the watched repositories, all, in
  progress, or failed. While the popout or a window shows, runs in progress
  refresh every 15 seconds, and the Actions tab looks for new runs every
  minute.

The scope button in the header ("Involving you") switches the lists from
what involves you to everything in one repository, whoever opened it: open,
merged, and closed pull requests, open and closed issues, and the
repository's latest 30 runs. The Inbox tab leaves meanwhile, since
notifications are yours rather than the repository's; asking for it from
the mark's menu or a desktop notification goes back to your scope. The
picker offers the repositories you opened lately, your own (the Actions
repositories from the settings and your most recently pushed ones), and,
as you type, GitHub's repositories by that name (`owner/words` searches one
owner's); a full `owner/name` opens as typed. A repository's lists refresh
every two minutes while it shows. The popout remembers its scope, and a
window keeps the one it was opened with.

The Inbox and the pull request and issue lists load a page at a time (50
notifications, 30 results) and fetch the next as you scroll near the end,
with "30 of 129" at the bottom saying how far they go. A list you scrolled
stays scrolled through the background refresh, which fetches it again as
far as it was loaded (100 at a time) so no item slips between pages; the
Inbox does the same when new threads push others off its first page.
Refresh starts every list over.

The search field searches GitHub on the pull request and issue lists: the
words join the list's own search (Created, Assigned, ...) a moment after
typing stops, GitHub's search syntax included (`label:bug`,
`repo:owner/name`), and the results page in as you scroll. A search covers
every state, open or closed; in a picked repository, whose filters are
states, the filter chips dim and the search spans the whole tab. Loaded
rows that match show at once, and those GitHub's text search cannot find
(a number, a repository name) stay after its results. The notifications
API has no text search, so searching the Inbox loads its remaining pages
(up to 500 notifications) and filters those; the Actions tab filters the
runs it has.

## Pages

Opening a row shows its page. For a pull request: the description, then
the conversation in time order (comments, and reviews with their inline
threads: the file and line, the code under discussion, and every reply;
resolved threads start folded), then, as in GitHub's merge box, the
reviews, the checks (the first 100, with GitHub's verdict over all of them
saying when one past those failed), and what stands in the way of a merge.
For an issue:
its description and comments, and below the description its sub-issues
(with how many are done) and the issues it is blocked by or blocking. For
a run: its jobs (see Actions runs). A conversation longer than one request
brings (the newest 100 comments, reviews, and threads, 50 replies per
thread) says how much is left and links to it on GitHub; a long
description shows its beginning with "Show the whole post", and a long
code block its first 40 lines.

Beside the state, an issue shows the pull requests that will close it and
its parent, and a pull request the issues it closes, each colored by its
own state and opening in place. The assignees sit on the right: whoever
may assign gets "Assign yourself" when no one is, and a pen that opens the
repository's assignable people, narrowed on GitHub as a name is typed; each
click assigns or unassigns at once. The bell in the header says whether the
page's notifications reach you, and why (subscribed, watching the
repository, ignoring), and a click subscribes or unsubscribes, as
github.com's Notifications box does. Changing that needs the
`notifications` scope, which `gh auth login` does not ask for (the inbox
itself reads with `notifications` or `repo`, which it does); while the
token lacks it, the bell says so and a click runs
`gh auth refresh -s notifications` in a terminal.

The bar at the bottom of the page, as on GitHub, holds the comment box and
what fits the state: approve, merge (with the repository's default method),
mark ready, close, or reopen a pull request; close or reopen an issue;
re-run failed jobs, re-run all, or cancel a run. Merge, close, and cancel
take a second click to confirm. A merge insists on the head commit the page
showed at the first click (a commit pushed since makes it fail instead of
merging that too), and says "Merged" only once GitHub does: a repository
with a merge queue, or a merge waiting for its checks, answers "Queued to
merge" and the pull request stays in the open lists, and when GitHub cannot
be asked afterwards the toast says only that the merge was asked for. A
thread offers Reply (the comment box then
answers that thread) and Resolve or Unresolve conversation. A page offers
only what GitHub says you may do: close and reopen follow the issue's own
permission, merging and re-running or cancelling runs need write access to
the repository, and a locked conversation takes comments only from
collaborators; anything else is left out rather than shown disabled. With a
comment written (not a reply), close and reopen post it first ("Close with
comment"). What you type is kept for its page: going back, opening another
page, moving the page into a window, or closing the popout keeps the draft
until it is posted.

The text of a description or comment selects with the mouse, across its
paragraphs, lists, and code blocks, as in a browser: a drag selects, a
double click selects a word, Ctrl+A the whole post, and Ctrl+C copies it.
So a page scrolls by wheel, touchpad, touch, or its scroll bar rather than
by dragging with the mouse. The copy icon on each post and thread comment
copies its whole body as the Markdown it was written in. The Markdown shown
covers what GitHub bodies use: headings, paragraphs, emphasis, inline and
fenced code (kept exactly as written), links and bare URLs, images, `#123`
and `@user` references, bullet, numbered, nested, and task lists, quotes,
tables, and rules; HTML comments and layout tags outside code are dropped
for their text.

What is clickable on github.com is clickable here: people (authors,
assignees, reviewers, mentions), the repository, labels, branches, the
commit of a run, a pull request's size (its Files changed tab, in the
browser, like a pull request's other tabs), post times
(the comment), the workflow of a run, and a job (its page on GitHub). List
rows stay a single target (a click opens the page, the edge button opens it
on GitHub) so a click never lands on a link by accident. A pull request,
issue, or Actions run opens in the popout, whether it comes from a `#123`
reference, a pasted URL, or a pull request's check; Back returns through
every page opened this way. A label, or a link to a repository's issues or
pull requests with a query, opens that repository's list with the search
filled in (`label:bug`). Anything else opens in the browser, as long as it
is a web or mail link: bodies are written by anyone, and a link to a file or
another app does nothing but say so.

Keys: arrows move, Enter opens the page (on a page: opens it on GitHub),
Ctrl+Enter opens the row on GitHub, Tab switches tabs, Left and Right
switch filters, Delete marks a notification read, Ctrl+R refreshes, `c`
focuses the comment box, Ctrl+Enter posts, Escape goes back and then closes
(the popout; a window stays).

Right click on the mark opens its menu: each tab with its count, Open in a
window, Refresh, Open github.com, and Settings, which opens the DMS settings
on the Plugins page with this plugin's section expanded.
`dms ipc call widget openWith github <inbox|issues|prs|actions>` opens the
popout at a tab.

## Actions runs

A run page lists its jobs as GitHub's run page does; a job folds open into
its steps with their state and time, live while it runs (the page asks for
the run again every ten seconds), and each step of a finished job folds
open into its log, styled like github.com's (groups in bold, commands in
the accent, errors and warnings in their colors, the last 400 lines until
asked for all). A failed job opens with its failed step's log showing.
GitHub does not publish a job's log to its API while the job runs (its own
page streams it over a channel only the browser has), so a running job
shows its steps and a link to watch the log live on GitHub, and its log
arrives here once it finishes. The log is one request per job, split into
steps by the plugin, since gh no longer can. The split goes by time, and a
step with a name of its own right after a composite action can take one of
the action's lines when both fall in the same second; so the job says the
split is by time, and offers "Show the whole job log".

## Size and window

Drag any edge or corner of the popout that is not against the bar to resize
it; a double click on one of them goes back to the default size. The window
button in the header moves what is on screen (the tab, its filter, the
search, and an open page with its Back history and draft) into a floating
window of its own, titled after what it shows. A window stays open until it
is closed, resizes from its edges, and moves by its header; the mark keeps
opening the popout, so there can be as many windows as pop-outs, each
browsing on its own. The popout and window sizes, the popout's scope, the
recent repositories, and what was announced are kept as plugin state in
`~/.local/state/DankMaterialShell/plugins/github_state.json`.

## How it talks to GitHub

One background instance (the plugin's daemon) asks for everything, however
many bars show the mark.

| What | gh command |
|---|---|
| Lists, login, recently pushed repositories | `gh api graphql` with `queries/inbox.graphql` (operation `Inbox`), one request |
| The bar's counts while nothing is on screen | `gh api graphql` with `queries/inbox.graphql` (operation `Badge`) |
| One repository's lists | `gh api graphql` with `queries/inbox.graphql` (operation `Repository`), one request |
| Repositories by name, for the picker | `gh search repos` |
| The next page of a list, or a search | `gh api graphql` with `queries/inbox.graphql` (operation `Page`) |
| Unread notifications | `gh api notifications` (the newest 50), the next ones with `before=` the oldest loaded |
| Mark a notification read | `gh api -X PATCH notifications/threads/<id>` |
| Mark all as read | `gh api -X PUT notifications -f last_read_at=<newest>` |
| Desktop notifications | `notify-send` (no GitHub access) |
| Runs | `gh run list -R <repo>` per watched repository, or for the repository picked |
| A pull request's or an issue's page: the page, what you may change there, what it links to, relationships, subscription, reviews and inline threads, and the rendered HTML behind its images | `gh api graphql` with `queries/detail.graphql` (operation `PullRequest` or `Issue`), one request |
| A run's page | `gh run view`, and `queries/detail.graphql` (operation `Permission`, once per repository) for re-run and cancel |
| A finished job's log | `gh api --allow-escape-sequences repos/<owner>/<name>/actions/jobs/<id>/logs` |
| A linked `#N` (issue or pull request) | `gh api graphql` with `queries/inbox.graphql` (operation `Resolve`) |
| People who can be assigned | `gh api graphql` with `queries/assignees.graphql` |
| Assign or unassign | `gh issue edit` / `gh pr edit` with `--add-assignee` / `--remove-assignee` |
| Subscribe or unsubscribe | `gh api graphql` with `updateSubscription` (needs the `notifications` scope) |
| Reply to a thread | `gh api -X POST repos/<repo>/pulls/<n>/comments/<id>/replies` |
| Resolve or unresolve a thread | `gh api graphql` with `resolveReviewThread` / `unresolveReviewThread` |
| Changes | `gh pr review/merge/ready/close/reopen/comment`, `gh issue close/reopen/comment`, `gh run rerun/cancel` |

Images are the one thing loaded outside gh, and none carries a credential.
A body names an attachment by a github.com URL that only a signed-in
browser can open, so the page's request also brings its rendered HTML,
where GitHub hands out short-lived signed image URLs (external images come
through GitHub's own image proxy), and the plugin loads exactly those; an
image without such a URL stays a link. The profile pictures in post headers
are GitHub's public avatars (`avatars.githubusercontent.com/<login>`), with
the initial standing in when there is none.

## Staying within GitHub's limits

GitHub allows 5,000 REST requests and 5,000 GraphQL points an hour, shared
by everything that uses the same `gh` account. In the background, with no
popout or window showing, the plugin uses:

- the bar's counts, which also say which account gh is on: one GraphQL
  request of 1 point per refresh interval (5 minutes by default, 1 minute
  at the lowest);
- notifications: one REST request a minute, the pace GitHub's
  `X-Poll-Interval` asks for (the plugin follows it if GitHub asks for
  longer), sent with `If-Modified-Since`, so an unchanged inbox answers 304,
  which GitHub does not count. Only a changed inbox, a full answer at least
  every ten minutes, and each popout open (so threads read on github.com
  leave the inbox too) count: a few dozen requests an hour at most.

While the popout or a window shows, the lists refresh in full on the same
interval (one request of 2 points) and when they come on screen more than
20 seconds old, runs in progress poll every 15 seconds (only the
repositories with a running run), the Actions tab asks for new runs every
minute, and a picked repository costs one request (a few points) when it
opens and every two minutes while it shows, plus its runs. A comment, a reply, or a resolved
thread refreshes only its page; a change that moves an item between lists
(merge, close, reopen, approve, ready, assign) refreshes the lists too.

Search results trail a change by a few seconds, so an item you merge,
close, reopen, or approve leaves the lists it no longer belongs in right
away instead of waiting for the next refresh (approving leaves Review
requests only).

## Settings

Settings > Plugins > GitHub (or Settings in the mark's right-click menu):
what the bar counts, the unread dot, desktop notifications, the background
refresh interval (5 minutes by default), and the repositories the Actions
tab watches (the five most recently pushed repositories you own or work in
when the list is empty).

Dependencies: `gh`, and `notify-send` (libnotify) for desktop notifications;
without notify-send the widget works and says so when a notification would
have gone out. If `gh auth switch` changes the account, the plugin notices
on its next answer (at the latest on the next refresh interval), drops
everything it kept for the old account, answers still on their way
included, and starts over for the new one; a page on screen starts over
too, and a close waiting behind its comment does not go out as the new
account.

## Code

`GitHubLogic.js` holds the pure logic (what each list asks, how answers
become rows and pages, links, Markdown, job logs, what a change hides or
announces) and is tested directly under Node (`tests/github_plugin.bats`).
`GitHubData.qml` asks gh and keeps the answers; the same tests run it in a
headless Quickshell with gh scripted (`tests/support/github_data`), answers
in any order. `GitHubDaemon.qml` owns it, the background polls, the desktop
notifications, and the windows; `GitHubWidget.qml` is a bar's mark, menu,
and popout; `GitHubPanel.qml` the lists (which poll what they show while on
screen); and `GitHubDetail.qml` a page, with `GitHubPost.qml` (the
conversation) and `GitHubJobs.qml` (a run's jobs and logs).
