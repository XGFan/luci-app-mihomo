#!/usr/bin/env bash
#
# build-openwrt-ipk.sh — 构建 mihomo wrapper 的两个 OpenWrt ipk
#
# 两个包都是 arch=all（不打包二进制和 geo 数据）。
#
# 用法:
#   ./scripts/build-openwrt-ipk.sh --version v1.0.0
#   ./scripts/build-openwrt-ipk.sh --version v1.0.0 --package mihomo
#   ./scripts/build-openwrt-ipk.sh --version v1.0.0 --prepare-only
#

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
OPENWRT_DIR="${REPO_ROOT}/openwrt"
DEFAULT_OUTPUT_BASE="${REPO_ROOT}/dist/ipk"

VERSION=""
PACKAGE="all"
OUTPUT_BASE="${DEFAULT_OUTPUT_BASE}"
PREPARE_ONLY=false

ALL_PACKAGES=(
  "mihomo"
  "luci-app-mihomo"
)

usage() {
  cat <<EOF
用法: $(basename "$0") [选项]

选项:
  -v, --version VERSION    版本号 (如 v1.0.0)，必填或从 git 推断
  -p, --package NAME       仅构建指定包: mihomo | luci-app-mihomo | all (默认 all)
  -o, --output-dir DIR     输出根目录 (默认: dist/ipk/)
      --prepare-only       仅校验 skeleton 并准备输出根目录
  -h, --help               显示帮助信息

输出:
  默认输出根目录固定为 dist/ipk/<version>/
  两个包均为 arch=all（不含二进制和 geo 数据）

示例:
  $(basename "$0") --help
  $(basename "$0") --version v1.0.0 --prepare-only
  $(basename "$0") --version v1.0.0 --package mihomo
EOF
  exit 0
}

require_command() {
  local command_name="$1"

  if ! command -v "${command_name}" >/dev/null 2>&1; then
    echo "错误: 缺少依赖工具 '${command_name}'" >&2
    exit 4
  fi
}

infer_version() {
  if [[ -d "${REPO_ROOT}/.git" ]] && command -v git &>/dev/null; then
    git -C "${REPO_ROOT}" describe --tags --always --dirty 2>/dev/null || echo "v0.0.0-dev"
  else
    echo "v0.0.0-dev"
  fi
}

validate_version() {
  local version="$1"

  if [[ ! "${version}" =~ ^v[0-9]+\.[0-9]+\.[0-9]+([-.][A-Za-z0-9._-]+)?$ ]]; then
    echo "警告: 版本号 '${version}' 不符合语义化版本格式 (vX.Y.Z)" >&2
  fi
}

selected_packages() {
  case "${PACKAGE}" in
    all)
      printf '%s\n' "${ALL_PACKAGES[@]}"
      ;;
    mihomo|luci-app-mihomo)
      printf '%s\n' "${PACKAGE}"
      ;;
    *)
      echo "错误: 不支持的包名 '${PACKAGE}'" >&2
      exit 2
      ;;
  esac
}

require_file() {
  local path="$1"

  if [[ ! -f "${path}" ]]; then
    echo "错误: 缺少 package skeleton 文件: ${path#${REPO_ROOT}/}" >&2
    exit 3
  fi
}

