# Product-owned Bash defaults loaded from ~/.zz.

if [ -f /etc/bashrc ]; then
  . /etc/bashrc
fi

for shell_rc in \
  "$HOME"/.zz/dotfiles/shell/.shellrc.d/* \
  "$HOME"/.config/zz-fedora/shell.d/*; do
  [ -f "$shell_rc" ] || continue
  . "$shell_rc"
done

for shell_rc in "$HOME"/.shellrc.d/*; do
  [ -f "$shell_rc" ] || continue
  . "$shell_rc"
done

if [ -f "$HOME/.cargo/env" ]; then
  . "$HOME/.cargo/env"
fi
