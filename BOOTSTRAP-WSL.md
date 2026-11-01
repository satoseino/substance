# Bootstrap Fedora on WSL2

## Introduction

This document covers how to set up an AMD64 Windows 11 with WSL2 as a developer machine, geared towards Go, Python,
and JavaScript development. Work through it before running `./set-up.sh` for the first time on a new machine.

## Installing a Fedora distro

First, install a Fedora distro for WSL2. Replace `<FedoraLinux-version>` with the actual distro name.

```
wsl --list --online
wsl --install <FedoraLinux-version>
```

## Set up the Fedora distro

Install essential utilities.

```bash
cd
sudo dnf update
sudo dnf install vim hostname tree tmux wl-clipboard gawk \
  fzf bat jq yq git neovim ripgrep luarocks \
  go uv gh shellcheck pre-commit redis hugo
```

Install Homebrew for Linux. Some of our CLI dependencies are later installed by Homebrew.

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

echo >> $HOME/.bashrc
echo 'eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"' >> $HOME/.bashrc
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv bash)"

sudo dnf group install development-tools
```

## Install Development Tooling

```bash
brew install fnm mongosh

brew install satoseino/tap/cli-toolkit satoseino/tap/gelato

curl -fsSL https://awscli.amazonaws.com/v2/install.sh | bash

curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh

curl -fsSL https://claude.ai/install.sh | bash
```

Then
- install at least one LTS Nodejs version via `fnm`;
- login to GitHub via `gh auth login`;
- update AWS CLI v2 via `aws update` when needed.

## Install Go Executables

```bash
go install mvdan.cc/sh/v3/cmd/shfmt@latest
go install golang.org/x/tools/cmd/godoc@latest
go install golang.org/x/pkgsite
go install github.com/air-verse/air@latest
```

## Install Rust Executables

```bash
cargo install --locked tree-sitter-cli
```

## Install Jarvis Registry CLI

[Jarvis Registry CLI](https://github.com/ascending-llc/jarvis-registry-cli) is the companion CLI for the
`jarvis-registry` MCP server; it also syncs additional Claude Code skills.

```bash
brew install ascending-llc/jarvis/jarvis-registry
```

Then follow the steps listed in the Homebrew formulae caveats.

## (Optional) Install Docker Engine

Install Docker Engine (`docker-ce`) from Docker's repository inside the distro, instead of Docker Desktop on Windows.
It runs as a regular systemd service (the Fedora distro ships `systemd=true` in `/etc/wsl.conf`), and published ports are still reachable from
Windows via `localhost`. Do not also install Fedora's `moby-engine`; it conflicts with `docker-ce`.

```bash
sudo dnf config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo
sudo dnf install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER"
```

The `docker` group membership takes effect after the `wsl --shutdown` in the next section.

## Configure `/etc/wsl.conf`

```bash
sudo vim /etc/wsl.conf
```

Set the `[network]` and `[interop]` tables to the following. Save and exit.

```toml
[network]
hostname = fedora

[interop]
appendWindowsPath = false
```

`hostname = fedora` selects `profile/fedora.bashrc` and the `fedora`-specific handling in this repo.

`appendWindowsPath = false` keeps the Windows `PATH` out of the Linux `PATH`. This avoids slow command lookups
across `/mnt/c` and Windows binaries shadowing Linux ones. Windows executables can still be run by full path
(e.g. `/mnt/c/WINDOWS/system32/clip.exe`).

Exit Fedora. In PowerShell, shutdown WSL2.

```
wsl --shutdown
```

Launch the Fedora distro again.
