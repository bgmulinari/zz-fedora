# Product-owned PATH cleanup sourced at the end of the ZZ profile and bashrc.
#
# Every login shell in the session chain (greetd's profile, then the login
# shell niri-session re-executes through) imports the environment.d PATH,
# which prepends to whatever PATH it inherits, and user or vendor lines such
# as JetBrains Toolbox's append unconditionally. Keep the first occurrence of
# each entry so the order (and Homebrew staying behind /usr/bin) is
# preserved, and drop empty entries, which would mean the current directory.
# POSIX sh: greetd sources the profile with /bin/sh. Zsh uses `typeset -U
# path` instead.

zz_path_rest="$PATH:"
zz_path_clean=""
while [ -n "$zz_path_rest" ]; do
  zz_path_entry="${zz_path_rest%%:*}"
  zz_path_rest="${zz_path_rest#*:}"
  [ -n "$zz_path_entry" ] || continue
  case ":$zz_path_clean:" in
    *":$zz_path_entry:"*) ;;
    *) zz_path_clean="${zz_path_clean:+$zz_path_clean:}$zz_path_entry" ;;
  esac
done
PATH="$zz_path_clean"
export PATH
unset zz_path_rest zz_path_clean zz_path_entry
