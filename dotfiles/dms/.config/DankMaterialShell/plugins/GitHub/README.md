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

- **Inbox**: github.com's notifications inbox, every thread not marked
  done, read or unread; an unread one has a dot and a bold title, and the
  All / Unread toggle above the list shows only those. The filters are
  GitHub's default ones: All, Assigned, Participating,
  Mentioned, Team mentioned, and Review requested, each counting what is
  unread in it. A row shows its subject's state (open, draft, merged,
  closed, as GitHub colors it), its repository and author, and on the
  right why it came and when; under the pointer, Done, Mark as read, and
  Unsubscribe take their place. Opening one reads it: a pull request or an
  issue opens its page here, anything else (a release, a commit, a
  discussion) the browser. Opening a pull request or an issue from
  anywhere also reads its notification, as a visit to the page does.

  Each row has a checkbox, and Select all checks the rows shown; with rows
  checked, the bar above the list offers Done, Mark as read, and
  Unsubscribe for all of them. With every row of the unfiltered inbox
  checked, Mark as read becomes GitHub's Mark all as read, which reads the
  threads past the loaded pages too and cannot be taken back, so it asks
  for a second click (or Ctrl+I) first. Done removes a thread from the
  inbox until something new happens in it; Unsubscribe also ignores it, a
  watched repository's thread included, until you are mentioned or comment
  again. GitHub's API has no Saved or Done lists and cannot mark a thread
  unread, so those stay on github.com. The Inbox count and the unread
  threads refresh every minute, whatever the lists' refresh interval, and
  an inbox on screen follows at once when they change.

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
merged, and closed pull requests, open and closed issues, the
repository's latest 30 runs, and your notifications from it (as
github.com's Repositories filter shows them). Asking for the Inbox from the
mark's menu or a desktop notification goes back to your scope, whose
unread notifications those count. The picker offers the repositories you
opened lately, your own (the Actions repositories from the settings and
your most recently pushed ones), and, as you type, GitHub's repositories by
that name (`owner/words` searches one owner's); a full `owner/name` opens
as typed. A repository's lists refresh
every two minutes while it shows. The popout remembers its scope, and a
window keeps the one it was opened with.

The Inbox and the pull request and issue lists load a page at a time (50
notifications, 30 results) and fetch the next as you scroll near the end,
with "30 of 129" at the bottom saying how far they go. A list you scrolled
stays scrolled through the background refresh, which fetches it again as
far as it was loaded (100 at a time, 50 for the Inbox) so no item slips
between pages. Refresh starts every list over.

The search field searches GitHub on the pull request and issue lists: the
words join the list's own search (Created, Assigned, ...) a moment after
typing stops, GitHub's search syntax included (`label:bug`,
`repo:owner/name`), and the results page in as you scroll. A search covers
every state, open or closed; in a picked repository, whose filters are
states, the filter chips dim and the search spans the whole tab. Loaded
rows that match show at once, and those GitHub's text search cannot find
(a number, a repository name) stay after its results. The Inbox filters as
github.com's does, with its qualifiers: `is:unread`, `is:read`, `is:pr`
(or `is:issue`, `is:issue-or-pull-request`, `is:release`,
`is:discussion`, `is:commit`, `is:check-suite`, ...), `reason:assign`
(`author`, `comment`, `mention`, `team-mention`, `review-requested`,
`participating`, ...), `repo:owner/name`, `org:owner`, and `author:login`
(an app by its name, its bot's login, or `app/name`); a qualifier given
twice matches either value, and words match the rows' text, which
github.com's inbox cannot search. The notifications API has no search of
its own, so filtering the Inbox loads its remaining pages (up to 500
notifications, a search typed while the Inbox still loads included) and
filters those; the Actions tab filters the runs it has.

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

Every post (the description, a comment, a review with a summary, and each
comment of a review thread) shows its reactions under it as github.com
does: a chip per reaction with its count, outlined where one is yours. A
click on a chip adds or takes back yours, and the smiley opens GitHub's
eight reactions (a click elsewhere or Escape closes them). Resting the
pointer on a chip lists who gave it, the first ten with their names and
how many more, as github.com's hover card does. The change shows at once
and comes back off if GitHub refuses it (a locked conversation takes
reactions only from collaborators, and the smiley is left out where you may
not react).

On a page, the popout's header is the page's, as github.com's sticky
header: the number (a click opens the page on GitHub, as Enter does) with
the state under it, and beside them the title (wrapped to three lines, the
header growing with it; a click on a longer title shows it whole, and
otherwise goes back up) and who opened a pull request with its branches
(base ← head), who opened an issue, or how a run started. Under it, the
page adds what the header leaves out: the repository, the comments, a pull
request's commits and size, what it closes or belongs to, the assignees,
and the labels. Once a page is scrolled more than half its height away
from its top or its end, a button in its lower right corner jumps there.

The text of a description or comment selects with the mouse, across its
paragraphs, lists, and code blocks, as in a browser: a drag selects, a
double click selects a word, Ctrl+A the whole post, and Ctrl+C copies it.
So a page scrolls by wheel, touchpad, touch, or its scroll bar rather than
by dragging with the mouse. The copy icon on each post and thread comment
copies its whole body as the Markdown it was written in.

The Markdown shows as github.com shows it in issues, pull requests, and
comments, sized and spaced after its stylesheet:

- Blocks: headings (the two largest ruled underneath), paragraphs with
  their line breaks, quotes, and the alerts (`> [!NOTE]`, `[!TIP]`,
  `[!IMPORTANT]`, `[!WARNING]`, `[!CAUTION]`, in github.com's colors)
  holding blocks of their own. Bullet, numbered, and task lists whose
  items hold blocks too (bullets turning to circles and squares, numbers
  to roman numerals and letters as lists nest). Tables with column
  alignment, a bold header, striped rows, and pictures in cells. Rules,
  lines of images at the width the body gives them (GIFs and other images
  GitHub marks as animated playing on a loop while in view: see How it
  talks to GitHub), video attachments in a box named after the file with
  a player (muted at first, as there, loading nothing until play is
  pressed, and pausing once its box closes or the page leaves the screen),
  footnotes, and collapsible sections (`<details>`: closed behind their
  summary unless marked open, a click opening or closing them, what they
  hold built only once open).
- Code: fenced and indented (in a quote or a list item too), kept exactly
  as written and colored by its language with github.com's theme (through
  `kf6-syntax-highlighting`'s QML module; without it code stays one
  color). Diffs color their lines,
  a review's `suggestion` says it is a suggested change, and Mermaid,
  GeoJSON, TopoJSON, and STL blocks, which github.com draws, show as their
  source. A copy button shows over a code block on hover.
- Inline: emphasis (`**` `__` `*` `_` `~~` `~`), code spans (with a swatch
  after a color), links (inline, reference, autolinks, bare URLs, `www.`
  and mail addresses), math (`$...$`, `$$...$$`, and `math` blocks, set
  as text: Greek letters, operators, fractions, roots, and scripts),
  `:emoji:` shortcodes, backslash escapes, and HTML entities. `@user` and
  `@org/team` mentions and `#123`, `GH-123`, `owner/repo#123`,
  `owner/repo@sha`, and full commit SHAs link to GitHub, and links to
  GitHub read as github.com shortens them (`#12 (comment)`, a commit's
  short SHA).
- HTML as GitHub lets it through: `<b>`, `<i>`, `<s>`, `<ins>`, `<sub>`,
  `<sup>`, `<small>`, `<mark>`, `<kbd>` (a keycap), `<code>`, `<q>`, and
  `<a href>` keep their meaning; `<img>` (its width kept, a `<picture>`
  read as its image for the shell's dark or light scheme), `<br>`, `<pre>`, `<h1>`-`<h6>`, `<hr>`, `<table>`,
  `<blockquote>`, and lists are the Markdown they stand for; `<p align>`,
  `<div align>`, and `<center>` center or right-align what they hold.
  Comments and other tags drop for their text, outside code.

A body is written by anyone, so nothing it writes reaches the page as
markup: its text is escaped wherever it shows (math and table cells
included), and only what the plugin writes is rich text. TeX it cannot
read shows as far as it reads, never keeping a post from showing.

In-page links (`#section`, a footnote and its way back) scroll to what
they name, opening the sections around it.

What is clickable on github.com is clickable here: people (authors,
assignees, reviewers, mentions), the repository, labels, branches, the
commit of a run, a pull request's size and commit count (its Files
changed and Commits tabs, in the browser, like a pull request's other
tabs), post times
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
switch filters, Ctrl+R refreshes, `c` focuses the comment box, Ctrl+Enter
posts, Escape goes back and then closes (the popout; a window stays). In
the Inbox, Space checks the row (Ctrl+Space while the search has text),
and Delete marks the checked threads done, or the row when none is checked
(github.com's E; the search field keeps Delete while there is text after
the cursor); Ctrl+I marks them read and Ctrl+M unsubscribes (github.com's
Shift+I and Shift+M, which would type into the search here).

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
| Unread notifications (the dot, the counts, desktop notifications) | `gh api notifications` (the newest 50) |
| The Inbox | `gh api notifications?all=true` (or `repos/<owner>/<name>/notifications?all=true`), 50 at a time, the next ones with `before=` the oldest loaded |
| What each Inbox subject is now (state, author) | `gh api graphql` with one `issueOrPullRequest` per subject, each repository once, per page |
| Mark a notification read | `gh api -X PATCH notifications/threads/<id>` |
| Mark all as read | `gh api -X PUT notifications -f last_read_at=<newest>` (or `repos/<owner>/<name>/notifications`) |
| Mark as done | `gh api -X DELETE notifications/threads/<id>` |
| Unsubscribe | `gh api -X PUT notifications/threads/<id>/subscription -F ignored=true`, then mark as done |
| Desktop notifications | `notify-send` (no GitHub access) |
| Runs | `gh run list -R <repo>` per watched repository, or for the repository picked |
| A pull request's or an issue's page: the page, what you may change there, what it links to, relationships, subscription, reviews and inline threads, and every post's reactions | `gh api graphql` with `queries/detail.graphql` (operation `PullRequest` or `Issue`), one request |
| The signed URLs of a page's images and videos (and which images move) | `gh api graphql` with `queries/detail.graphql` (operation `Rendered`), only for the posts whose Markdown names an image or a video, kept three minutes |raphql` with `queries/detail.graphql` (operation `PullRequest` or `Issue`), one request |
| A run's page | `gh run view`, and `queries/detail.graphql` (operation `Permission`, once per repository) for re-run and cancel |
| A finished job's log | `gh api --allow-escape-sequences repos/<owner>/<name>/actions/jobs/<id>/logs` |
| A linked `#N` (issue or pull request) | `gh api graphql` with `queries/inbox.graphql` (operation `Resolve`) |
| People who can be assigned | `gh api graphql` with `queries/assignees.graphql` |
| Assign or unassign | `gh issue edit` / `gh pr edit` with `--add-assignee` / `--remove-assignee` |
| Subscribe or unsubscribe | `gh api graphql` with `updateSubscription` (needs the `notifications` scope) |
| Who reacted (asked for when the pointer rests on a reaction, kept a minute) | `gh api graphql` with `queries/detail.graphql` (operation `Reactors`) |
| Add or remove a reaction | `gh api graphql` with `addReaction` / `removeReaction` |
| Reply to a thread | `gh api -X POST repos/<repo>/pulls/<n>/comments/<id>/replies` |
| Resolve or unresolve a thread | `gh api graphql` with `resolveReviewThread` / `unresolveReviewThread` |
| Changes | `gh pr review/merge/ready/close/reopen/comment`, `gh issue close/reopen/comment`, `gh run rerun/cancel` |

Images and videos are the one thing loaded outside gh, and none carries a
credential. A body names an attachment by a github.com URL that only a
signed-in browser can open, so the plugin asks for the rendered HTML of the
posts that name images or videos (right after the page, which shows its
text meanwhile; rendering every body would slow each page by about half a
second), where GitHub hands out signed URLs that last five minutes
(external images come through GitHub's own image proxy), and loads exactly
those; one without such a URL stays a link. A page opened again within
three minutes reuses them, so its pictures come from the cache, and a
picture or a video whose URL expired before it loaded asks for new ones
(one request for everything that asks meanwhile). A picture of pixels (a
screenshot) decodes no wider than 1,600 pixels; a drawing (an SVG badge)
keeps its own size.

Qt plays an animated image (a GIF) from its download only once, so each
one GitHub marks as animated is copied, from its signed URL, into the
session's runtime directory (in memory), and plays on a loop from there.
curl makes the copy, the one download without gh: it is handed the signed
URL and nothing else (no header, no credential, HTTPS only) and writes
straight to the file, so the shell never holds the download. The copies
are bounded: none larger than 40 MB (a response that does not say its size
included) or slower than a minute, two at a time, 160 MB in all (the least
lately shown go first), cleared when the shell starts, and one that failed
is not tried again for ten minutes. A picture plays only while it is in
view.

The profile pictures in post headers are GitHub's public avatars
(`avatars.githubusercontent.com/<login>`), with the initial standing in
when there is none.

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
20 seconds old, the Inbox on screen when it comes on screen, every two
minutes, and when the unread notifications change (one REST request for
its newest page, and one GraphQL request of about a point for the subjects
that changed), runs in progress poll every 15 seconds (only the
repositories with a running run), the Actions tab asks for new runs every
minute, and a picked repository costs one request (a few points) when it
opens and every two minutes while it shows, plus its runs. A comment, a
reply, or a resolved thread refreshes only its page; a change that moves
an item between lists (merge, close, reopen, approve, ready, assign)
refreshes the lists too.

Search results trail a change by a few seconds, so an item you merge,
close, reopen, or approve leaves the lists it no longer belongs in right
away instead of waiting for the next refresh (approving leaves Review
requests only).

## Settings

Settings > Plugins > GitHub (or Settings in the mark's right-click menu):
what the bar counts, the unread dot, desktop notifications, the background
refresh interval (5 minutes by default), how long the popout keeps your
place, and the repositories the Actions tab watches (the five most recently
pushed repositories you own or work in when the list is empty).

The popout keeps your place for a while (5 minutes by default): dismissed
by a click elsewhere and opened again from the bar within that time, it
shows what it showed, the issue, pull request, or run scrolled where it was
(brought up to date if it has been away more than 20 seconds), the tab, the
search, and any draft. Later, or opened for something in particular (a tab
from the bar's menu or IPC, a desktop notification), it starts over at the
list.

Dependencies: `gh`, `notify-send` (libnotify) for desktop notifications,
`kf6-syntax-highlighting` for colored code, `qt6-qtmultimedia` for video
attachments, and `curl` for animated images; without notify-send the
widget works and says so when a notification would have gone out, without
syntax highlighting code shows in one color, without Qt Multimedia a video
is a link to GitHub, and without curl an animated image shows still.

If `gh auth switch` changes the account, the plugin notices on its next
answer (at the latest on the next refresh interval), drops
everything it kept for the old account, answers still on their way
included, and starts over for the new one; a page on screen starts over
too, and a close waiting behind its comment does not go out as the new
account.

## Code

`GitHubLogic.js` holds the pure logic (what each list asks, how answers
become rows and pages, links, job logs, what a change hides or announces)
and `GitHubMarkdown.js` reads the bodies; both are tested directly under
Node (`tests/github_plugin.bats`). `GitHubEmoji.js` maps GitHub's emoji
shortcodes to their characters (`tests/support/github_emoji.js`
regenerates it from `gh api emojis`). `GitHubData.qml` asks gh and keeps
the answers; the same tests run it in a headless Quickshell with gh
scripted (`tests/support/github_data`), answers in any order.
`GitHubDaemon.qml` owns it, the background polls, the desktop
notifications, and the windows; `GitHubWidget.qml` is a bar's mark, menu,
and popout; `GitHubPanel.qml` the lists (which poll what they show while on
screen); and `GitHubDetail.qml` a page, with `GitHubPost.qml` (the
conversation, its bodies drawn by `GitHubMarkdown.qml`, their code colored
by `GitHubHighlighter.qml` and a video played by `GitHubVideo.qml`) and
`GitHubJobs.qml` (a run's jobs and logs). `GitHubScrollPlace.qml` keeps
where the list and a page were scrolled while the popout is away.
