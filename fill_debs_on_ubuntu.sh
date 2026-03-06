#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
BUNDLE_DIR="${ROOT_DIR}/bundle"
DEB_DIR="${BUNDLE_DIR}/debs"
OFFLINE_DIR="${ROOT_DIR}/offline"
APT_WORK_ROOT="${ROOT_DIR}/.apt-work"
META_FILE="${BUNDLE_DIR}/metadata.txt"

if [[ "$(id -u)" -eq 0 ]]; then
  SUDO_CMD=()
else
  if ! command -v sudo >/dev/null 2>&1; then
    echo "This script requires root privileges or sudo." >&2
    exit 1
  fi
  SUDO_CMD=(sudo)
fi

run_as_root() {
  "${SUDO_CMD[@]}" "$@"
}

log_info() {
  echo "[$(date '+%H:%M:%S')] [INFO] $*"
}

log_warn() {
  echo "[$(date '+%H:%M:%S')] [WARN] $*"
}

check_cmd() {
  local cmd="$1"
  if ! command -v "${cmd}" >/dev/null 2>&1; then
    echo "Missing required command: ${cmd}" >&2
    exit 1
  fi
}

normalize_arch() {
  case "$1" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armhf|armv7l) echo "armhf" ;;
    i386|i686) echo "i386" ;;
    *) echo "$1" ;;
  esac
}

default_version_for_codename() {
  case "$1" in
    bionic) echo "18.04" ;;
    focal) echo "20.04" ;;
    jammy) echo "22.04" ;;
    noble) echo "24.04" ;;
    oracular) echo "24.10" ;;
    plucky) echo "25.04" ;;
    *) echo "" ;;
  esac
}

sanitize_token() {
  echo "$1" | sed 's/[^0-9A-Za-z._-]/_/g'
}

