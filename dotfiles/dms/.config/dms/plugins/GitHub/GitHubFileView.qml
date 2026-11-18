import QtQuick
import qs.Common
import qs.DCommon.Widgets
import "GitHubLogic.js" as Logic

// A file as github.com shows it (Logic.fileOf): the last commit that
// changed it, with its history (a page here), over a box headed by what it
// is (its lines, the ones with code, and its size) and ways to copy it or
// open it raw. Markdown reads as it renders (the page's readme, its
// pictures and relative links from its folder), or as its code; code shows
// with its line numbers and colors (GitHubCodeView); a picture shows while
// the repository is public; anything else says why it is not shown. A
// folder (a blob link to one) opens on GitHub.
Column {
    id: view

    property var page: null
    readonly property var file: page ? page.detail : null
    readonly property var item: page ? page.item : null
    // Markdown as it reads, or (Code, ?plain=1) as written.
    property bool preview: !(item && item.plain)
    readonly property bool reads: !!file && file.markdown && file.text !== null && preview && page.readme !== false

    width: parent ? parent.width : 0
    spacing: Theme.spacingM

    // The marked lines come into view once they are drawn: the page grows
    // a moment after the code does, so it tries a few times.
    property bool marked: false

    function showMark() {
        if (marked || !item || item.line <= 0 || !codeView.visible || !codeView.mark.visible)
            return;
        marked = true;
        markTries.tries = 0;
        markTries.start();
    }

    Timer {
        id: markTries
        property int tries: 0
        interval: 100
        repeat: true
        onTriggered: {
            view.page.scrollToItem(codeView.mark);
            if (++tries >= 10 || view.page.inView(codeView.mark, view.page.viewY))
                stop();
        }
    }

    // ---------- A folder ----------
    GitHubLinkRow {
        visible: !!view.file && view.file.folder
        icon: "folder_open"
        text: view.file ? view.file.path + " is a folder: open it on GitHub" : ""
        action: () => view.page.openExternally(view.file.url)
    }

    // ---------- The last commit ----------
    Rectangle {
        visible: !!view.file && !!view.file.commit
        width: parent.width
        height: 44
        radius: Theme.cornerRadius
        color: Theme.withAlpha(Theme.surfaceText, 0.05)
        border.width: 1
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.45)

        GitHubCommitRow {
            anchors.left: parent.left
            anchors.right: history.left
            anchors.verticalCenter: parent.verticalCenter
            page: view.page
            commit: view.file ? view.file.commit : null
            compact: true
        }

        // The file's history, a page here.
        Row {
            id: history
            anchors.right: parent.right
            anchors.rightMargin: Theme.spacingM
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.spacingXS

            GitHubOcticon {
                anchors.verticalCenter: parent.verticalCenter
                name: "history"
                size: 14
                color: Theme.surfaceVariantText
            }

            GitHubLinkText {
                anchors.verticalCenter: parent.verticalCenter
                page: view.page
                text: "History"
                url: view.file ? view.file.historyUrl : ""
                font.pixelSize: Theme.fontSizeSmall
                font.weight: Font.DemiBold
                color: Theme.surfaceText
            }
        }
    }

    // ---------- The file ----------
    Rectangle {
        visible: !!view.file && !view.file.folder
        width: parent.width
        height: fileColumn.implicitHeight
        radius: Theme.cornerRadius
        color: "transparent"
        border.width: 1
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.45)
        clip: true

        Column {
            id: fileColumn
            width: parent.width

            // Preview or Code (Markdown), what the file is, and its buttons.
            Item {
                width: parent.width
                height: 40

                Row {
                    id: lead
                    anchors.left: parent.left
                    anchors.leftMargin: Theme.spacingS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: Theme.spacingS

                    Row {
                        visible: !!view.file && view.file.markdown && view.file.text !== null
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0

                        Toggle {
                            text: "Preview"
                            chosen: view.preview
                            onPicked: view.preview = true
                        }

                        Toggle {
                            text: "Code"
                            chosen: !view.preview
                            onPicked: view.preview = false
                        }
                    }

                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, view.width - x - tools.width - Theme.spacingL * 2)
                        text: {
                            const f = view.file;
                            if (!f)
                                return "";
                            const size = Logic.fileSize(f.size);
                            return f.text !== null && f.lines > 0 ? Logic.plural(f.lines, "line") + " (" + f.loc + " loc) · " + size : size;
                        }
                        textFormat: Text.PlainText
                        font.pixelSize: Theme.fontSizeSmall
                        color: Theme.surfaceVariantText
                        wrapMode: Text.NoWrap
                        elide: Text.ElideRight
                    }
                }

                Row {
                    id: tools
                    anchors.right: parent.right
                    anchors.rightMargin: Theme.spacingXS
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 2

                    GitHubCopyButton {
                        visible: !!view.file && view.file.text !== null && view.file.text !== ""
                        anchors.verticalCenter: parent.verticalCenter
                        github: view.page ? view.page.github : null
                        copyText: view.file && view.file.text !== null ? view.file.text : ""
                        toast: view.file ? "Copied " + view.file.name : ""
                        tooltipText: "Copy the file's contents"
                    }

                    DActionButton {
                        anchors.verticalCenter: parent.verticalCenter
                        buttonSize: 24
                        iconSize: 14
                        iconName: "description"
                        iconColor: Theme.surfaceVariantText
                        tooltipText: "View it raw on GitHub"
                        onClicked: view.page.openExternally(view.file.rawUrl)
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: Theme.withAlpha(Theme.outlineVariant, 0.45)
                }
            }

            // Markdown as it reads.
            Item {
                visible: view.reads
                width: parent.width
                height: view.page && view.page.readme ? markdown.implicitHeight + Theme.spacingL * 2 : 48

                StyledText {
                    visible: !!view.page && !view.page.readme
                    anchors.centerIn: parent
                    text: "Loading " + (view.file ? view.file.name : "") + "…"
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                }

                GitHubMarkdown {
                    id: markdown
                    visible: !!view.page && !!view.page.readme
                    x: Theme.spacingL
                    y: Theme.spacingL
                    width: parent.width - Theme.spacingL * 2
                    page: view.page
                    repo: view.file ? view.file.repo : ""
                    source: view.page && view.page.readme ? view.page.readme.markdown : ""
                }
            }

            // Code, with its line numbers.
            GitHubCodeView {
                id: codeView
                visible: !!view.file && view.file.text !== null && view.file.text !== "" && !view.reads
                page: view.page
                text: view.file && view.file.text !== null ? view.file.text : ""
                fileName: view.file ? view.file.name : ""
                line: view.item ? view.item.line : 0
                lineEnd: view.item ? view.item.lineEnd : 0
                onHeightChanged: view.showMark()
                onVisibleChanged: view.showMark()
            }

            // A picture.
            Item {
                visible: !!view.file && view.file.imageUrl !== ""
                width: parent.width
                height: Math.min(picture.status === Image.Ready ? picture.paintedHeight : 120, 1200) + Theme.spacingL * 2

                Rectangle {
                    anchors.centerIn: picture
                    width: picture.paintedWidth
                    height: picture.paintedHeight
                    color: "transparent"
                    border.width: 1
                    border.color: Theme.withAlpha(Theme.outlineVariant, 0.45)
                }

                Image {
                    id: picture
                    x: Theme.spacingL
                    y: Theme.spacingL
                    width: parent.width - Theme.spacingL * 2
                    height: Math.min(status === Image.Ready ? Math.min(sourceSize.height, width * sourceSize.height / Math.max(1, sourceSize.width)) : 120, 1200)
                    source: view.file ? view.file.imageUrl : ""
                    fillMode: Image.PreserveAspectFit
                    horizontalAlignment: Image.AlignHCenter
                    asynchronous: true
                    cache: true
                    smooth: true
                    mipmap: true
                }

                DSpinner {
                    anchors.centerIn: parent
                    visible: picture.status === Image.Loading
                    size: 22
                }
            }

            // Why nothing shows.
            Column {
                readonly property string why: {
                    const f = view.file;
                    if (!f || f.folder || f.imageUrl !== "")
                        return "";
                    if (f.image)
                        return "This picture is in a private repository, which shows it on GitHub.";
                    if (f.truncated)
                        return "This file is too large to show here.";
                    if (f.binary || f.text === null)
                        return "This is a binary file, which GitHub does not show as text.";
                    if (f.text === "")
                        return "This file is empty.";
                    return "";
                }
                visible: why !== ""
                width: parent.width
                padding: Theme.spacingM
                spacing: Theme.spacingS

                StyledText {
                    width: parent.width - Theme.spacingM * 2
                    text: parent.why
                    textFormat: Text.PlainText
                    font.pixelSize: Theme.fontSizeSmall
                    color: Theme.surfaceVariantText
                    wrapMode: Text.Wrap
                }

                GitHubLinkText {
                    visible: !!view.file && view.file.size > 0
                    page: view.page
                    text: "View it raw on GitHub"
                    url: view.file ? view.file.rawUrl : ""
                    external: true
                    font.pixelSize: Theme.fontSizeSmall
                    font.weight: Font.DemiBold
                    color: Theme.primary
                }
            }
        }
    }

    // One of Preview and Code, as github.com's segmented buttons.
    component Toggle: Rectangle {
        id: toggle

        property string text: ""
        property bool chosen: false
        signal picked()

        width: toggleText.implicitWidth + Theme.spacingM * 2
        height: 26
        radius: Theme.cornerRadius / 2
        color: chosen ? Theme.withAlpha(Theme.surfaceText, 0.1) : (toggleArea.containsMouse ? Theme.withAlpha(Theme.surfaceText, 0.05) : "transparent")
        border.width: chosen ? 1 : 0
        border.color: Theme.withAlpha(Theme.outlineVariant, 0.6)

        StyledText {
            id: toggleText
            anchors.centerIn: parent
            text: toggle.text
            font.pixelSize: Theme.fontSizeSmall
            font.weight: toggle.chosen ? Font.DemiBold : Font.Normal
            color: toggle.chosen ? Theme.surfaceText : Theme.surfaceVariantText
        }

        MouseArea {
            id: toggleArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: toggle.picked()
        }
    }
}
