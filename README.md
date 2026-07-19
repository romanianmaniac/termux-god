# termux-god

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Convert **Xbox 360 `.iso` disc images into the GOD (Games On Demand) format**,
straight from your phone in **[Termux](https://termux.dev)**. No GUI, no
Termux-X11, no APK — just one command in the terminal.

`termux-god` is a thin wrapper around the excellent Rust tool
[`iliazeus/iso2god-rs`](https://github.com/iliazeus/iso2god-rs): the installer
builds it natively on the device, and the `termux-god` command adds a sensible
default output path, a byte-based progress bar, and up-front title detection.

---

## What GOD is and why this works

An Xbox 360 reads "Games On Demand" titles from a USB/HDD as a package of
plain files — no optical drive required. The console verifies integrity through
a **tree of SHA-1 hashes**, so a GOD package is not just the raw ISO renamed; it
has to be re-laid-out and re-hashed. That is exactly what the conversion does:

| Layer | Size | Contains |
|-------|------|----------|
| **Block** | `0x1000` (4 KiB) | raw ISO data |
| **Subpart** | 204 blocks | one hash table (SHA-1 per block) + 204 data blocks |
| **Part** (`Data0000`, `Data0001`, …) | 203 subparts | a master hash table (MHT) + 203 subparts |

The hashes chain upward: every block hash rolls into its subpart's hash table,
every subpart table hash rolls into the part's master hash table (MHT), the MHTs
of all parts are chained back-to-front, and the final top hash is written into
the **CON header** — a ~`0xB000`-byte metadata blob (built from an
`empty_live.bin` template) that carries the Title ID, Media ID, content type
(`0x7000` = Games on Demand), the game name in UTF-16BE, an icon, and a SHA-1
over its own payload. When the console recomputes this tree and it matches, the
game is accepted. Get one byte or one offset wrong and the disc won't boot — which
is the whole reason we don't reimplement it (see below).

The ISO side uses the **XGD/GDF** layout (2048-byte sectors, a volume descriptor
that locates the game partition's root offset). `--trim` walks the directory
tree to find the highest sector actually used and drops the unused tail, so the
output is smaller.

All of the above — XGD/XEX parsing, the hash tree, the CON header template, trim,
and the built-in Title-ID→name database — is implemented in **iso2god-rs**. This
repo does **not** reimplement any of it.

## What this repo adds

`iso2god-rs` is a great Rust program but a raw `cargo` binary. `termux-god`
makes it pleasant to use on a phone:

- **`install.sh`** — builds iso2god-rs natively in Termux and installs it.
- **`termux-god`** — a wrapper that supplies a default `/sdcard` output path,
  checks storage access, shows title info before converting, and renders a clean
  progress bar (upstream only prints `writing part files: N/M`).

## Why it builds cleanly in Termux

Rust installs in Termux with `pkg install rust`, and every **runtime** dependency
of iso2god-rs is pure Rust (`anyhow`, `bitflags`, `byteorder`, `clap`,
`num_enum`, `rayon`, `sha1`) — no C toolchain, no OpenSSL. The only heavy
dependency, `reqwest` (which pulls in TLS and is painful to build on Android), is
a **dev-dependency** used to regenerate the title database; `cargo build
--release --bin iso2god` never compiles it. The upstream version we build is
pinned in [`VERSION`](VERSION).

---

## Requirements

- Android + [Termux](https://f-droid.org/packages/com.termux/) (the F-Droid
  build is recommended)
- Shared-storage access: run `termux-setup-storage` once
- Roughly 2× the ISO size in free space (source + output)

## Install

```bash
pkg install -y git
git clone https://github.com/romanianmaniac/termux-god.git
cd termux-god
bash install.sh
```

This installs `rust` and `git`, builds `iso2god`, and drops two commands into
`$PREFIX/bin`: `iso2god-bin` (the upstream binary) and `termux-god` (the wrapper).

## Usage

```bash
termux-god <game.iso> [options]
```

| Option           | Description                                             |
|------------------|---------------------------------------------------------|
| `--trim`         | trim unused tail off the ISO (smaller output)           |
| `--out DIR`      | output directory (default: `/sdcard/termux-god`)        |
| `--threads N`    | worker threads (default: number of CPU cores)           |
| `--no-progress`  | disable the progress bar                                |
| `-h`, `--help`   | show help                                               |

Example:

```bash
termux-god /sdcard/Download/Halo3.iso --trim
```

```
▸ Reading ISO metadata…
  Title ID: 4D5307E6
  Name:     Halo 3
  Type:     Games on Demand
▸ Converting → GOD…
  [############################] 100%  done
✓ Done: /sdcard/termux-god/4D5307E6
```

## Output layout & running it on the console

```
/sdcard/termux-god/<TitleID>/00007000/<MediaID>          ← CON header
/sdcard/termux-god/<TitleID>/00007000/<MediaID>.data/    ← Data0000, Data0001 …
```

To make the console see the game, copy the whole `<TitleID>` folder to:

```
Content/0000000000000000/<TitleID>/
```

on a USB drive or HDD formatted for the console.

## How the wrapper works internally

1. Runs `iso2god-bin --dry-run` to read metadata and prints Title ID / name
   (the name comes from iso2god-rs's built-in game database — nothing to maintain
   here).
2. Runs the conversion into an isolated temporary directory, hiding the upstream
   output in a log and drawing its own progress bar from the number of bytes
   written (denominator = source ISO size, so with `--trim` the bar honestly
   reaches 100% only when the process finishes).
3. On success, moves the finished `<TitleID>` folder into the output directory;
   on error or `Ctrl+C`, a `trap` kills the worker and removes the partial output.

## Default thread count

Upstream defaults to a single thread (a safety choice for Windows and spinning
hard drives). Phone storage is flash, so `termux-god` defaults `-j` to the number
of CPU cores for a big speed-up. Override with `--threads N` if you prefer.

## Credits

All the hard work — XGD/XEX parsing, the hierarchical SHA-1 tree, the CON header,
trim, and the title database — belongs to
[iso2god-rs](https://github.com/iliazeus/iso2god-rs) by **iliazeus**, itself a
rewrite of [iso2god-cli](https://github.com/eliecharra/iso2god-cli). This repo is
just the Termux packaging around it.

## License

This project (the `termux-god` wrapper and installer) is released under the
[MIT License](LICENSE).

The tool it builds, [iso2god-rs](https://github.com/iliazeus/iso2god-rs), is also
MIT-licensed (© 2023 Ilia Pozdnyakov). It is **not** redistributed in this
repository — `install.sh` fetches and builds it on the device — so the two
licenses simply coexist, with no additional obligations.
