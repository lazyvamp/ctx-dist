#!/usr/bin/env sh
# ctx installer — downloads the right binary for your platform from
# https://github.com/lazyvamp/ctx-dist, verifies SHA256, and installs to
# /usr/local/bin (or $CTX_INSTALL_DIR).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/lazyvamp/ctx-dist/main/install.sh | sh
#
# Uninstall:
#   curl -fsSL https://raw.githubusercontent.com/lazyvamp/ctx-dist/main/install.sh | sh -s -- --uninstall
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

# Sentinel comments marking the block install.sh writes into your rc
# file. Used by both install and uninstall to find/remove the hook
# idempotently. Don't edit them by hand — install.sh greps for these.
SHELL_HOOK_START="# >>> ctx shell integration >>>"
SHELL_HOOK_END="# <<< ctx shell integration <<<"

# detect_rc_file echoes the path of the rc file we'd modify for the
# detected shell, or empty if we don't recognise the shell. Honours
# $ZDOTDIR for zsh; on macOS bash, prefers .bash_profile (login shells
# read it) over .bashrc.
detect_rc_file() {
    case "${SHELL:-}" in
        */zsh)
            echo "${ZDOTDIR:-$HOME}/.zshrc"
            ;;
        */bash)
            if [ "$(uname -s)" = "Darwin" ] && [ -f "$HOME/.bash_profile" ]; then
                echo "$HOME/.bash_profile"
            else
                echo "$HOME/.bashrc"
            fi
            ;;
        *)
            echo ""
            ;;
    esac
}

detect_shell_name() {
    case "${SHELL:-}" in
        */zsh)  echo zsh ;;
        */bash) echo bash ;;
        *)      echo "" ;;
    esac
}

remove_shell_hook() {
    for rc in "${ZDOTDIR:-$HOME}/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile"; do
        if [ -f "$rc" ] && grep -qxF "$SHELL_HOOK_START" "$rc"; then
            # sed -i has incompatible syntax across BSD (macOS) and GNU
            # (linux). The portable workaround: -i.bak with an explicit
            # backup extension, then rm the backup.
            sed -i.ctx-bak "/^$(printf '%s' "$SHELL_HOOK_START" | sed 's/[][\.*^$/]/\\&/g')\$/,/^$(printf '%s' "$SHELL_HOOK_END" | sed 's/[][\.*^$/]/\\&/g')\$/d" "$rc"
            rm -f "${rc}.ctx-bak"
            echo "    removed shell hook from ${rc}"
        fi
    done
}

# ── Uninstall path ───────────────────────────────────────────────────
# Handled before platform detection — uninstall doesn't care which
# OS/arch produced the binaries it's removing. Honours $CTX_INSTALL_DIR
# so users who installed to a custom prefix can uninstall the same way.
if [ "${1:-}" = "--uninstall" ]; then
    echo "==> Uninstalling ctx from ${INSTALL_DIR}"
    removed=0
    for bin in ctx ctx-mcp; do
        target="${INSTALL_DIR}/${bin}"
        if [ -e "$target" ]; then
            if [ -w "$(dirname "$target")" ]; then
                rm -f "$target"
            else
                echo "    sudo needed to remove ${target}"
                sudo rm -f "$target"
            fi
            echo "    removed ${target}"
            removed=$((removed + 1))
        fi
    done
    if [ "$removed" -eq 0 ]; then
        echo "    nothing to remove — neither ctx nor ctx-mcp found under ${INSTALL_DIR}"
    fi
    remove_shell_hook
    exit 0
fi

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
    VERSION="$(curl -fsSLI --connect-timeout 10 --max-time 30 -o /dev/null -w '%{url_effective}' "https://github.com/${REPO}/releases/latest" | sed 's#.*/tag/##')"
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

