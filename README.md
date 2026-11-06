# dotfiles

Managed with [chezmoi](https://chezmoi.io). Nothing syncs on its own: run
`chezmoi update` to pull and apply.

## Arch vs macOS

Shared config lives in the normal chezmoi places. OS-specific bits live in
their own files, and `.chezmoiignore` makes sure each machine only gets the
ones for its OS:

| | Arch | macOS |
| --- | --- | --- |
| zsh | `dot_config/zsh/arch.zsh` | `dot_config/zsh/macos.zsh`, `dot_zprofile` |
| kitty | `dot_config/kitty/linux.conf` | `dot_config/kitty/macos.conf` |
| Window manager | `dot_config/hypr`, `dot_config/waybar` | `dot_config/aerospace` |
| Packages | | `Brewfile` |
| System settings | | `run_onchange_after_macos-defaults.sh.tmpl` |
| Wallpapers | `Documents/Backgrounds` | |

`~/.zshrc` sources the OS's zsh file last, and `kitty.conf` includes
`${KITTY_OS}.conf`. To add something OS-specific, make a new file and list it
under that OS's block in `.chezmoiignore`.

## Packages (macOS)

`Brewfile` lists every formula and app. When it changes, `chezmoi apply` runs
`brew bundle --no-upgrade` with it, which only installs what's missing. To
remove anything that isn't listed:

```sh
brew bundle cleanup --file="$(chezmoi source-path)/Brewfile"         # preview
brew bundle cleanup --force --file="$(chezmoi source-path)/Brewfile" # remove
```

An app that was installed from a `.dmg` before it was listed makes the cask
install fail. Hand it to Homebrew once with `brew install --cask --adopt <name>`.

## System settings (macOS)

`run_onchange_after_macos-defaults.sh.tmpl` sets keyboard, text, Finder, Dock
and screenshot defaults with `defaults write`, one setting per line. chezmoi
reruns it whenever the file changes. Some settings need a logout.

## Git

`dot_config/git/config.tmpl` is the shared git config at `~/.config/git/config`.
The signing key path comes from the home dir, so the same file works on both
OSes. Don't keep a `~/.gitconfig` as well: git reads both, and settings in
`~/.gitconfig` override this one.
