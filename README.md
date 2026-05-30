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

### Manual

Browse the [latest release](https://github.com/lazyvamp/ctx-dist/releases/latest) and download the binary for your platform.

## Supported platforms

| OS    | Arch        | Binary                  |
| ----- | ----------- | ----------------------- |
| macOS | arm64       | `ctx-darwin-arm64`      |
| macOS | amd64       | `ctx-darwin-amd64`      |
| Linux | amd64       | `ctx-linux-amd64`       |
| Linux | arm64       | `ctx-linux-arm64`       |

Each release also ships `ctx-mcp-*` (the MCP server) and a `SHA256SUMS` file.

## Verifying

```bash
sha256sum -c SHA256SUMS --ignore-missing
```

## Reporting issues

File issues on [github.com/lazyvamp/ctx-dist/issues](https://github.com/lazyvamp/ctx-dist/issues).
