import QtQuick
import QtMultimedia
import qs.Common
import qs.Widgets

// A video attachment as github.com shows one: a box named after its file,
// open until its name is clicked, holding a player that starts muted.
// Nothing loads until play is pressed, and it pauses once it is out of
// sight (its box closed, or the page gone from screen). GitHubMarkdown
// loads this file on its own, so a shell without Qt Multimedia still shows
// the rest of a body (and the video as a link).
Item {
    id: video

    // What plays: the signed URL GitHub rendered for the attachment, which
    // the page renews when one expired before it played.
    property string source: ""
    property string name: ""
    // Whether the page it is on shows.
    property bool active: true
    // Opens the attachment on GitHub, for a video that does not play here.
    property var openOutside: null
    // Asks the page for new signed URLs: renew(done), done once the page
    // has them, or has none newer.
    property var renew: null
    readonly property bool takesClicks: true

    property bool open: true
    property bool started: false
    property bool failed: false
    // Whether the viewer wants it playing (what a pause out of sight
    // leaves as it was).
    property bool wanted: false
    // Whether the page was asked for a new URL after a failure, and whether
    // the player waits for it.
    property bool renewed: false
    property bool renewing: false
    readonly property bool playing: player.playbackState === MediaPlayer.PlayingState
    readonly property bool seen: visible && open && active
    readonly property real ratio: output.sourceRect.width > 0 ? output.sourceRect.height / output.sourceRect.width : 9 / 16

    implicitHeight: frame.height

    onSeenChanged: {
        if (!seen)
            player.pause();
    }

    // A URL that comes after the player gave up (another renewal brought
    // it) lets play be pressed again.
    onSourceChanged: {
        if (failed && !renewing) {
            failed = false;
            renewed = false;
            started = false;
        }
    }

    function toggle() {
        if (failed || renewing)
            return;
        if (!started) {
            started = true;
            player.source = source;
        }
        wanted = !playing;
        if (wanted)
            player.play();
        else
            player.pause();
    }

    // Most likely an expired signature: the page is asked for a new URL,
    // once. The player takes a newer one up (playing on if the viewer
    // wants it and it shows); with none, the video is a link to GitHub.
    function renewSource() {
        const tried = String(player.source);
        renewed = true;
        renewing = true;
        renew(() => {
            if (!Qt.isQtObject(video) || !renewing)
                return;
            renewing = false;
            if (source === "" || source === tried) {
                failed = true;
                return;
            }
            player.source = source;
            if (wanted && seen)
                player.play();
        });
    }

    function clock(ms) {
        const seconds = Math.max(0, Math.floor(ms / 1000));
        return Math.floor(seconds / 60) + ":" + String(seconds % 60).padStart(2, "0");
    }

    MediaPlayer {
        id: player
        videoOutput: output
        audioOutput: AudioOutput {
            id: audio
            muted: true
        }
        onErrorOccurred: {
            if (!video.renewed && typeof video.renew === "function")
                video.renewSource();
            else
                video.failed = true;
        }
    }

    Rectangle {
        id: frame
        width: parent.width
        height: header.height + (video.open ? screen.height + controls.height : 0)
        radius: Theme.cornerRadius
        color: "transparent"
        border.width: 1
        border.color: Theme.outlineVariant
        clip: true

        // The file's name, which opens and closes the box.
        Item {
            id: header
            width: parent.width
            height: 34

            DankIcon {
                id: camera
                x: Theme.spacingM
                anchors.verticalCenter: parent.verticalCenter
                name: "videocam"
                size: Theme.iconSizeSmall
                color: Theme.surfaceVariantText
            }

            StyledText {
                id: title
                anchors.left: camera.right
                anchors.leftMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                width: Math.min(implicitWidth, parent.width - x - 40)
                text: video.name || "Video"
                font.pixelSize: Theme.fontSizeMedium
                color: Theme.surfaceText
                elide: Text.ElideMiddle
            }

            DankIcon {
                anchors.left: title.right
                anchors.verticalCenter: parent.verticalCenter
                name: "arrow_drop_down"
                size: Theme.iconSizeSmall
                color: Theme.surfaceVariantText
                rotation: video.open ? 0 : -90
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: video.open = !video.open
            }
        }

        Rectangle {
            id: screen
            y: header.height
            visible: video.open
            width: parent.width
            height: Math.round(Math.min(width * video.ratio, 420))
            color: "black"

            Rectangle {
                width: parent.width
                height: 1
                color: Theme.outlineVariant
            }

            VideoOutput {
                id: output
                anchors.fill: parent
                fillMode: VideoOutput.PreserveAspectFit
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: video.toggle()
            }

            // Play, until it plays.
            Rectangle {
                anchors.centerIn: parent
                visible: !video.playing && !video.failed && !buffering.visible
                width: 56
                height: 56
                radius: 28
                color: Qt.rgba(1, 1, 1, 0.2)
                border.width: 1
                border.color: Qt.rgba(1, 1, 1, 0.35)

                DankIcon {
                    anchors.centerIn: parent
                    name: "play_arrow"
                    size: 34
                    color: "white"
                }
            }

            DankSpinner {
                id: buffering
                anchors.centerIn: parent
                visible: video.started && !video.failed && (video.renewing || player.mediaStatus === MediaPlayer.LoadingMedia || player.mediaStatus === MediaPlayer.BufferingMedia || player.mediaStatus === MediaPlayer.StalledMedia)
                size: 32
            }

            GitHubLinkRow {
                anchors.centerIn: parent
                width: Math.min(parent.width - Theme.spacingL * 2, 280)
                visible: video.failed
                color: Qt.rgba(0, 0, 0, 0.6)
                icon: "open_in_new"
                text: "Can't play it here: open on GitHub"
                action: () => {
                    if (video.openOutside)
                        video.openOutside();
                }
            }
        }

        // Play or pause, where it is, a bar to seek along, and the sound.
        Item {
            id: controls
            y: header.height + screen.height
            visible: video.open
            width: parent.width
            height: 34

            DankActionButton {
                id: playButton
                x: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter
                buttonSize: 28
                iconSize: 18
                iconName: video.playing ? "pause" : "play_arrow"
                iconColor: Theme.surfaceText
                enabled: !video.failed
                onClicked: video.toggle()
            }

            StyledText {
                id: time
                anchors.left: playButton.right
                anchors.leftMargin: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter
                text: video.clock(player.position) + " / " + video.clock(player.duration)
                font.pixelSize: Theme.fontSizeSmall
                font.family: Theme.monoFontFamily
                color: Theme.surfaceVariantText
            }

            Item {
                id: track
                anchors.left: time.right
                anchors.leftMargin: Theme.spacingM
                anchors.right: muteButton.left
                anchors.rightMargin: Theme.spacingS
                anchors.verticalCenter: parent.verticalCenter
                height: 16

                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Theme.withAlpha(Theme.surfaceText, 0.15)

                    Rectangle {
                        width: player.duration > 0 ? parent.width * player.position / player.duration : 0
                        height: parent.height
                        radius: 2
                        color: Theme.primary
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: player.duration > 0 && player.seekable
                    cursorShape: Qt.PointingHandCursor
                    function seek(x) {
                        player.position = Math.round(player.duration * Math.max(0, Math.min(1, x / width)));
                    }
                    onPressed: mouse => seek(mouse.x)
                    onPositionChanged: mouse => {
                        if (pressed)
                            seek(mouse.x);
                    }
                }
            }

            DankActionButton {
                id: muteButton
                anchors.right: parent.right
                anchors.rightMargin: Theme.spacingXS
                anchors.verticalCenter: parent.verticalCenter
                buttonSize: 28
                iconSize: 18
                iconName: audio.muted ? "volume_off" : "volume_up"
                iconColor: Theme.surfaceText
                tooltipText: audio.muted ? "Unmute" : "Mute"
                onClicked: audio.muted = !audio.muted
            }
        }
    }
}