create_ustar_gzip_archive() {
  local output_path="$1"
  local root_path="$2"
  local include_root_dot=0
  shift 2

  if [[ "${1:-}" == "--include-root-dot" ]]; then
    include_root_dot=1
    shift
  fi

  python3 - "$output_path" "$root_path" "$include_root_dot" "$@" <<'PY'
import gzip
import pathlib
import tarfile
import sys

output = pathlib.Path(sys.argv[1])
root = pathlib.Path(sys.argv[2])
include_root_dot = sys.argv[3] == "1"
members = [pathlib.Path(item) for item in sys.argv[4:]]

if not members:
    raise SystemExit("tar archive requires at least one member")

def archive_name(relative_path: pathlib.Path) -> str:
    return f"./{relative_path.as_posix()}"

def add_path(tf: tarfile.TarFile, relative_path: pathlib.Path) -> None:
    source_path = root / relative_path
    stat = source_path.lstat()

    tar_info = tarfile.TarInfo(archive_name(relative_path))
    tar_info.uid = 0
    tar_info.gid = 0
    tar_info.uname = "root"
    tar_info.gname = "root"
    tar_info.mtime = 0
    tar_info.mode = stat.st_mode & 0o7777

    if source_path.is_dir():
      tar_info.type = tarfile.DIRTYPE
      tar_info.size = 0
      tf.addfile(tar_info)
      for child in sorted(source_path.iterdir(), key=lambda p: p.name):
          add_path(tf, relative_path / child.name)
      return

    if source_path.is_symlink():
      tar_info.type = tarfile.SYMTYPE
      tar_info.size = 0
      tar_info.linkname = source_path.readlink().as_posix()
      tf.addfile(tar_info)
      return

    tar_info.size = stat.st_size
    with source_path.open('rb') as f:
        tf.addfile(tar_info, f)

with output.open('wb') as raw:
    with gzip.GzipFile(filename='', mode='wb', fileobj=raw, mtime=0) as gz:
        with tarfile.open(fileobj=gz, mode='w', format=tarfile.USTAR_FORMAT) as tf:
            if include_root_dot:
                root_info = tarfile.TarInfo('.')
                root_info.type = tarfile.DIRTYPE
                root_info.size = 0
                root_info.mode = 0o755
                root_info.uid = 0
                root_info.gid = 0
                root_info.uname = "root"
                root_info.gname = "root"
                root_info.mtime = 0
                tf.addfile(root_info)
            for member in members:
                add_path(tf, member)
PY
}

ensure_package_skeleton() {
  local package="$1"

  case "${package}" in
    mihomo)
      require_file "${OPENWRT_DIR}/mihomo/Makefile"
      require_file "${OPENWRT_DIR}/mihomo/files/postinst"
      require_file "${OPENWRT_DIR}/mihomo/files/prerm"
      require_file "${OPENWRT_DIR}/mihomo/files/postrm"
      require_file "${OPENWRT_DIR}/mihomo/files/conffiles"
      require_file "${REPO_ROOT}/files/etc/init.d/mihomo"
      require_file "${REPO_ROOT}/files/etc/config/mihomo"
      require_file "${REPO_ROOT}/files/etc/mihomo/config.yaml"
      require_file "${REPO_ROOT}/files/usr/sbin/mihomo-install-binary"
      ;;
    luci-app-mihomo)
      require_file "${OPENWRT_DIR}/luci-app-mihomo/Makefile"
      require_file "${OPENWRT_DIR}/luci-app-mihomo/root/usr/share/luci/menu.d/mihomo.json"
      require_file "${OPENWRT_DIR}/luci-app-mihomo/root/usr/share/rpcd/acl.d/luci-app-mihomo.json"
      require_file "${OPENWRT_DIR}/luci-app-mihomo/htdocs/luci-static/resources/view/mihomo/index.js"
      ;;
    *)
      echo "错误: 未知 package skeleton: ${package}" >&2
      exit 2
      ;;
  esac
}

prepare_output_root() {
  local version="$1"
  local output_root="${OUTPUT_BASE%/}/${version}"

  mkdir -p "${output_root}"
  printf '%s\n' "${output_root}"
}

build_locally() {
  local output_root="$1"
  local package="$2"

  require_command tar
  require_command python3

  case "${package}" in
    mihomo)
      build_service_ipk_locally "${output_root}"
      ;;
    luci-app-mihomo)
      build_luci_shell_ipk_locally "${output_root}"
      ;;
    *)
      echo "错误: 本地 packager 不支持 ${package}" >&2
      exit 12
      ;;
  esac
}

write_luci_cache_refresh_script() {
  local output_path="$1"

  cat > "${output_path}" <<'EOF'
#!/bin/sh

[ -n "${IPKG_INSTROOT:-}" ] && exit 0

rm -f /tmp/luci-indexcache.*
rm -rf /tmp/luci-modulecache/
/etc/init.d/rpcd reload >/dev/null 2>&1 || true

exit 0
EOF
  chmod 0755 "${output_path}"
}

