#!/usr/bin/env bash

set -eui
set -x

createKey() {
  location="$HOME/.ssh/id_ed25519_$1"
  ssh-keygen -t ed25519 -C "$(whoami)@$(hostname)-$1" \
    -f "$location"

  return "$location"
}

archieSpot="$(createKey "archie")"
gitSpot="$(createKey "git")"

ssh-add "$archieSpot"
ssh-add "$gitSpot"
