# Product-owned Bash login environment loaded from ~/.zz.
#
# Bash is the login shell, and a Bash login shell reads this file instead of
# ~/.profile. niri-session re-executes itself through the login shell after
# /etc/profile has reset distro defaults such as EDITOR, so load the product
# profile directly (a user-owned ~/.profile is not guaranteed to load it;
# other installers create that file too), then the user's ~/.profile so
# personal additions win, then the interactive configuration.

if [ -f "$HOME/.zz/dotfiles/shell/.profile" ]; then
  . "$HOME/.zz/dotfiles/shell/.profile"
fi

if [ -f "$HOME/.profile" ]; then
  . "$HOME/.profile"
fi

if [ -f "$HOME/.bashrc" ]; then
  . "$HOME/.bashrc"
fi

# Last, so lines the user files append unconditionally (and a seeded
# ~/.profile loading the product profile a second time) leave no duplicates.
if [ -f "$HOME/.zz/dotfiles/shell/path-dedupe.sh" ]; then
  . "$HOME/.zz/dotfiles/shell/path-dedupe.sh"
fi
