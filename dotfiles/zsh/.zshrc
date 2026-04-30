# Managed by zz-linux-setup.

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME=""
plugins=(git sudo zsh-autosuggestions zsh-syntax-highlighting)

[[ -f "$HOME/.zsh/noctalia-zsh-syntax-highlighting.zsh" ]] && source "$HOME/.zsh/noctalia-zsh-syntax-highlighting.zsh"
[[ -f "$ZSH/oh-my-zsh.sh" ]] && source "$ZSH/oh-my-zsh.sh"

for shell_rc in "$HOME"/.shellrc.d/*(N); do
  [[ -f "$shell_rc" ]] || continue
  source "$shell_rc"
done

for zsh_rc in "$HOME"/.zshrc.d/*(N); do
  [[ -f "$zsh_rc" ]] || continue
  source "$zsh_rc"
done
