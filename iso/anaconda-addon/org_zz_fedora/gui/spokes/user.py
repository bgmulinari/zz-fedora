"""Require Anaconda's user creation screen for ZZ Fedora installs."""

from pyanaconda.ui.gui.spokes.user import UserSpoke

__all__ = ["ZZUserSpoke"]


class ZZUserSpoke(UserSpoke):
    """Keep user creation required even when root is configured."""

    @property
    def mandatory(self):
        return True