usage() {
  cat <<'EOF'
Usage:
  ./fill_debs_on_ubuntu.sh [options]

Options:
  --target-codename <codename>         Target Ubuntu codename (e.g. jammy, noble)
  --target-version <version>           Target Ubuntu version label (e.g. 22.04.3)
  --target-arch <arch>                 Target architecture (amd64, arm64, ...)
  --target-mirror <url>                Target Ubuntu mirror (default: http://archive.ubuntu.com/ubuntu)
  --target-security-mirror <url>       Target security mirror (default: http://security.ubuntu.com/ubuntu)
  --target-components "<components>"   Components list (default: "main universe")
  --skip-host-setup                    Skip `apt-get install` of host helper tools
  --keep-apt-workdir                   Keep temporary isolated apt workspace
  -h, --help                           Show this help

Notes:
  - This script expects existing bundle archives under bundle/archives.
  - It refreshes bundle/debs and re-packs a new final tarball.
EOF
}

for arg in "$@"; do
  if [[ "${arg}" == "-h" || "${arg}" == "--help" ]]; then
    usage
    exit 0
  fi
done

read_meta_value() {
  local key="$1"
  if [[ ! -f "${META_FILE}" ]]; then
    return 0
  fi
  awk -F= -v target_key="${key}" '$1 == target_key {print substr($0, index($0, "=") + 1); exit}' "${META_FILE}"
}

prepare_apt_context() {
  APT_CONTEXT_DIR="${APT_WORK_ROOT}/${TARGET_CODENAME}-${TARGET_ARCH}"
  APT_SOURCES_LIST="${APT_CONTEXT_DIR}/sources.list"
  APT_LISTS_DIR="${APT_CONTEXT_DIR}/lists"
  APT_ARCHIVES_DIR="${APT_CONTEXT_DIR}/archives"
  APT_STATUS_FILE="${APT_CONTEXT_DIR}/status"

  rm -rf "${APT_CONTEXT_DIR}"
  mkdir -p "${APT_LISTS_DIR}/partial" "${APT_ARCHIVES_DIR}/partial"
  : > "${APT_STATUS_FILE}"

  cat > "${APT_SOURCES_LIST}" <<EOF
deb [arch=${TARGET_ARCH}] ${TARGET_MIRROR} ${TARGET_CODENAME} ${TARGET_COMPONENTS}
deb [arch=${TARGET_ARCH}] ${TARGET_MIRROR} ${TARGET_CODENAME}-updates ${TARGET_COMPONENTS}
deb [arch=${TARGET_ARCH}] ${TARGET_SECURITY_MIRROR} ${TARGET_CODENAME}-security ${TARGET_COMPONENTS}
EOF

  APT_TOOL_OPTS=(
    -o "APT::Architecture=${TARGET_ARCH}"
    -o "Dir::Etc::sourcelist=${APT_SOURCES_LIST}"
    -o "Dir::Etc::sourceparts=-"
    -o "Dir::State::status=${APT_STATUS_FILE}"
    -o "Dir::State::lists=${APT_LISTS_DIR}"
    -o "Dir::Cache::archives=${APT_ARCHIVES_DIR}"
    -o "Acquire::Languages=none"
    -o "Debug::NoLocking=1"
  )
  if [[ -f /etc/apt/trusted.gpg ]]; then
    APT_TOOL_OPTS+=(-o "Dir::Etc::trusted=/etc/apt/trusted.gpg")
  fi
  if [[ -d /etc/apt/trusted.gpg.d ]]; then
    APT_TOOL_OPTS+=(-o "Dir::Etc::trustedparts=/etc/apt/trusted.gpg.d")
  fi
}

target_apt_get() {
  apt-get "${APT_TOOL_OPTS[@]}" "$@"
}

target_apt_cache() {
  apt-cache "${APT_TOOL_OPTS[@]}" "$@"
}

if [[ ! -d "${BUNDLE_DIR}" ]]; then
  echo "Missing bundle directory: ${BUNDLE_DIR}" >&2
  echo "Run ./prepare_online_bundle.sh first." >&2
  exit 1
fi

required_archives=(
  "${BUNDLE_DIR}/archives/oh-my-zsh.tar.gz"
  "${BUNDLE_DIR}/archives/zsh-autosuggestions.tar.gz"
  "${BUNDLE_DIR}/archives/zsh-completions.tar.gz"
  "${BUNDLE_DIR}/archives/zsh-syntax-highlighting.tar.gz"
  "${BUNDLE_DIR}/archives/powerlevel10k.tar.gz"
)
for archive in "${required_archives[@]}"; do
  if [[ ! -f "${archive}" ]]; then
    echo "Missing required archive: ${archive}" >&2
    exit 1
  fi
done

if [[ ! -f "${OFFLINE_DIR}/install_offline.sh" || ! -f "${OFFLINE_DIR}/zshrc.template" ]]; then
  echo "Missing offline installer files under ${OFFLINE_DIR}" >&2
  exit 1
fi

HOST_OS_ID="unknown"
HOST_OS_PRETTY="unknown"
HOST_OS_VERSION_ID="unknown"
HOST_OS_CODENAME="unknown"
if [[ -r /etc/os-release ]]; then
  # shellcheck disable=SC1091
  source /etc/os-release
  HOST_OS_ID="${ID:-unknown}"
  HOST_OS_PRETTY="${PRETTY_NAME:-unknown}"
  HOST_OS_VERSION_ID="${VERSION_ID:-unknown}"
  HOST_OS_CODENAME="${VERSION_CODENAME:-unknown}"
fi

meta_codename="$(read_meta_value target_codename)"
meta_version="$(read_meta_value target_version)"
meta_arch="$(read_meta_value target_arch)"
meta_mirror="$(read_meta_value target_mirror)"
meta_security_mirror="$(read_meta_value target_security_mirror)"
meta_components="$(read_meta_value target_components)"

TARGET_CODENAME="${TARGET_CODENAME:-${meta_codename:-}}"
TARGET_VERSION="${TARGET_VERSION:-${meta_version:-}}"
TARGET_ARCH="${TARGET_ARCH:-${meta_arch:-}}"
TARGET_MIRROR="${TARGET_MIRROR:-${meta_mirror:-http://archive.ubuntu.com/ubuntu}}"
TARGET_SECURITY_MIRROR="${TARGET_SECURITY_MIRROR:-${meta_security_mirror:-http://security.ubuntu.com/ubuntu}}"
TARGET_COMPONENTS="${TARGET_COMPONENTS:-${meta_components:-main universe}}"
SKIP_HOST_SETUP=0
KEEP_APT_WORKDIR=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-codename)
      TARGET_CODENAME="$2"
      shift 2
      ;;
    --target-version)
      TARGET_VERSION="$2"
      shift 2
      ;;
    --target-arch)
      TARGET_ARCH="$2"
      shift 2
      ;;
    --target-mirror)
      TARGET_MIRROR="$2"
      shift 2
      ;;
    --target-security-mirror)
      TARGET_SECURITY_MIRROR="$2"
      shift 2
      ;;
    --target-components)
      TARGET_COMPONENTS="$2"
      shift 2
      ;;
    --skip-host-setup)
      SKIP_HOST_SETUP=1
      shift
      ;;
    --keep-apt-workdir)
      KEEP_APT_WORKDIR=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

