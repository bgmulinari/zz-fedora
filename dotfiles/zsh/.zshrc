# Managed by zz-linux-setup.

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""
plugins=(git sudo zsh-autosuggestions zsh-syntax-highlighting)

[[ -f "$ZSH/oh-my-zsh.sh" ]] && source "$ZSH/oh-my-zsh.sh"

for shell_rc in "$HOME"/.shellrc.d/*(N); do
  [[ -f "$shell_rc" ]] || continue
  source "$shell_rc"
done
