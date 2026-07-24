# Product-owned Zsh defaults loaded from ~/.zz.

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""
plugins=(git sudo zsh-autosuggestions zsh-syntax-highlighting)

[[ -f "$ZSH/oh-my-zsh.sh" ]] && source "$ZSH/oh-my-zsh.sh"

for shell_rc in \
  "$HOME"/.zz/dotfiles/shell/.shellrc.d/*(N) \
  "$HOME"/.config/zz-fedora/shell.d/*(N); do
  [[ -f "$shell_rc" ]] || continue
  source "$shell_rc"
done

for shell_rc in "$HOME"/.shellrc.d/*(N); do
  [[ -f "$shell_rc" ]] || continue
  source "$shell_rc"
done

for zsh_rc in "$HOME"/.zshrc.d/*(N); do
  [[ -f "$zsh_rc" ]] || continue
  source "$zsh_rc"
done