build_service_ipk_locally() {
  local output_root="$1"
  local clean_version="${VERSION#v}"
  local package_arch="all"
  local package_version="${clean_version}-1"
  local artifact_dir="${output_root}/artifacts"
  local artifact_name="mihomo_${clean_version}_${package_arch}.ipk"
  local artifact_path="${artifact_dir}/${artifact_name}"
  local workspace
  workspace="$(mktemp -d "${output_root}/build.XXXXXX")"
  local data_root="${workspace}/data"
  local control_root="${workspace}/control"
  local files_root="${REPO_ROOT}/files"
  local installed_size

  mkdir -p "${artifact_dir}" "${control_root}"

  # Init script
  mkdir -p "${data_root}/etc/init.d"
  cp "${files_root}/etc/init.d/mihomo" "${data_root}/etc/init.d/mihomo"
  chmod 0755 "${data_root}/etc/init.d/mihomo"

  # UCI defaults (conffile, preserved on upgrade)
  mkdir -p "${data_root}/etc/config"
  cp "${files_root}/etc/config/mihomo" "${data_root}/etc/config/mihomo"
  chmod 0644 "${data_root}/etc/config/mihomo"

  # Default mihomo config.yaml fallback (conffile, preserved on upgrade)
  mkdir -p "${data_root}/etc/mihomo"
  cp "${files_root}/etc/mihomo/config.yaml" "${data_root}/etc/mihomo/config.yaml"
  chmod 0644 "${data_root}/etc/mihomo/config.yaml"

  # Binary auto-install helper
  mkdir -p "${data_root}/usr/sbin"
  cp "${files_root}/usr/sbin/mihomo-install-binary" "${data_root}/usr/sbin/mihomo-install-binary"
  chmod 0755 "${data_root}/usr/sbin/mihomo-install-binary"

  # Control scripts
  cp "${OPENWRT_DIR}/mihomo/files/postinst" "${control_root}/postinst"
  cp "${OPENWRT_DIR}/mihomo/files/prerm" "${control_root}/prerm"
  cp "${OPENWRT_DIR}/mihomo/files/postrm" "${control_root}/postrm"
  cp "${OPENWRT_DIR}/mihomo/files/conffiles" "${control_root}/conffiles"
  chmod 0755 "${control_root}/postinst" "${control_root}/prerm" "${control_root}/postrm"
  chmod 0644 "${control_root}/conffiles"

  installed_size="$(du -sk "${data_root}" | awk '{print $1}')"

  cat > "${control_root}/control" <<EOF
Package: mihomo
Version: ${package_version}
Architecture: ${package_arch}
Maintainer: luci-app-mihomo project
License: GPL-3.0
Section: net
Priority: optional
Installed-Size: ${installed_size}
Description: Mihomo wrapper service (UCI shim + procd init.d). Binary and geo data not bundled.
EOF

  printf '2.0\n' > "${workspace}/debian-binary"
  create_ustar_gzip_archive "${workspace}/control.tar.gz" "${control_root}" --include-root-dot control postinst prerm postrm conffiles
  create_ustar_gzip_archive "${workspace}/data.tar.gz" "${data_root}" --include-root-dot etc usr

  rm -f "${artifact_path}"
  create_ustar_gzip_archive "${artifact_path}" "${workspace}" debian-binary data.tar.gz control.tar.gz

  rm -rf "${workspace}"

  echo "✓ 本地 ipk 构建完成: ${artifact_path}"
}

