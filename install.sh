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
    die "Похоже, это не Termux (нет \$PREFIX / pkg). Запусти установку внутри Termux."
fi

# --- read pinned upstream version -------------------------------------------
[ -f "$SCRIPT_DIR/VERSION" ] || die "Не найден файл VERSION рядом с install.sh"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/VERSION"
: "${ISO2GOD_TAG:?VERSION не задаёт ISO2GOD_TAG}"

# --- dependencies ------------------------------------------------------------
info "Устанавливаю зависимости (rust, git)…"
pkg update -y
pkg install -y rust git

command -v cargo >/dev/null 2>&1 || die "cargo не найден после установки rust."

# --- fetch upstream sources --------------------------------------------------
SRC_DIR="${TMPDIR:-$PREFIX/tmp}/termux-god-src/iso2god-rs"
info "Клонирую iso2god-rs ($ISO2GOD_TAG) → $SRC_DIR"
rm -rf "$SRC_DIR"
mkdir -p "$(dirname "$SRC_DIR")"
git clone --depth 1 --branch "$ISO2GOD_TAG" \
    https://github.com/iliazeus/iso2god-rs "$SRC_DIR"

# --- build (release bin only — dev-deps like reqwest are NOT compiled) -------
info "Собираю iso2god (release)… это может занять несколько минут."
( cd "$SRC_DIR" && cargo build --release --bin iso2god )

BUILT_BIN="$SRC_DIR/target/release/iso2god"
[ -x "$BUILT_BIN" ] || die "Сборка не дала бинарь $BUILT_BIN"

# --- install ----------------------------------------------------------------
info "Устанавливаю в $PREFIX/bin …"
install -m 0755 "$BUILT_BIN"            "$PREFIX/bin/iso2god-bin"
install -m 0755 "$SCRIPT_DIR/termux-god" "$PREFIX/bin/termux-god"

# --- cleanup build tree (source is disposable) ------------------------------
rm -rf "$SRC_DIR"

info "Готово. Установлено: termux-god, iso2god-bin"
"$PREFIX/bin/iso2god-bin" --version 2>/dev/null || true

# --- storage hint ------------------------------------------------------------
if [ ! -d "$HOME/storage" ] && [ ! -d /sdcard ]; then
    warn "Нет доступа к общей памяти. Выполни один раз:  termux-setup-storage"
fi

cat <<'EOF'

Использование:
  termux-god <game.iso> [--trim] [--out DIR] [--threads N] [--no-progress]

Пример:
  termux-god /sdcard/Download/game.iso --trim

Результат по умолчанию: /sdcard/termux-god/<TitleID>/00007000/<MediaID>
EOF
