# Managed by zz-fedora.

if [ -f /etc/bashrc ]; then
  . /etc/bashrc
fi

for shell_rc in "$HOME"/.shellrc.d/*; do
  [ -f "$shell_rc" ] || continue
  . "$shell_rc"
done

if [ -f "$HOME/.cargo/env" ]; then
  . "$HOME/.cargo/env"
fi
