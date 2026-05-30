#!/usr/bin/env sh
# ctx installer — downloads the right binary for your platform from
# https://github.com/lazyvamp/ctx-dist, verifies SHA256, and installs to
# /usr/local/bin (or $CTX_INSTALL_DIR).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/lazyvamp/ctx-dist/main/install.sh | sh
#
# Env vars:
#   CTX_VERSION      — pin a specific tag (default: latest)
#   CTX_INSTALL_DIR  — install prefix (default: /usr/local/bin)
#
# Why POSIX sh, not bash: this script gets piped into whatever shell the
# user's curl-pipe defaults to. Sticking to /bin/sh keeps it portable
# across minimal Linux containers and macOS without surprises.

set -eu

REPO="lazyvamp/ctx-dist"
INSTALL_DIR="${CTX_INSTALL_DIR:-/usr/local/bin}"
VERSION="${CTX_VERSION:-latest}"

# ── Platform detection ───────────────────────────────────────────────
detect_os() {
    case "$(uname -s)" in
        Darwin) echo "darwin" ;;
        Linux)  echo "linux"  ;;
        *) echo "unsupported OS: $(uname -s) — see https://github.com/${REPO}/releases for manual install" >&2; exit 1 ;;
    esac
}

detect_arch() {
    case "$(uname -m)" in
        arm64|aarch64) echo "arm64" ;;
        x86_64|amd64)  echo "amd64" ;;
        *) echo "unsupported arch: $(uname -m)" >&2; exit 1 ;;
    esac
}

OS="$(detect_os)"
ARCH="$(detect_arch)"

# macOS Intel native builds aren't shipped. Rosetta runs the arm64
# binary, but we don't try to detect Rosetta here — give a clear
# message and exit instead of downloading a 404.
if [ "$OS" = "darwin" ] && [ "$ARCH" = "amd64" ]; then
    echo "macOS Intel (x86_64) native builds are not published." >&2
    echo "Use Rosetta on the arm64 build, or build from source." >&2
    exit 1
fi

# ── Resolve version ──────────────────────────────────────────────────
# `latest` → look up the actual tag via the GitHub redirect on the
# /releases/latest URL. Avoids hitting the API (rate-limited for
# unauthenticated users on busy networks) and works with just curl.
#
# Gotcha: if NO published (non-draft) release exists, GitHub redirects
# /releases/latest back to /releases (no /tag/ in the path). The sed
# strip then leaves the full URL in VERSION, which silently corrupts
# the download URL downstream. Validate the result looks like a vX.Y.Z
# tag before proceeding.
if [ "$VERSION" = "latest" ]; then
    VERSION="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest" | sed 's#.*/tag/##')"
    case "$VERSION" in
        v[0-9]*) ;;  # looks like a tag (vX.Y.Z), proceed
        *)
            echo "could not resolve a latest release tag from github.com/${REPO}." >&2
            echo "Is there a published (non-draft) release? See https://github.com/${REPO}/releases" >&2
            exit 1
            ;;
    esac
fi

BASE_URL="https://github.com/${REPO}/releases/download/${VERSION}"
CTX_NAME="ctx-${OS}-${ARCH}"
MCP_NAME="ctx-mcp-${OS}-${ARCH}"

# ── Download ─────────────────────────────────────────────────────────
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Installing ctx ${VERSION} for ${OS}/${ARCH}"

for asset in "$CTX_NAME" "$MCP_NAME" SHA256SUMS; do
    echo "    fetching ${asset}"
    if ! curl -fsSL -o "${TMP}/${asset}" "${BASE_URL}/${asset}"; then
        echo "failed to download ${asset} — does ${VERSION} exist for ${OS}/${ARCH}?" >&2
        echo "see https://github.com/${REPO}/releases/${VERSION}" >&2
        exit 1
    fi
done

# ── Verify ───────────────────────────────────────────────────────────
# Mismatched checksums = either the release was tampered with in
# transit, or upstream re-uploaded a bad asset. Either way: hard fail.
cd "$TMP"
if command -v sha256sum >/dev/null 2>&1; then
    SHA_TOOL="sha256sum"
elif command -v shasum >/dev/null 2>&1; then
    SHA_TOOL="shasum -a 256"
else
    echo "neither sha256sum nor shasum found — cannot verify checksums" >&2
    exit 1
fi

for asset in "$CTX_NAME" "$MCP_NAME"; do
    expected="$(grep " ${asset}$" SHA256SUMS | awk '{print $1}')"
    if [ -z "$expected" ]; then
        echo "no checksum for ${asset} in SHA256SUMS — refusing to install" >&2
        exit 1
    fi
    actual="$($SHA_TOOL "$asset" | awk '{print $1}')"
    if [ "$expected" != "$actual" ]; then
        echo "checksum mismatch for ${asset}" >&2
        echo "  expected: ${expected}" >&2
        echo "  actual:   ${actual}" >&2
        exit 1
    fi
done
echo "    checksums verified"

# ── Install ──────────────────────────────────────────────────────────
# We try a plain mv first; if the install dir isn't writable, fall back
# to sudo. This matches Homebrew's behaviour and keeps the prompt out
# of the way for users with /usr/local/bin already owned.
install_one() {
    src="$1"
    dest="$2"
    chmod +x "$src"
    if [ -w "$(dirname "$dest")" ]; then
        mv "$src" "$dest"
    else
        echo "    sudo needed to write ${dest}"
        sudo mv "$src" "$dest"
    fi
}

install_one "$CTX_NAME" "${INSTALL_DIR}/ctx"
install_one "$MCP_NAME" "${INSTALL_DIR}/ctx-mcp"

# Clear macOS quarantine attribute so Gatekeeper doesn't block on first
# run. No-op on Linux.
if [ "$OS" = "darwin" ]; then
    xattr -d com.apple.quarantine "${INSTALL_DIR}/ctx"     2>/dev/null || true
    xattr -d com.apple.quarantine "${INSTALL_DIR}/ctx-mcp" 2>/dev/null || true
fi

echo "==> Installed:"
echo "    ${INSTALL_DIR}/ctx"
echo "    ${INSTALL_DIR}/ctx-mcp"
echo
echo "Verify with: ctx --version"
