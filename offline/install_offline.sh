#!/usr/bin/env bash
set -euo pipefail

BUNDLE_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DEB_DIR="${BUNDLE_DIR}/debs"
ARCHIVE_DIR="${BUNDLE_DIR}/archives"
ZSHRC_TEMPLATE="${BUNDLE_DIR}/zshrc.template"

CURRENT_USER="$(id -un)"
if [[ -n "${TARGET_USER:-}" ]]; then
  TARGET_USER="${TARGET_USER}"
elif [[ -n "${SUDO_USER:-}" && "${SUDO_USER}" != "root" ]]; then
  TARGET_USER="${SUDO_USER}"
else
  TARGET_USER="${CURRENT_USER}"
fi

if [[ -n "${TARGET_HOME:-}" ]]; then
  TARGET_HOME="${TARGET_HOME}"
else
  TARGET_HOME="$(getent passwd "${TARGET_USER}" | cut -d: -f6 || true)"
  TARGET_HOME="${TARGET_HOME:-${HOME}}"
fi

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

if ! id "${TARGET_USER}" >/dev/null 2>&1; then
  echo "Target user does not exist: ${TARGET_USER}" >&2
  exit 1
fi

mkdir -p "${TARGET_HOME}"

backup_if_exists() {
  local path="$1"
  if [[ -e "${path}" ]]; then
    local backup_path="${path}.bak.$(date '+%Y%m%d-%H%M%S')"
    mv "${path}" "${backup_path}"
    echo "Backed up ${path} -> ${backup_path}"
  fi
}

extract_archive() {
  local archive_file="$1"
  local target_dir="$2"
  if [[ ! -f "${archive_file}" ]]; then
    echo "Missing archive: ${archive_file}" >&2
    exit 1
  fi
  mkdir -p "${target_dir}"
  if tar --help 2>&1 | grep -q -- '--warning'; then
    tar --warning=no-unknown-keyword -xzf "${archive_file}" -C "${target_dir}"
  else
    tar -xzf "${archive_file}" -C "${target_dir}"
  fi
  find "${target_dir}" -name '._*' -type f -delete 2>/dev/null || true
}

if [[ ! -d "${DEB_DIR}" ]]; then
  echo "Missing deb directory: ${DEB_DIR}" >&2
  exit 1
fi

if [[ ! -d "${ARCHIVE_DIR}" ]]; then
  echo "Missing archive directory: ${ARCHIVE_DIR}" >&2
  exit 1
fi

mapfile -t deb_files < <(find "${DEB_DIR}" -maxdepth 1 -type f -name '*.deb' | sort)
if [[ ${#deb_files[@]} -eq 0 ]]; then
  echo "No deb files found in ${DEB_DIR}" >&2
  exit 1
fi

echo "[1/4] Installing zsh from local deb packages"
run_as_root dpkg --configure -a || true
if ! run_as_root apt install -y --no-download "${deb_files[@]}"; then
  echo "Local apt install failed, trying dpkg fallback..."
  run_as_root dpkg -i "${deb_files[@]}" || true
  run_as_root apt-get install -y --no-download -f
fi

if ! command -v zsh >/dev/null 2>&1; then
  echo "zsh was not installed successfully." >&2
  exit 1
fi

echo "[2/4] Installing oh-my-zsh, plugins, and theme"
backup_if_exists "${TARGET_HOME}/.oh-my-zsh"
tmp_extract_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_extract_dir}"' EXIT

extract_archive "${ARCHIVE_DIR}/oh-my-zsh.tar.gz" "${tmp_extract_dir}"
mv "${tmp_extract_dir}/oh-my-zsh" "${TARGET_HOME}/.oh-my-zsh"

custom_dir="${ZSH_CUSTOM:-${TARGET_HOME}/.oh-my-zsh/custom}"
mkdir -p "${custom_dir}/plugins" "${custom_dir}/themes"

extract_archive "${ARCHIVE_DIR}/zsh-autosuggestions.tar.gz" "${custom_dir}/plugins"
extract_archive "${ARCHIVE_DIR}/zsh-completions.tar.gz" "${custom_dir}/plugins"
extract_archive "${ARCHIVE_DIR}/zsh-syntax-highlighting.tar.gz" "${custom_dir}/plugins"
extract_archive "${ARCHIVE_DIR}/powerlevel10k.tar.gz" "${custom_dir}/themes"

echo "[3/4] Writing ~/.zshrc"
backup_if_exists "${TARGET_HOME}/.zshrc"
if [[ -f "${ZSHRC_TEMPLATE}" ]]; then
  cp "${ZSHRC_TEMPLATE}" "${TARGET_HOME}/.zshrc"
else
  echo "Missing zshrc template: ${ZSHRC_TEMPLATE}" >&2
  exit 1
fi

if [[ "$(id -u)" -eq 0 ]]; then
  target_group="$(id -gn "${TARGET_USER}")"
  run_as_root chown -R "${TARGET_USER}:${target_group}" "${TARGET_HOME}/.oh-my-zsh" "${TARGET_HOME}/.zshrc"
fi

echo "[4/4] Setting default shell to zsh"
zsh_path="$(command -v zsh)"
if [[ "${SKIP_CHSH:-0}" == "1" ]]; then
  echo "Skipping chsh because SKIP_CHSH=1"
else
  current_shell="$(getent passwd "${TARGET_USER}" | cut -d: -f7 || true)"
  if [[ "${current_shell}" != "${zsh_path}" ]]; then
    if run_as_root chsh -s "${zsh_path}" "${TARGET_USER}"; then
      echo "Default shell changed to ${zsh_path} for user ${TARGET_USER}"
    else
      echo "Failed to change default shell automatically."
      echo "Please run manually: chsh -s ${zsh_path} ${TARGET_USER}"
    fi
  else
    echo "Default shell is already ${zsh_path} for user ${TARGET_USER}"
  fi
fi

cat <<'EOF'

Offline installation completed.
Run `zsh` to start using it.
Powerlevel10k is installed. Enable it by editing ~/.zshrc if needed.
EOF
echo "Config file: ${TARGET_HOME}/.zshrc"
echo "Oh My Zsh dir: ${TARGET_HOME}/.oh-my-zsh"
echo "Target user: ${TARGET_USER}"
