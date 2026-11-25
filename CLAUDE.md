# dotfiles

Jason's personal config for an Arch (Hyprland) machine and a Mac (AeroSpace),
managed with chezmoi. This repo is the chezmoi source directory: nothing here
runs directly; `chezmoi apply` renders it into `$HOME`.

## Layout

- `dot_zshrc`, `dot_zprofile`: shell. OS-specific bits in `dot_config/zsh/{arch,macos}.zsh`, sourced last.
- `dot_config/git/config.tmpl`: shared git config at `~/.config/git/config` (SSH commit signing).
- `dot_config/kitty/`: terminal; `kitty.conf` includes `${KITTY_OS}.conf`.
- `dot_config/zellij/config.kdl`: multiplexer.
- `dot_config/hypr/`, `dot_config/waybar/`: Arch window manager and bar. `hyprland.lua` is the real config; `hyprland.conf` is a stub.
- `dot_config/aerospace/aerospace.toml`: macOS window manager.
- `private_dot_ssh/private_config`: SSH hosts (no keys, ever).
- `dot_local/bin/`: personal scripts, installed to `~/.local/bin`.
- `Brewfile` + `run_onchange_after_brew-bundle.sh.tmpl`: macOS packages.
- `run_onchange_after_macos-defaults.sh.tmpl`: macOS `defaults write` settings.
- `.chezmoiignore`: the Arch / macOS / Linux split. Read it before adding a file.

## Commands

```sh
chezmoi diff                                  # what apply would change
chezmoi apply -v                              # render into $HOME
chezmoi execute-template < dot_config/git/config.tmpl   # check a template renders
shellcheck -s bash dot_local/bin/executable_*            # lint scripts
```

There is no test suite; check a change with `chezmoi diff` on the machine it targets.

## Hard constraints

- **The repo is public.** Never commit secrets, tokens, private keys, work
  details or employer email. Machine-specific or private values go in chezmoi
  data (`~/.config/chezmoi/chezmoi.toml`), read from templates.
- Commit as `garnerjasonj@icloud.com` (or the GitHub noreply), never a work address.
- Every OS-specific file must be listed under its OS's block in `.chezmoiignore`,
  or it lands on every machine.
- Repo-only files (README, CLAUDE.md, Brewfile) must be in `.chezmoiignore`, or
  chezmoi copies them into `$HOME`.

## Conventions

- chezmoi naming: `dot_` → `.`, `private_` → mode 0600/0700, `executable_` → +x,
  `.tmpl` → Go template, `run_onchange_` → reruns when its contents change.
- Comments explain *why* a setting exists, not what it does.
- Don't vendor other repos (no committed `.git` dirs or plugin checkouts);
  install them with a package manager instead.

## Gotchas

- `chezmoi update` is manual; nothing syncs on its own.
- Don't keep a `~/.gitconfig` alongside `~/.config/git/config`: it overrides it.
- An app installed from a `.dmg` before it was in the `Brewfile` makes the cask
  install fail; adopt it once with `brew install --cask --adopt <name>`.
