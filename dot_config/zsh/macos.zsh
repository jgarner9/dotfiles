# macOS-only zsh config, sourced last from ~/.zshrc.
# chezmoi only installs this file on macOS (see .chezmoiignore).

alias ls="ls -G"
alias saksync="launchctl kickstart -k gui/$(id -u)/dev.jgarner.swiss"
