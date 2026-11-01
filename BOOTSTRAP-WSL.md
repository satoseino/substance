# Bootstrap

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
sudo dfn update
sudo dnf install vim hostname tree \
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

## Change hostname to `fedora`

```bash
sudo vim /etc/wsl.conf
```

Change the contents under the `[network]` table to the following. Save and exit.

```toml
[network]
hostname = fedora
```

Exit Fedora. In PowerShell, shutdown WSL2.

```
wsl --shutdown
```

Launch the Fedora distro again.
