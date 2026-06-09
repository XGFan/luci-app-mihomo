# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

An OpenWrt LuCI wrapper for [mihomo](https://github.com/MetaCubeX/mihomo) (Clash.Meta), shipped as **two `arch=all` ipks**:

- `mihomo` — the service package: UCI shim + procd `init.d` + binary auto-install helper.
- `luci-app-mihomo` — a thin LuCI entry that iframes mihomo's own dashboard.

This project deliberately does **not** manage mihomo's binary distribution, geo data, or subscriptions. It only does service control (start/stop/config injection) and provides a LuCI menu entry. No compiler toolchain or OpenWrt SDK is needed to build — packaging is pure `python3` + `tar`.

## Build & CI

```bash
# Build both ipks (output: dist/ipk/<version>/artifacts/*.ipk)
bash scripts/build-openwrt-ipk.sh --version v1.0.0

# Build one package only
bash scripts/build-openwrt-ipk.sh --version v1.0.0 --package mihomo       # or luci-app-mihomo

# Validate skeleton + prepare output dir without building
bash scripts/build-openwrt-ipk.sh --version v1.0.0 --prepare-only
```

`--version` is optional; if omitted it's inferred via `git describe`. There is no separate lint/test command — verification is "the ipk installs and `pidof mihomo` succeeds" (what CI's deploy step checks).

CI is **Woodpecker** (`.woodpecker.yaml`), not GitHub Actions: push to `master` builds both ipks, `scp`s them to `OPENWRT_HOST`, runs `opkg install` + `uci set data_dir` + `restart`, then asserts `pidof mihomo`. Requires secrets `ci_ssh_key` / `openwrt_host` / `openwrt_user` / `bark_token` and env `MIHOMO_DATA_DIR`.

## Two parallel packaging paths — keep them in sync

There are **two independent ways** the ipks can be built, and editing one does not update the other:

1. **`scripts/build-openwrt-ipk.sh`** (canonical, used by CI) — builds ipks directly with a vendored python tar packer. No SDK.
2. **`openwrt/{mihomo,luci-app-mihomo}/Makefile`** (OpenWrt SDK `BuildPackage` recipes) — for building inside an OpenWrt buildroot/feeds.

**Gotcha:** the package control scripts (`postinst` / `prerm` / `postrm` for the service; the LuCI cache-refresh `postinst`/`postrm`) exist in **both** places:
- the script reads them from `openwrt/mihomo/files/*` (service) and generates the LuCI ones inline (`write_luci_cache_refresh_script`);
- the Makefiles embed the same logic in `define Package/.../postinst` blocks.

If you change install/upgrade/removal behavior, update **both** the `openwrt/*/files/*` (or the script's inline generator) **and** the corresponding `Makefile` block, or the SDK build and the CI build will diverge.

## Source-of-truth file layout

- `files/` — payload installed to the router's `/` (init.d script, UCI defaults, fallback `config.yaml`, the install helper). Both build paths copy from here.
- `openwrt/mihomo/` — service package: `Makefile` + control scripts under `files/`.
- `openwrt/luci-app-mihomo/` — LuCI package: `Makefile`, the iframe view (`htdocs/luci-static/resources/view/mihomo/index.js`), menu (`root/usr/share/luci/menu.d/mihomo.json`), and ACL (`root/.../acl.d/luci-app-mihomo.json`). Note the LuCI frontend lives here, **not** under top-level `files/`.

## Core mechanism: UCI override via CLI flags (`files/etc/init.d/mihomo`)

The most non-obvious behavior. On each `start_service`:

1. `config_load mihomo` reads UCI (`enabled`, `data_dir`, `controller_port`, `ui_path`, `secret`).
2. `ensure_binary` — if `${data_dir}/mihomo` is missing/non-exec, it auto-runs `/usr/sbin/mihomo-install-binary`. **An existing binary is never touched/upgraded** here (locking a version = it already exists on disk).
3. procd launches mihomo **directly against the user's config** with UCI injected as mihomo override flags:
   `${data_dir}/mihomo -d ${data_dir} -f ${data_dir}/config.yaml -ext-ctl 0.0.0.0:${controller_port} -ext-ui ${ui_path} -secret ${secret}`.
   `-ext-ctl` / `-ext-ui` / `-secret` take precedence over the same top-level keys in `config.yaml` and persist across mihomo hot-reloads.

Key invariants when touching this code:
- The user's `${data_dir}/config.yaml` is **never modified** — UCI is injected via override flags, not by editing the file. `controller_port`/`ui_path` always carry non-empty UCI defaults so they always win. **`secret` only overrides when UCI sets a non-empty value**: mihomo treats `-secret ""` as no-override, so an empty UCI `secret` defers to whatever `config.yaml` declares (the old generated-file path force-emptied it instead — a deliberate behavior change of this fix).
- **mihomo must run with `-f ${data_dir}/config.yaml`, never with a generated copy.** The dashboard's "reload config" (`PUT /configs`) and "restart core" (`POST /restart`) re-read mihomo's *own* `-f` file. If that file is an ephemeral snapshot, those UI actions silently load stale config and only `/etc/init.d/mihomo restart` ever applies edits. (This was the bug fixed by switching from a generated `/var/run/mihomo.yaml` to the live `config.yaml`.)
- **Only `/etc/config/mihomo` (UCI) is procd-watched**, so changing wrapper settings restarts mihomo to re-apply the override flags. The user's `${data_dir}/config.yaml` is **deliberately not watched** — a bad edit or subscription update must not auto-restart a running mihomo into a failed-to-start state. config.yaml edits apply on the next explicit dashboard "reload config"/"restart core" (or `init.d restart`), when the user is present to react.

`/etc/config/mihomo` and `/etc/mihomo/config.yaml` are declared **conffiles** — preserved across `opkg upgrade`. Removal intentionally leaves user data (binary, geo, configs) in place.

## Binary auto-install (`files/usr/sbin/mihomo-install-binary`)

Downloads from `MetaCubeX/mihomo` GitHub releases into `${data_dir}`. Arch is auto-detected from `uname -m` (override with UCI `binary_arch`); on `x86_64` + auto-detect, `binary_variant` chooses `amd64-compatible` (default) vs `amd64` (V3). `binary_version=latest` queries the GitHub API for the tag. Triggered automatically only when the binary is missing; force a (re)download via `/etc/init.d/mihomo update [VERSION]`.

## LuCI entry

`index.js` builds the iframe URL **client-side** from UCI (`//<hostname>:<controller_port>/<ui_path>/`) — changing UCI port/path takes effect on page refresh, no rebuild. The menu's `fallbackTarget` (`:9090/ui/`) is hardcoded and won't track non-default UCI ports.