check_cmd apt-get
check_cmd apt-cache
check_cmd awk
check_cmd grep
check_cmd sort
check_cmd sed
check_cmd find
check_cmd tar

if [[ -z "${TARGET_CODENAME}" || "${TARGET_CODENAME}" == "unknown" ]]; then
  TARGET_CODENAME="${HOST_OS_CODENAME}"
fi
if [[ -z "${TARGET_CODENAME}" || "${TARGET_CODENAME}" == "unknown" ]]; then
  echo "Cannot determine target codename. Use --target-codename." >&2
  exit 1
fi

if [[ -z "${TARGET_ARCH}" ]]; then
  TARGET_ARCH="$(dpkg --print-architecture 2>/dev/null || uname -m)"
fi
TARGET_ARCH="$(normalize_arch "${TARGET_ARCH}")"

if [[ -z "${TARGET_VERSION}" ]]; then
  if [[ "${TARGET_CODENAME}" == "${HOST_OS_CODENAME}" && "${HOST_OS_VERSION_ID}" != "unknown" ]]; then
    TARGET_VERSION="${HOST_OS_VERSION_ID}"
  else
    TARGET_VERSION="$(default_version_for_codename "${TARGET_CODENAME}")"
  fi
fi
TARGET_VERSION="${TARGET_VERSION:-unknown}"

log_info "Host OS: ${HOST_OS_PRETTY}"
log_info "Target OS: ubuntu ${TARGET_VERSION} (${TARGET_CODENAME}), arch=${TARGET_ARCH}"
log_info "Target mirrors: main=${TARGET_MIRROR}, security=${TARGET_SECURITY_MIRROR}"
log_info "Long-running steps ahead: apt metadata refresh and package download."
log_info "If mirror/network is unstable, download may take longer."

APT_CONTEXT_DIR=""
APT_SOURCES_LIST=""
APT_LISTS_DIR=""
APT_ARCHIVES_DIR=""
APT_STATUS_FILE=""
declare -a APT_TOOL_OPTS=()

cleanup() {
  if [[ "${KEEP_APT_WORKDIR}" -eq 0 && -n "${APT_CONTEXT_DIR}" ]]; then
    rm -rf "${APT_CONTEXT_DIR}"
    rmdir "${APT_WORK_ROOT}" 2>/dev/null || true
  fi
}
trap cleanup EXIT

if [[ "${SKIP_HOST_SETUP}" -eq 0 ]]; then
  log_info "[1/5] Installing helper tools on online host"
  run_as_root apt-get update
  run_as_root apt-get install -y ca-certificates tar
else
  log_info "[1/5] Skipping host helper setup (--skip-host-setup)"
fi

log_info "[2/5] Refreshing target package metadata (isolated apt context)"
log_info "This step may take several minutes on slower mirrors."
prepare_apt_context
target_apt_get update

