#!/usr/bin/env bash
#
# termux-god installer — builds iso2god-rs natively in Termux and installs
# the `termux-god` wrapper + `iso2god-bin` binary into $PREFIX/bin.
#
# Usage (inside Termux):
#   bash install.sh
#
set -euo pipefail

# --- locate ourselves --------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

info()  { printf '\033[1;36m▸\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m!\033[0m %s\n' "$*" >&2; }
die()   { printf '\033[1;31m✗\033[0m %s\n' "$*" >&2; exit 1; }

# --- sanity: are we in Termux? ----------------------------------------------
if [ -z "${PREFIX:-}" ] || [ ! -d "$PREFIX/bin" ] || ! command -v pkg >/dev/null 2>&1; then
    die "This does not look like Termux (no \$PREFIX / pkg). Run the installer inside Termux."
fi

# --- read pinned upstream version -------------------------------------------
[ -f "$SCRIPT_DIR/VERSION" ] || die "VERSION file not found next to install.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/VERSION"
: "${ISO2GOD_TAG:?VERSION does not define ISO2GOD_TAG}"

# --- dependencies ------------------------------------------------------------
info "Installing dependencies (rust, git)…"
pkg update -y
pkg install -y rust git

command -v cargo >/dev/null 2>&1 || die "cargo not found after installing rust."

# --- fetch upstream sources --------------------------------------------------
SRC_DIR="${TMPDIR:-$PREFIX/tmp}/termux-god-src/iso2god-rs"
info "Cloning iso2god-rs ($ISO2GOD_TAG) → $SRC_DIR"
rm -rf "$SRC_DIR"
mkdir -p "$(dirname "$SRC_DIR")"
git clone --depth 1 --branch "$ISO2GOD_TAG" \
    https://github.com/iliazeus/iso2god-rs "$SRC_DIR"

# --- build (release bin only — dev-deps like reqwest are NOT compiled) -------
info "Building iso2god (release)… this can take a few minutes."
( cd "$SRC_DIR" && cargo build --release --bin iso2god )

BUILT_BIN="$SRC_DIR/target/release/iso2god"
[ -x "$BUILT_BIN" ] || die "Build did not produce a binary at $BUILT_BIN"

# --- install ----------------------------------------------------------------
info "Installing into $PREFIX/bin …"
install -m 0755 "$BUILT_BIN"             "$PREFIX/bin/iso2god-bin"
install -m 0755 "$SCRIPT_DIR/termux-god" "$PREFIX/bin/termux-god"

# --- cleanup build tree (source is disposable) ------------------------------
rm -rf "$SRC_DIR"

info "Done. Installed: termux-god, iso2god-bin"
"$PREFIX/bin/iso2god-bin" --version 2>/dev/null || true

# --- storage hint ------------------------------------------------------------
if [ ! -d "$HOME/storage" ] && [ ! -d /sdcard ]; then
    warn "No shared-storage access yet. Run once:  termux-setup-storage"
fi

cat <<'EOF'

Usage:
  termux-god <game.iso> [--trim] [--out DIR] [--threads N] [--no-progress]

Example:
  termux-god /sdcard/Download/game.iso --trim

Default output: /sdcard/termux-god/<TitleID>/00007000/<MediaID>
EOF
