# Adds "Copy Full Path" to the Nautilus context menu for the selected files
# and folders, and for the current folder when the view background is
# right-clicked. Multiple selections are copied one path per line. Items are
# resolved through their activation URI, so a Recent entry copies the file it
# points to. Items without a local path (Trash, network locations without a
# FUSE mount) get no menu entry. Loaded by nautilus-python from
# ~/.local/share/nautilus-python/extensions; restart Nautilus after editing.

import gi

gi.require_version("Gdk", "4.0")

from gi.repository import Gdk, Gio, GObject, Nautilus


def local_paths(files):
    paths = []
    for file in files:
        path = Gio.File.new_for_uri(file.get_activation_uri()).get_path()
        if path is None:
            return []
        paths.append(path)
    return paths


def copy_paths_activated(_item, paths):
    Gdk.Display.get_default().get_clipboard().set("\n".join(paths))


def copy_path_items(name, files):
    paths = local_paths(files)
    if not paths:
        return []
    label = "Copy Full Paths" if len(paths) > 1 else "Copy Full Path"
    item = Nautilus.MenuItem(name=name, label=label)
    item.connect("activate", copy_paths_activated, paths)
    return [item]


class ZzCopyPathMenuProvider(GObject.GObject, Nautilus.MenuProvider):
    def get_file_items(self, files):
        return copy_path_items("ZzCopyPath::copy_selection", files)

    def get_background_items(self, current_folder):
        return copy_path_items("ZzCopyPath::copy_current_folder", [current_folder])
