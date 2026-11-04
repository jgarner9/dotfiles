# Arch-only zsh config, sourced last from ~/.zshrc.
# chezmoi only installs this file on Arch (see .chezmoiignore).

alias ls="ls --color=auto"
alias spm="sudo pacman"

# plugins from pacman (zsh-autosuggestions, zsh-syntax-highlighting);
# syntax-highlighting must stay last
if [[ -f /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
	source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
fi
if [[ -f /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]]; then
	source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
fi
