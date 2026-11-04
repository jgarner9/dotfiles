# dotfiles

Managed with [chezmoi](https://chezmoi.io). Nothing syncs on its own: run
`chezmoi update` to pull and apply.

## Arch vs macOS

Shared config lives in the normal chezmoi places. OS-specific bits live in
their own files, and `.chezmoiignore` makes sure each machine only gets the
ones for its OS:

| | Arch | macOS |
| --- | --- | --- |
| zsh | `dot_config/zsh/arch.zsh` | `dot_config/zsh/macos.zsh` |
| kitty | `dot_config/kitty/linux.conf` | `dot_config/kitty/macos.conf` |
| Desktop | `dot_config/hypr`, `dot_config/waybar`, `Documents/Backgrounds` | |

`~/.zshrc` sources the OS's zsh file last, and `kitty.conf` includes
`${KITTY_OS}.conf`. To add something OS-specific, make a new file and list it
under that OS's block in `.chezmoiignore`.
