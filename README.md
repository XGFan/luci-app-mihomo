# luci-app-mihomo

OpenWrt 上 mihomo (Clash.Meta) 的 LuCI 包装器，仿 dns-switchy 双 ipk 模式。

## 不做什么

- **不打包 mihomo 二进制**：但提供 `/usr/sbin/mihomo-install-binary` 自动从 [MetaCubeX/mihomo releases](https://github.com/MetaCubeX/mihomo/releases) 下载
- **不打包 GeoIP / GeoSite / ASN 数据**：mihomo 自身可按需下载，或你手动拷贝过去
- **不实现订阅管理**：本仓库只做 service 包装与 LuCI iframe 入口

## 二进制自动获取

- 服务首次启动时，若 `${data_dir}/mihomo` 不存在或不可执行，init.d 自动调用 `/usr/sbin/mihomo-install-binary` 下载到 `${data_dir}`
- **二进制已存在则跳过下载**，不会覆盖你手动放置或修改过的版本
- 强制更新到最新版：`/etc/init.d/mihomo update`
- 强制安装指定版本：`/etc/init.d/mihomo update v1.19.24`
- 直接运行 helper：`/usr/sbin/mihomo-install-binary [VERSION]`

架构检测：`uname -m` 自动映射到 mihomo release 命名（`x86_64` → `amd64-compatible`/`amd64`、`aarch64` → `arm64`、`armv7l` → `armv7`、mips/mipsle/mips64/i386 已支持）。
可在 UCI 用 `binary_arch` 强制覆盖、`binary_variant` 控制 x86_64 是 V3 还是 compatible。

## 两个 ipk

| 包 | 内容 | 用途 |
|---|---|---|
| `mihomo` | `/etc/init.d/mihomo`（UCI-driven procd） + `/etc/config/mihomo`（UCI shim） + `/etc/mihomo/config.yaml`（最小 fallback） | 提供 service 控制和 UCI 接口 |
| `luci-app-mihomo` | LuCI 菜单 + iframe view + RPC ACL | 在 LuCI `Services / Mihomo` 嵌入 mihomo 自带 dashboard |

两个包都是 `arch=all`。

## UCI 字段（`/etc/config/mihomo`）

| key | 默认 | 说明 |
|-----|------|------|
| `enabled` | `1` | `0` 禁用服务 |
| `data_dir` | `/etc/mihomo` | mihomo `-d` 工作目录；二进制和 geo 文件位置 |
| `controller_port` | `9090` | external-controller 端口 + LuCI iframe 目标 |
| `ui_path` | `ui` | external-ui 路径段 |
| `secret` | `''` | Clash API secret |
| `binary_version` | `latest` | mihomo release tag（`latest` 走 GitHub API，或固定如 `v1.19.24`） |
| `binary_arch` | `''` | release 架构覆盖；空则按 `uname -m` 自动 |
| `binary_variant` | `compatible` | x86_64 自动检测时使用：`compatible`（V1/V2）或 `v3` |

UCI 字段会在 service 启动时覆盖 `${data_dir}/config.yaml` 顶层的 `external-controller` / `external-ui` / `secret`，写入 `/var/run/mihomo.yaml` 后由 `mihomo -f /var/run/mihomo.yaml -d ${data_dir}` 启动。

## 构建

```bash
bash scripts/build-openwrt-ipk.sh --version v1.0.0
# 产物: dist/ipk/v1.0.0/artifacts/{mihomo,luci-app-mihomo}_*_all.ipk
```

## 部署到 OpenWrt

```bash
scp dist/ipk/v1.0.0/artifacts/*.ipk root@router:/tmp/
ssh root@router 'opkg install /tmp/mihomo_*.ipk /tmp/luci-app-mihomo_*.ipk'

# 路径方案 A —— 沿用现有 /mnt/ext/app/mihomo（推荐，零迁移）
ssh root@router 'uci set mihomo.main.data_dir="/mnt/ext/app/mihomo" && uci commit mihomo && /etc/init.d/mihomo restart'

# 路径方案 B —— 用默认 /etc/mihomo（需把现有 geo 文件搬过去）
ssh root@router 'mv /mnt/ext/app/mihomo/{mihomo,*.dat,*.mmdb,*.metadb,ruleset,ui,meta-backup} /etc/mihomo/'
ssh root@router '/etc/init.d/mihomo restart'

# 路径方案 C —— 让 init.d 自动下载二进制（仅当 ${data_dir}/mihomo 不存在时触发）
ssh root@router '/etc/init.d/mihomo restart'
```

## LuCI 入口

`Services / Mihomo` — iframe 加载 `//<router>:<controller_port>/<ui_path>/`，端口和路径来自 UCI。

## 行为

- `opkg install` 升级时 `/etc/config/mihomo` 与 `/etc/mihomo/config.yaml` 都是 conffile，用户改动保留
- 服务通过 `procd_set_param file /etc/config/mihomo ${data_dir}/config.yaml` 监听 reload；`/etc/init.d/mihomo reload` 会触发重启
- `/etc/init.d/mihomo` 启动时校验 `${data_dir}/mihomo` 可执行 + `${data_dir}/config.yaml` 存在，缺失则 procd 拒绝拉起
