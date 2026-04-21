# Managed by zz-linux-setup.

export TERMINAL=ghostty

if [ -d "$HOME/.config/environment.d" ]; then
  for env_file in "$HOME/.config/environment.d"/*.conf; do
    [ -f "$env_file" ] || continue
    while IFS='=' read -r key value; do
      [ -n "${key:-}" ] || continue
      export "$key=$value"
    done <"$env_file"
  done
fi
