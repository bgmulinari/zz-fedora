import QtQuick
import qs.Common
import qs.Services
import qs.DCommon.Widgets
import "GitHubLogic.js" as Logic
import "GitHubMarkdown.js" as Markdown

// The pages past pull requests, issues, and runs, as github.com shows them
// (Logic.PAGE_KINDS): a repository's home (GitHubRepoView), a branch's
// history (GitHubCommitsView), one commit with its diff
// (GitHubCommitView), a repository's releases or one release
// (GitHubReleasesView), a file (GitHubFileView), and a person's or an
// organization's profile (GitHubProfileView). This page loads them, keeps their links in the
// popout where the popout has the page (Logic.parseLink), and gives the
// panel header what to say (header). Escape, Backspace, or Left goes back,
// Enter opens the page on GitHub. A history and a list of releases load
// their next page as the end nears.
Item {
    id: browsePage

    property var item: null
    property var github: null
    // True while the popout shows this page.
    property bool active: false

    signal back()
    signal editingFinished()
    signal closeRequested()
    // A page to open in place of this one (a pull request, a commit, a
    // repository, a profile).
    signal openItem(var item)
    // A link that is a repository's list, searched or not (its Issues,
    // a label), for the panel to show there.
    signal searchRequested(string repo, string tab, string terms)

    readonly property string kind: item ? String(item.kind || "") : ""
    readonly property string itemUrl: item ? String(item.url || "") : ""
    // The repository the page is in ("" on a profile), which a bare #123
    // in a body belongs to.
    readonly property string repo: item ? String(item.repo || "") : ""

    // The page's own load: Logic.repoHomeOf, historyOf, the commit's page
    // (GitHubData.loadCommit), releasesOf, releaseOf, fileOf, or ownerOf.
    property var detail: null
    property string loadError: ""
    property bool loading: false
    // A history's or a list's next page on its way, or why it failed.
    property bool loadingMore: false
    property string moreError: ""
    // Bumped whenever the page shows another item or account: an answer to
    // something asked for before leaves this page alone.
    property int generation: 0

    // A repository's or a profile's README, or a Markdown file's text as
    // it reads: { markdown, html, repo, linkBase, isPublic, branch }, false
    // when there is none, null while it comes.
    property var readme: null
    // Where the README's relative links start (GitHubMarkdown).
    readonly property string linkBase: readme ? readme.linkBase : ""
    // Original image or video URL -> what loads for it (GitHubMarkdown):
    // the README's, and the release notes' signed URLs.
    readonly property var images: Object.assign({}, readmeImages, notesImages)
    property var readmeImages: ({})
    property var notesImages: ({})
    // The release notes that name media (Logic.releaseRendering), whose
    // signed URLs are asked for again when one expired.
    property var rendering: []
    readonly property var mediaRenewal: Logic.renewals(20000)

    // How a commit message's code and links look (Markdown's style, as
    // GitHubMarkdown's), and the message in it.
    readonly property var richStyle: ({
            "link": Theme.primary,
            "codeFont": Theme.monoFontFamily,
            "codeSize": Theme.fontSizeSmall,
            "codeBackground": Theme.surfaceContainerHighest,
            "codeText": Theme.surfaceText,
            "keyBackground": Theme.surfaceContainerHigh,
            "dark": !Theme.isLightMode,
            "mark": Theme.withAlpha(Theme.warning, 0.25)
        })

    function messageHtml(text, inRepo) {
        return Markdown.commitMessageHtml(text, inRepo || repo, richStyle);
    }

    // The reaction picker open on this page (GitHubReactions), and the
    // chip whose reactors show (GitHubReactorsCard).
    property var openPicker: null
    property var reactorsChip: null
    property var reactorsShown: null
    readonly property bool editing: false

    // What the popout header shows (GitHubBrowseHeader): { avatar,
    // square, lead, title, badges: [{ text, tone }], line: [{ text, url,
    // mono, strong }] }.
    readonly property var header: Logic.pageHeader(item, detail)
    readonly property string headerTitle: header.lead || header.title
    readonly property string windowTitle: kind === "repo" ? repo : header.title + (repo ? " · " + repo : "")

    function showReactors(chip, subjectId, reaction) {
        reactorsChip = chip;
        github.loadReactors(subjectId, groups => {
            const group = groups ? groups[reaction.content] : null;
            if (reactorsChip !== chip || !group || group.people.length === 0)
                return;
            reactorsShown = {
                "emoji": reaction.emoji,
                "people": group.people,
                "total": group.total
            };
        }, browsePage);
    }

    function hideReactors(chip) {
        if (reactorsChip !== chip)
            return;
        reactorsChip = null;
        reactorsShown = null;
    }

    onItemChanged: start()

    function start() {
        generation++;
        detail = null;
        readme = null;
        readmeAsk = null;
        readmeImages = {};
        notesImages = {};
        rendering = [];
        mediaRenewal.reset();
        loadError = "";
        moreError = "";
        loadingMore = false;
        openPicker = null;
        reactorsChip = null;
        reactorsShown = null;
        flick.contentY = 0;
        reload();
    }

    // Whether an answer still belongs on this page.
    function stillHere() {
        const page = browsePage;
        const asked = generation;
        return () => Qt.isQtObject(page) && asked === page.generation;
    }

    // The page from GitHub again. A history or a list keeps the pages past
    // its first that were loaded, under the fresh first one; the same
    // answer leaves what shows as it is.
    function reload() {
        if (!item || !github)
            return;
        const here = stillHere();
        const asked = item;
        const take = (answer, error) => {
            if (!here())
                return false;
            loading = false;
            if (!answer) {
                loadError = Logic.failureText(error);
                return false;
            }
            loadError = "";
            return true;
        };
        loading = true;
        switch (asked.kind) {
        case "repo":
            github.loadRepoHome(asked.repo, (home, error) => {
                if (!take(home, error))
                    return;
                if (!github.sameJson(home, detail))
                    detail = home;
                loadReadme(asked.repo, "", !home.isPrivate, home.branch);
            }, browsePage);
            break;
        case "commits":
            github.loadCommits(asked, "", (history, error) => {
                if (take(history, error))
                    keepFirstPage(history, "commits", "sha");
            }, browsePage);
            break;
        case "commit":
            github.loadCommit(asked, (page, error) => {
                if (take(page, error) && !github.sameJson(page, detail))
                    detail = page;
            }, browsePage);
            break;
        case "releases":
            github.loadReleases(asked, "", (list, error) => {
                if (!take(list, error))
                    return;
                keepFirstPage(list, "releases", "id");
                showNotesMedia(false);
            }, browsePage);
            break;
        case "release":
            github.loadRelease(asked, (release, error) => {
                if (!take(release, error))
                    return;
                if (!github.sameJson(release, detail))
                    detail = release;
                showNotesMedia(false);
            }, browsePage);
            break;
        case "file":
            github.loadFile(asked, (file, error) => {
                if (!take(file, error))
                    return;
                if (!github.sameJson(file, detail))
                    detail = file;
                // Markdown reads as GitHub renders it, its pictures and
                // relative links from its folder at its ref.
                if (file.markdown && file.text !== null)
                    loadReadme(asked.repo, file.path, !file.isPrivate, file.ref);
            }, browsePage);
            break;
        case "user":
            github.loadOwner(asked.login, (profile, error) => {
                if (!take(profile, error))
                    return;
                if (!github.sameJson(profile, detail))
                    detail = profile;
                // A person's README is their own repository's; an
                // organization's, its .github repository's profile/README.md.
                // Either shows only while public.
                if (profile.isOrg)
                    loadReadme(profile.login + "/.github", "profile/README.md", true, "HEAD");
                else
                    loadReadme(profile.login + "/" + profile.login, "", true, "HEAD");
            }, browsePage);
            break;
        default:
            loading = false;
        }
    }

    // A fresh first page over what was loaded past it.
    function keepFirstPage(fresh, key, id) {
        const shown = detail && detail[key] ? detail[key] : [];
        const next = Object.assign({}, fresh);
        if (shown.length > fresh[key].length && detail.more !== undefined) {
            next[key] = Logic.appendNew(fresh[key], shown, id);
            next.more = detail.more;
            next.cursor = detail.cursor;
        }
        if (!github.sameJson(next, detail))
            detail = next;
    }

    // The next page of a history or of releases, when there is one.
    function loadMore() {
        if (!detail || !detail.more || loadingMore || loading || (kind !== "commits" && kind !== "releases"))
            return;
        const here = stillHere();
        const key = kind === "commits" ? "commits" : "releases";
        const id = kind === "commits" ? "sha" : "id";
        const done = (page, error) => {
            if (!here())
                return;
            loadingMore = false;
            if (!page) {
                moreError = Logic.failureText(error);
                return;
            }
            moreError = "";
            const next = Object.assign({}, detail);
            next[key] = Logic.appendNew(detail[key], page[key], id);
            next.more = page.more;
            next.cursor = page.cursor;
            detail = next;
            if (kind === "releases")
                showNotesMedia(false);
        };
        loadingMore = true;
        if (kind === "commits")
            github.loadCommits(item, detail.cursor, done, browsePage);
        else
            github.loadReleases(item, detail.cursor, done, browsePage);
    }

    // What the README was asked as, for its pictures' URLs again.
    property var readmeAsk: null

    // The README, and the URLs its pictures load from (Logic.readmeImages).
    function loadReadme(readmeRepo, path, isPublic, branch, done) {
        readmeAsk = {
            "repo": readmeRepo,
            "path": path,
            "isPublic": isPublic,
            "branch": branch
        };
        const here = stillHere();
        github.loadReadme(readmeRepo, path, answer => {
            if (!here())
                return;
            if (!answer) {
                readme = false;
                readmeImages = {};
            } else {
                const next = {
                    "markdown": answer.markdown,
                    "repo": readmeRepo,
                    "path": Logic.readmePath(answer.html),
                    "linkBase": Logic.readmeLinkBase(answer.html, readmeRepo, branch),
                    "url": Logic.repoUrl(readmeRepo) + "/blob/" + Logic.encodePath(branch || "HEAD") + "/" + Logic.encodePath(Logic.readmePath(answer.html))
                };
                if (!github.sameJson(next, readme))
                    readme = next;
                const found = Logic.readmeImages(answer.markdown, answer.html, readmeRepo, isPublic, branch);
                if (!github.sameJson(found, readmeImages))
                    readmeImages = found;
            }
            if (done)
                done();
        }, browsePage, kind === "file" ? branch : "");
    }

    // The signed URLs of the pictures and videos release notes name
    // (GitHubData.loadMedia, kept a few minutes); `fresh` asks again.
    function showNotesMedia(fresh, done) {
        const releases = kind === "release" ? (detail ? [detail] : []) : (detail ? detail.releases || [] : []);
        rendering = Logic.releaseRendering(releases);
        if (rendering.length === 0) {
            if (done)
                done();
            return;
        }
        const here = stillHere();
        github.loadMedia(rendering, (found, settled) => {
            if (!here())
                return;
            const next = Object.assign({}, notesImages, found);
            if (!github.sameJson(next, notesImages))
                notesImages = next;
            if (settled && done)
                done();
        }, browsePage, fresh);
    }

    // A picture whose signed URL expired asks for new ones (GitHubMarkdown):
    // the README's again, or the notes'.
    function refreshMedia(done) {
        mediaRenewal.ask(done, finished => {
            if (readme && readmeAsk)
                loadReadme(readmeAsk.repo, readmeAsk.path, readmeAsk.isPublic, readmeAsk.branch, finished);
            else
                showNotesMedia(true, finished);
        });
    }

    Connections {
        target: browsePage.github
        function onAccountSwitched() {
            browsePage.start();
        }
    }

    // ---------------------------------------------------------------- links

    // Every link of the page leads where it does on github.com: what the
    // popout has a page for opens here (a relative link from the README's
    // folder), a repository's lists in the panel, the rest in the browser.
    function openLink(url) {
        let target = String(url || "").trim();
        if (target === "")
            return;
        if (!/^[a-z][a-z0-9+.-]*:/i.test(target) && target.charAt(0) !== "#")
            target = Markdown.resolveUrl(target, repo, linkBase);
        const search = Logic.parseSearchLink(target, "issues");
        if (search) {
            searchRequested(search.repo, search.tab, search.terms);
            return;
        }
        const link = Logic.parseLink(target);
        if (!link || link.anchor) {
            openExternally(target);
            return;
        }
        if (Logic.isPageKind(link.kind)) {
            const page = Logic.pageItem(link);
            if (Logic.samePage(page, item))
                scrollToTop();
            else
                openItem(page);
            return;
        }
        const here = stillHere();
        loading = true;
        github.resolveLink(link, (resolved, error) => {
            if (!here())
                return;
            loading = false;
            if (resolved)
                openItem(resolved);
            else
                openExternally(target);
        }, browsePage);
    }

    // A repository's Issues, Pull requests, or Actions: its lists in the
    // panel.
    function openList(tab) {
        searchRequested(repo, tab, "");
    }

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

    // ----------------------------------------------------------------- keys

    function bodyKey(event) {
        if (handleKey(event))
            event.accepted = true;
    }

    function handleKey(event) {
        const control = event.modifiers & Qt.ControlModifier;
        if (event.key === Qt.Key_Escape && openPicker) {
            openPicker.picking = false;
            return true;
        }
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
        case Qt.Key_Home:
            scrollToTop();
            return true;
        case Qt.Key_End:
            flick.contentY = Math.max(flick.originY, flick.originY + flick.contentHeight - flick.height);
            return true;
        }
        return false;
    }

    // --------------------------------------------------------------- scroll

    function scrollToTop() {
        flick.contentY = flick.originY;
    }

    function scrollToItem(target) {
        const y = target.mapToItem(flick.contentItem, 0, 0).y - Theme.spacingS;
        flick.contentY = Logic.scrollClamp(y, flick.originY, flick.contentHeight, flick.height);
    }

    readonly property real viewY: flick.contentY

    function inView(target, top) {
        const y = target.mapToItem(flick.contentItem, 0, 0).y;
        return y + target.height > top && y < top + flick.height;
    }

    // Where the page was scrolled when the popout went away (the panel's
    // cameBack).
    property alias place: scrollPlace

    GitHubScrollPlace {
        id: scrollPlace
        target: flick
    }

    // ---------------------------------------------------------------- layout

    DFlickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: body.implicitHeight + Theme.spacingM
        clip: true
        // A mouse drag selects a body's text rather than dragging the page.
        acceptedButtons: Qt.NoButton

        // The next page of a history or of releases, as its end nears.
        onContentYChanged: {
            if (browsePage.reactorsChip)
                browsePage.hideReactors(browsePage.reactorsChip);
            if (contentHeight > height && contentY + height >= originY + contentHeight - height)
                browsePage.loadMore();
        }

        Column {
            id: body
            width: flick.width - Theme.spacingS
            spacing: Theme.spacingL

            StyledText {
                visible: text !== ""
                width: parent.width
                text: browsePage.loadError
                textFormat: Text.PlainText
                font.pixelSize: Theme.fontSizeSmall
                color: Theme.error
                wrapMode: Text.Wrap
            }

            Loader {
                width: parent.width
                active: !!browsePage.detail
                sourceComponent: ({
                        "repo": repoView,
                        "commits": commitsView,
                        "commit": commitView,
                        "releases": releasesView,
                        "release": releasesView,
                        "file": fileView,
                        "user": profileView
                    })[browsePage.kind] || null
            }
        }
    }

    Component {
        id: repoView

        GitHubRepoView {
            page: browsePage
        }
    }

    Component {
        id: commitsView

        GitHubCommitsView {
            page: browsePage
        }
    }

    Component {
        id: commitView

        GitHubCommitView {
            page: browsePage
        }
    }

    Component {
        id: releasesView

        GitHubReleasesView {
            page: browsePage
        }
    }

    Component {
        id: fileView

        GitHubFileView {
            page: browsePage
        }
    }

    Component {
        id: profileView

        GitHubProfileView {
            page: browsePage
        }
    }

    // Until the page's first answer, it says what it is waiting for.
    Column {
        anchors.centerIn: flick
        width: flick.width - Theme.spacingXL * 2
        visible: browsePage.loading && !browsePage.detail && browsePage.loadError === ""
        spacing: Theme.spacingS

        GitHubOcticon {
            anchors.horizontalCenter: parent.horizontalCenter
            name: ({
                    "repo": "repo",
                    "commits": "history",
                    "commit": "git-commit",
                    "releases": "tag",
                    "release": "tag",
                    "file": "file",
                    "user": "people"
                })[browsePage.kind] || "repo"
            size: 32
            color: Theme.surfaceVariantText
        }

        StyledText {
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: Logic.pageLoadingText(browsePage.item)
            font.pixelSize: Theme.fontSizeMedium
            color: Theme.surfaceVariantText
        }
    }

    GitHubScrollButtons {
        anchors.right: flick.right
        anchors.rightMargin: Theme.spacingL
        anchors.bottom: flick.bottom
        anchors.bottomMargin: Theme.spacingS
        z: 10
        target: flick
    }

    GitHubReactorsCard {
        page: browsePage
        z: 50
    }

    // While a reaction picker is open, a press outside it closes it and
    // goes on to whatever is under it.
    MouseArea {
        id: pickerCatcher
        anchors.fill: parent
        z: 100
        enabled: !!browsePage.openPicker
        // No cursor of its own (see GitHubPanel's suggestions catcher).
        cursorShape: undefined
        acceptedButtons: Qt.AllButtons
        onPressed: mouse => {
            const picker = browsePage.openPicker;
            if (picker && !picker.holds(pickerCatcher, mouse.x, mouse.y))
                picker.picking = false;
            mouse.accepted = false;
        }
    }
}
