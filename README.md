# ctx-dist

Distribution channel for [`ctx`](https://ctx.sh) — releases, install script, and checksums.

The source repository is private. This repo exists to serve public release artifacts and the install script.

## Install

### Homebrew (macOS, Linux)

```bash
brew install lazyvamp/ctx/ctx
```

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/lazyvamp/ctx-dist/main/install.sh | sh
```

The installer also wires a `(.ctx)` badge into your shell prompt automatically — appears in the prompt whenever you `cd` into a git repo containing a ctx palace. To skip that step, set `CTX_SKIP_SHELL_HOOK=1` before piping.

### Manual

Browse the [latest release](https://github.com/lazyvamp/ctx-dist/releases/latest) and download the binary for your platform.

## Supported platforms

| OS    | Arch        | Binary                  |
| ----- | ----------- | ----------------------- |
| macOS | arm64       | `ctx-darwin-arm64`      |
| Linux | amd64       | `ctx-linux-amd64`       |
| Linux | arm64       | `ctx-linux-arm64`       |

macOS Intel (x86_64) is not shipped as a native binary. Rosetta runs the arm64 build fine.

Each release also ships `ctx-mcp-*` (the MCP server) and a `SHA256SUMS` file.

## Uninstalling

```bash
curl -fsSL https://raw.githubusercontent.com/lazyvamp/ctx-dist/main/install.sh | sh -s -- --uninstall
```

Or remove the binaries directly:

```bash
sudo rm -f /usr/local/bin/ctx /usr/local/bin/ctx-mcp
```

## Verifying

```bash
sha256sum -c SHA256SUMS --ignore-missing
```

## Reporting issues

File issues on [github.com/lazyvamp/ctx-dist/issues](https://github.com/lazyvamp/ctx-dist/issues).
