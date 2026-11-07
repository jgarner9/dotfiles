# macOS-only zsh config, sourced last from ~/.zshrc.
# chezmoi only installs this file on macOS (see .chezmoiignore).

alias ls="ls -G"
alias python="python3"
alias ssh-reload="sudo launchctl stop com.openssh.sshd && sudo launchctl start com.openssh.sshd"
alias saksync="launchctl kickstart -k gui/$(id -u)/dev.jgarner.swiss"