log_info "[3/5] Downloading zsh direct dependency deb files"
mapfile -t dep_packages < <({
  echo "zsh"
  target_apt_cache depends --no-recommends --no-suggests zsh \
    | awk '/^[[:space:]]*(PreDepends|Depends):/ {print $2}'
} | sed 's/:any$//' | sed 's/[<>]//g' | grep -v '^libc6$' | sort -u)

if [[ ${#dep_packages[@]} -eq 0 ]]; then
  echo "Failed to resolve zsh dependency list for target: ${TARGET_CODENAME}/${TARGET_ARCH}" >&2
  exit 1
fi

mkdir -p "${DEB_DIR}"
rm -f "${DEB_DIR}"/*.deb

declare -a failed_packages=()
pushd "${DEB_DIR}" >/dev/null
log_info "Resolved ${#dep_packages[@]} dependency package(s). Starting local .deb download..."
for pkg in "${dep_packages[@]}"; do
  candidate="$(target_apt_cache policy "${pkg}" | awk '/Candidate:/ {c=$2} END {print c}')"
  if [[ -z "${candidate}" || "${candidate}" == "(none)" ]]; then
    log_warn "Skipping ${pkg} (no candidate in target repository)"
    failed_packages+=("${pkg}=<none>")
    continue
  fi
  log_info "Downloading deb: ${pkg}=${candidate}"
  if ! target_apt_get download "${pkg}=${candidate}"; then
    failed_packages+=("${pkg}=${candidate}")
  fi
done
popd >/dev/null

log_info "[4/5] Syncing installer files into bundle"
cp "${OFFLINE_DIR}/install_offline.sh" "${BUNDLE_DIR}/install_offline.sh"
cp "${OFFLINE_DIR}/zshrc.template" "${BUNDLE_DIR}/zshrc.template"
chmod +x "${BUNDLE_DIR}/install_offline.sh"

{
  echo "created_at_utc=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
  echo "host_os=${HOST_OS_PRETTY}"
  echo "host_os_id=${HOST_OS_ID}"
  echo "host_os_version=${HOST_OS_VERSION_ID}"
  echo "host_os_codename=${HOST_OS_CODENAME}"
  echo "target_os=ubuntu"
  echo "target_version=${TARGET_VERSION}"
  echo "target_codename=${TARGET_CODENAME}"
  echo "target_arch=${TARGET_ARCH}"
  echo "target_mirror=${TARGET_MIRROR}"
  echo "target_security_mirror=${TARGET_SECURITY_MIRROR}"
  echo "target_components=${TARGET_COMPONENTS}"
  if [[ ${#failed_packages[@]} -eq 0 ]]; then
    echo "failed_deb_downloads=none"
  else
    echo "failed_deb_downloads=${failed_packages[*]}"
  fi
} >"${META_FILE}"

log_info "[5/5] Creating final offline tarball"
timestamp="$(date '+%Y%m%d-%H%M%S')"
safe_target_version="$(sanitize_token "${TARGET_VERSION}")"
safe_target_codename="$(sanitize_token "${TARGET_CODENAME}")"
safe_target_arch="$(sanitize_token "${TARGET_ARCH}")"
final_tarball="${ROOT_DIR}/zsh-offline-bundle-ubuntu${safe_target_version}-${safe_target_codename}-${safe_target_arch}-${timestamp}.tar.gz"
tar -czf "${final_tarball}" -C "${BUNDLE_DIR}" .

deb_count="$(find "${DEB_DIR}" -type f -name '*.deb' | wc -l | tr -d ' ')"
log_info "Offline bundle ready: ${final_tarball}"
log_info "Downloaded .deb count: ${deb_count}"
if [[ ${#failed_packages[@]} -gt 0 ]]; then
  log_warn "Failed package downloads: ${failed_packages[*]}"
fi
if [[ "${KEEP_APT_WORKDIR}" -eq 1 ]]; then
  log_info "Isolated apt workspace kept at: ${APT_CONTEXT_DIR}"
fi
