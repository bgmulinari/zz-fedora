#!/usr/bin/env python3

import os

from gi import require_version

require_version("Nautilus", "4.1")

from gi.repository import GObject, Gio, Nautilus


class OpenTerminalHere(GObject.GObject, Nautilus.MenuProvider):
    def _open_terminal(self, _menu, path):
        Gio.Subprocess.new(
            ["xdg-terminal-exec", "--dir", path],
            Gio.SubprocessFlags.NONE,
        )

    def _item_for_path(self, path):
        if not path:
            return None

        item = Nautilus.MenuItem(
            name="OpenTerminalHere::open",
            label="Open in Terminal",
            tip="Open the default terminal in this folder",
        )
        item.connect("activate", self._open_terminal, path)
        return item

    def _path_from_file_info(self, file_info):
        location = file_info.get_location()
        if location is None:
            return None

        path = location.get_path()
        if not path:
            return None

        if file_info.is_directory():
            return path
        return os.path.dirname(path)

    def get_background_items(self, *args):
        current_folder = args[-1]
        item = self._item_for_path(self._path_from_file_info(current_folder))
        return [item] if item else []

    def get_file_items(self, *args):
        files = args[-1]
        if len(files) != 1:
            return []

        item = self._item_for_path(self._path_from_file_info(files[0]))
        return [item] if item else []
