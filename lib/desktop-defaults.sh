#!/usr/bin/env bash
set -Eeuo pipefail

# Desktop default-application helpers shared by first-run and post-action
# steps.

browser_desktop_file() {
  case "$1" in
    firefox) printf 'firefox.desktop\n' ;;
    chromium) printf 'chromium.desktop\n' ;;
    chrome) printf 'google-chrome.desktop\n' ;;
    brave) printf 'brave-browser.desktop\n' ;;
    zen-copr) printf 'zen.desktop\n' ;;
    helium|helium-copr) printf 'helium.desktop\n' ;;
    *) return 1 ;;
  esac
}
