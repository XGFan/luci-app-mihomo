# luci-app-mihomo

OpenWrt 上 [mihomo](https://github.com/MetaCubeX/mihomo)（Clash.Meta）的 LuCI 包装。两个 ipk：service + luci-app，仿 dns-switchy 模式。

不接管 mihomo 的二进制、geo 数据、订阅管理 —— 只做 service 控制和 LuCI 入口。

## 特性

- **UCI 化的 service**：通过 `/etc/config/mihomo` 控制启停、端口、data_dir、secret
- **二进制按需自动下载**：首次启动时若 `${data_dir}/mihomo` 不存在，自动从 [MetaCubeX/mihomo releases](https://github.com/MetaCubeX/mihomo/releases) 拉对应架构的二进制；**已存在则不动**
- **运行时配置注入**：service 启动时从 UCI 读 `external-controller` / `external-ui` / `secret`，注入到 `/var/run/mihomo.yaml`，用户的 `${data_dir}/config.yaml` 不被改写
- **LuCI iframe**：`Services / Mihomo` 菜单嵌入 mihomo 自带 dashboard，URL 由 UCI 端口和路径动态拼接
- **conffile 升级保留**：`opkg upgrade` 时用户对 `/etc/config/mihomo` 与 `/etc/mihomo/config.yaml` 的改动保留
- **Woodpecker CI**：`master` 分支 push 自动构建 + 部署到目标路由器（参见 `.woodpecker.yaml`）

## 快速开始

### 一次性手工安装

```bash
# 在仓库根目录构建
bash scripts/build-openwrt-ipk.sh --version v1.0.0

# 推到路由器
scp dist/ipk/v1.0.0/artifacts/*.ipk root@router:/tmp/
ssh root@router 'opkg install /tmp/mihomo_*.ipk /tmp/luci-app-mihomo_*.ipk'

# 把 data_dir 指向你已有的 mihomo 目录（如果有），否则保持默认 /etc/mihomo
ssh root@router '
  uci set mihomo.main.data_dir="/mnt/ext/app/mihomo" &&
  uci commit mihomo &&
  /etc/init.d/mihomo restart
'
```

> 如果 `${data_dir}` 下没有 `mihomo` 二进制，service 启动时会自动 `wget` 一个对应架构的版本。

### 自动化（Woodpecker CI）

仓库已配置 `.woodpecker.yaml`：每次 push 到 `master` 自动构建两个 ipk 并 ssh 到 `OPENWRT_HOST` 执行 `opkg install` + `uci set data_dir=$MIHOMO_DATA_DIR` + `restart` + `pidof` 健康检查。

需要的 Woodpecker secrets / env：

| 名字 | 来源 | 说明 |
|---|---|---|
| `ci_ssh_key` | secret | 部署用 SSH 私钥 |
| `openwrt_host` | secret | 路由器地址 |
| `openwrt_user` | secret | 部署 ssh 用户（一般 `root`） |
| `bark_token` | secret | 通知用 |
| `MIHOMO_DATA_DIR` | env (明文) | data_dir 强制值，默认 `/mnt/ext/app/mihomo` |

## UCI 配置（`/etc/config/mihomo`）

```
config mihomo 'main'
    option enabled '1'
    option data_dir '/etc/mihomo'
    option controller_port '9090'
    option ui_path 'ui'
    option secret ''
    option binary_version 'latest'
    option binary_arch ''
    option binary_variant 'compatible'
```

| key | 默认 | 说明 |
|-----|------|------|
| `enabled` | `1` | `0` 禁用服务 |
| `data_dir` | `/etc/mihomo` | mihomo `-d` 工作目录，二进制 + geo + ui 都从这里加载 |
| `controller_port` | `9090` | mihomo external-controller 端口 + LuCI iframe 目标端口 |
| `ui_path` | `ui` | external-ui 名称 + LuCI iframe URL 路径段 |
| `secret` | `''` | Clash API secret |
| `binary_version` | `latest` | mihomo release tag。`latest` 走 GitHub API；或写固定 `v1.19.24` |
| `binary_arch` | `''` | release 架构覆盖；空则按 `uname -m` 自动检测 |
| `binary_variant` | `compatible` | 仅 x86_64 + auto-arch 时使用：`compatible`（V1/V2 CPU）或 `v3`（V3 CPU） |

修改 UCI 后：

```sh
uci commit mihomo && /etc/init.d/mihomo restart
```

## 二进制管理

| 触发 | 行为 |
|---|---|
| 首次 `start_service`（`${data_dir}/mihomo` 不可执行） | 自动调 `/usr/sbin/mihomo-install-binary` 下载到 `${data_dir}` |
| 首次 `start_service`（二进制已存在） | **不下载**，直接用现有版本 |
| `/etc/init.d/mihomo update` | 强制下载 UCI 配置的版本到 `${data_dir}/mihomo` |
| `/etc/init.d/mihomo update v1.19.24` | 强制下载指定版本 |
| `/usr/sbin/mihomo-install-binary [VERSION]` | 直接调底层 helper（带 `-h` 看用法） |

架构自动检测映射：

| `uname -m` | mihomo release |
|---|---|
| `x86_64` | `amd64-compatible`（默认）或 `amd64`（设 `binary_variant=v3`） |
| `aarch64` | `arm64` |
| `armv7l` | `armv7` |
| `armv6l` | `armv6` |
| `mips` / `mipsel` | `mips-softfloat` / `mipsle-softfloat` |
| `mips64` / `mips64el` | `mips64` / `mips64le` |
| `i386` / `i686` | `386` |

冷门架构可在 UCI 设 `binary_arch` 显式覆盖。

## 运行时数据流

```
                 ┌────────────────────────┐
/etc/config/mihomo  ─UCI─► init.d (config_load)
                          │   reads enabled, data_dir,
                          │   controller_port, ui_path, secret
                          ▼
                  generate_runtime_config:
                    ┌─ printf top 3 lines from UCI
                    │  external-controller: "0.0.0.0:9090"
                    │  external-ui: "ui"
                    │  secret: "..."
                    └─ sed -E 删除 ${data_dir}/config.yaml 中
                       的同名顶层字段，append 剩余内容
                          ▼
                /var/run/mihomo.yaml
                          ▼
        procd_open_instance:
          ${data_dir}/mihomo -f /var/run/mihomo.yaml -d ${data_dir}
```

`procd_set_param file /etc/config/mihomo ${data_dir}/config.yaml` 让 procd 监听这两个文件，外部 `service mihomo reload` 会重新生成 `/var/run/mihomo.yaml` 并重启实例。

## 仓库结构

```
.
├── .woodpecker.yaml           # CI: build + deploy + notify
├── files/                     # 装到路由器 / 下的内容
│   ├── etc/
│   │   ├── config/mihomo      # UCI 默认值（conffile）
│   │   ├── init.d/mihomo      # procd 启动脚本
│   │   └── mihomo/config.yaml # 最小可启动 fallback（conffile）
│   └── usr/sbin/mihomo-install-binary  # GitHub release 下载器
├── openwrt/
│   ├── mihomo/                # service ipk Makefile + control 脚本
│   │   ├── Makefile
│   │   └── files/{conffiles,postinst,prerm,postrm}
│   └── luci-app-mihomo/       # luci ipk Makefile + 前端 + 元数据
│       ├── Makefile
│       ├── htdocs/luci-static/resources/view/mihomo/index.js
│       └── root/
│           ├── usr/share/luci/menu.d/mihomo.json
│           └── usr/share/rpcd/acl.d/luci-app-mihomo.json
├── scripts/build-openwrt-ipk.sh  # 本地打包脚本（python3 + tar，无需 OpenWrt SDK）
└── README.md
```

两个 ipk 都是 `arch=all`，不依赖编译工具链。

## LuCI 入口

`Services / Mihomo`：iframe 自动指向 `//<router>:<controller_port>/<ui_path>/`，由 LuCI 客户端读 UCI 后拼接。修改 UCI 端口或路径，刷新 LuCI 页面即可生效。

如果浏览器不支持 iframe（罕见），LuCI 菜单的 `fallbackTarget` 会让点击直接跳到独立页 `//<router>:9090/ui/`。

## 故障排查

- **`/etc/init.d/mihomo restart` 后服务起不来**
  - `logread | grep mihomo` 看 procd 日志
  - 校验 `${data_dir}` 下是否存在可执行 `mihomo` + `config.yaml`
  - 若曾手动改过 `/var/run/mihomo.yaml`，那是运行时生成文件，被 init.d 覆盖
- **iframe 加载失败**
  - 浏览器 devtools 看是否被 `Mixed Content`（http→https）拦
  - 直接在新标签打开 `http://<router>:9090/ui/` 验证 dashboard 本身能开
  - 检查 `uci show mihomo` 的 `controller_port` / `ui_path` 是否对得上 mihomo 实际监听
- **CI deploy 步骤 `pidof mihomo` 失败**
  - 大概率是 `${data_dir}/mihomo` 自动下载失败（GitHub 网络）或 `${data_dir}/config.yaml` 不合法
  - ssh 进路由器手动跑 `/usr/sbin/mihomo-install-binary` 看 wget 错误
- **想锁定 mihomo 版本不被自动升级**
  - 把 `binary_version` 设成具体 tag（`uci set mihomo.main.binary_version='v1.19.24'`），加 `uci commit mihomo`
  - 自动下载只在二进制缺失时触发，**已存在不会重复下载**

## 卸载

```sh
opkg remove luci-app-mihomo mihomo
```

`/etc/config/mihomo`、`/etc/mihomo/config.yaml`、`${data_dir}` 下的 mihomo 二进制和 geo 文件都不会被自动清理（避免误删用户数据）。需要彻底清干净的话 `opkg remove --autoremove` 后手动 `rm` 对应路径。