# ── Preflight: sudo availability ─────────────────────────────────────
# Under `curl ... | sh`, stdin is the curl pipe — not a TTY. If the
# later `sudo mv` had to prompt for a password it would block forever
# (no visible prompt, because sudo writes the prompt to /dev/tty but
# reads the password from stdin). Detect that situation now and fail
# fast with actionable guidance, before downloading ~30 MB of binaries
# we wouldn't be able to install anyway.
if [ ! -w "$INSTALL_DIR" ] && ! sudo -n true 2>/dev/null; then
    INSTALLER_URL="https://raw.githubusercontent.com/${REPO}/main/install.sh"
    echo "==> ${INSTALL_DIR} is not writable and sudo is not authenticated." >&2
    echo "    Under 'curl | sh' sudo cannot prompt for a password (stdin is the pipe)." >&2
    echo "    Pick one:" >&2
    echo "      1) Pre-authenticate sudo, then re-run:" >&2
    echo "           sudo -v && curl -fsSL ${INSTALLER_URL} | sh" >&2
    echo "      2) Install to a user-writable prefix (no sudo):" >&2
    echo "           curl -fsSL ${INSTALLER_URL} | CTX_INSTALL_DIR=\$HOME/.local/bin sh" >&2
    echo "      3) Download first, then run with a real terminal:" >&2
    echo "           curl -fsSL ${INSTALLER_URL} -o /tmp/ctx-install.sh && sh /tmp/ctx-install.sh" >&2
    exit 1
fi

# ── Download ─────────────────────────────────────────────────────────
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Installing ctx ${VERSION} for ${OS}/${ARCH}"

for asset in "$CTX_NAME" "$MCP_NAME" SHA256SUMS; do
    echo "    fetching ${asset}"
    # --connect-timeout 15: fail fast if GitHub is unreachable instead
    # of hanging on a stuck TCP handshake.
    # --max-time 300: cap the whole transfer at 5 min. Binaries are
    # ~30 MB; a stalled mid-download would otherwise hang silently.
    if ! curl -fsSL --connect-timeout 15 --max-time 300 -o "${TMP}/${asset}" "${BASE_URL}/${asset}"; then
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
    # Take only the first match — guards against a malformed SHA256SUMS
    # that lists the same asset twice (e.g. from a bad CI glob).
    # Duplicate entries would otherwise produce a multi-line `expected`
    # and silently fail the string comparison below.
    expected="$(grep " ${asset}$" SHA256SUMS | awk 'NR==1 {print $1}')"
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

# ── Shell prompt integration ─────────────────────────────────────────
# Append `eval "$(ctx --shell zsh|bash)"` to the user's rc file so
# their prompt grows a (.ctx) badge in palace-bearing directories.
# Skip with CTX_SKIP_SHELL_HOOK=1. Idempotent — sentinel comments let
# us detect prior installs and avoid duplicating the block.
install_shell_hook() {
    if [ -n "${CTX_SKIP_SHELL_HOOK:-}" ]; then
        echo "==> Shell hook: skipped (CTX_SKIP_SHELL_HOOK set)"
        return
    fi
    shell_name="$(detect_shell_name)"
    rc_file="$(detect_rc_file)"
    if [ -z "$shell_name" ] || [ -z "$rc_file" ]; then
        echo "==> Shell hook: not installed (unsupported \$SHELL=${SHELL:-unset})"
        echo "    install manually: echo 'eval \"\$(ctx --shell zsh)\"' >> ~/.zshrc"
        return
    fi
    if [ -f "$rc_file" ] && grep -qxF "$SHELL_HOOK_START" "$rc_file"; then
        echo "==> Shell hook: already present in ${rc_file}"
        return
    fi
    {
        printf '\n%s\n' "$SHELL_HOOK_START"
        printf '%s\n'   "# Adds a (.ctx) badge to the prompt in palace-bearing repos."
        printf '%s\n'   "# Managed by ctx-dist/install.sh — edit at your own risk."
        printf '%s\n'   'eval "$(ctx --shell '"$shell_name"')"'
        printf '%s\n'   "$SHELL_HOOK_END"
    } >> "$rc_file"
    echo "==> Shell hook: added to ${rc_file}"
    echo "    restart your shell (or 'source ${rc_file}') to activate the (.ctx) badge"
}
install_shell_hook

echo
echo "Verify with: ctx --version"
