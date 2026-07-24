# Product-owned login-shell defaults loaded from ~/.zz.

export TERMINAL=kitty

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
