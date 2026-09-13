# Product-owned login-shell defaults loaded from ~/.zz.

export TERMINAL=xdg-terminal-exec

# The editor is a session-wide default, not an interactive-shell one: DMS,
# the ZZ menu rows, and anything else the compositor spawns read EDITOR from
# the login environment greetd builds. Fedora's nano-default-editor profile.d
# script has already set EDITOR=/usr/bin/nano by the time this file runs, so
# override it here whenever a better editor is installed.
if command -v nvim >/dev/null 2>&1; then
  export EDITOR="nvim"
  export VISUAL="nvim"
elif command -v vi >/dev/null 2>&1; then
  export EDITOR="vi"
  export VISUAL="vi"
fi

zz_environment_d_generator="/usr/lib/systemd/user-environment-generators/30-systemd-environment-d-generator"
if [ -x "$zz_environment_d_generator" ] && \
   zz_environment_output="$("$zz_environment_d_generator")"; then
  while IFS='=' read -r zz_environment_key zz_environment_value; do
    [ -n "${zz_environment_key:-}" ] || continue
    export "$zz_environment_key=$zz_environment_value"
  done <<EOF
$zz_environment_output
EOF
fi
unset zz_environment_d_generator zz_environment_output zz_environment_key zz_environment_value

if [ -f "$HOME/.cargo/env" ]; then
  . "$HOME/.cargo/env"
fi
