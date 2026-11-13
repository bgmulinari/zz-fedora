# Product-owned Zsh login environment loaded from ~/.zz.
#
# The login shell is bash (~/.bash_profile owns the session environment);
# this covers an explicit `zsh -l`. The environment.d import in the product
# profile prepends to the inherited PATH, so keep PATH entries unique.

typeset -U path PATH

if [[ -f "$HOME/.zz/dotfiles/shell/.profile" ]]; then
  emulate sh -c '. "$HOME/.zz/dotfiles/shell/.profile"'
fi