build_luci_shell_ipk_locally() {
  local output_root="$1"
  local clean_version="${VERSION#v}"
  local package_arch="all"
  local package_version="${clean_version}-1"
  local artifact_dir="${output_root}/artifacts"
  local artifact_name="luci-app-mihomo_${clean_version}_${package_arch}.ipk"
  local artifact_path="${artifact_dir}/${artifact_name}"
  local workspace
  workspace="$(mktemp -d "${output_root}/build.XXXXXX")"
  local data_root="${workspace}/data"
  local control_root="${workspace}/control"
  local installed_size

  mkdir -p \
    "${artifact_dir}" \
    "${data_root}/www/luci-static/resources/view/mihomo" \
    "${data_root}/usr/share/luci/menu.d" \
    "${data_root}/usr/share/rpcd/acl.d" \
    "${control_root}"

  cp "${OPENWRT_DIR}/luci-app-mihomo/htdocs/luci-static/resources/view/mihomo/index.js" \
    "${data_root}/www/luci-static/resources/view/mihomo/index.js"
  cp "${OPENWRT_DIR}/luci-app-mihomo/root/usr/share/luci/menu.d/mihomo.json" \
    "${data_root}/usr/share/luci/menu.d/mihomo.json"
  cp "${OPENWRT_DIR}/luci-app-mihomo/root/usr/share/rpcd/acl.d/luci-app-mihomo.json" \
    "${data_root}/usr/share/rpcd/acl.d/luci-app-mihomo.json"
  chmod 0644 \
    "${data_root}/www/luci-static/resources/view/mihomo/index.js" \
    "${data_root}/usr/share/luci/menu.d/mihomo.json" \
    "${data_root}/usr/share/rpcd/acl.d/luci-app-mihomo.json"

  write_luci_cache_refresh_script "${control_root}/postinst"
  write_luci_cache_refresh_script "${control_root}/postrm"

  installed_size="$(du -sk "${data_root}" | awk '{print $1}')"

  cat > "${control_root}/control" <<EOF
Package: luci-app-mihomo
Version: ${package_version}
Architecture: ${package_arch}
Maintainer: luci-app-mihomo project
License: GPL-3.0
Section: luci
Priority: optional
Depends: luci-base, rpcd
Installed-Size: ${installed_size}
Description: Mihomo LuCI shell entry package (iframe wrapper)
EOF

  printf '2.0\n' > "${workspace}/debian-binary"
  create_ustar_gzip_archive "${workspace}/control.tar.gz" "${control_root}" --include-root-dot control postinst postrm
  create_ustar_gzip_archive "${workspace}/data.tar.gz" "${data_root}" --include-root-dot usr www

  rm -f "${artifact_path}"
  create_ustar_gzip_archive "${artifact_path}" "${workspace}" debian-binary data.tar.gz control.tar.gz

  rm -rf "${workspace}"

  echo "✓ 本地 ipk 构建完成: ${artifact_path}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -v|--version)
      VERSION="$2"
      shift 2
      ;;
    -p|--package)
      PACKAGE="$2"
      shift 2
      ;;
    -o|--output-dir)
      OUTPUT_BASE="$2"
      shift 2
      ;;
    --prepare-only)
      PREPARE_ONLY=true
      shift
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "错误: 未知选项 '$1'" >&2
      exit 1
      ;;
  esac
done

main() {
  if [[ -z "${VERSION}" ]]; then
    VERSION="$(infer_version)"
    echo "自动推断版本号: ${VERSION}"
  fi

  validate_version "${VERSION}"

  mapfile -t packages < <(selected_packages)

  local package
  for package in "${packages[@]}"; do
    ensure_package_skeleton "${package}"
  done

  local output_root
  output_root="$(prepare_output_root "${VERSION}")"

  echo "=========================================="
  echo "OpenWrt packaging workspace 已准备"
  echo "版本: ${VERSION}"
  echo "包: ${packages[*]} (arch=all)"
  echo "输出根目录: ${output_root}"
  echo "=========================================="

  if [[ "${PREPARE_ONLY}" == true ]]; then
    echo "✓ 已完成 skeleton 校验与输出根目录准备"
    return 0
  fi

  for package in "${packages[@]}"; do
    build_locally "${output_root}" "${package}"
  done

  echo "✓ OpenWrt ipk 构建完成"
  echo "产物目录: ${output_root}/artifacts"
}

main "$@"
