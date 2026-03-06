#!/usr/bin/env bash
set -euo pipefail

if [[ ! -r /etc/os-release ]]; then
  echo "Cannot read /etc/os-release on this machine." >&2
  exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release

codename="${VERSION_CODENAME:-}"
version="${VERSION_ID:-}"
arch="$(dpkg --print-architecture 2>/dev/null || uname -m)"

case "${arch}" in
  x86_64) arch="amd64" ;;
  aarch64) arch="arm64" ;;
esac

if [[ -z "${codename}" || -z "${version}" ]]; then
  echo "Missing VERSION_CODENAME or VERSION_ID in /etc/os-release." >&2
  exit 1
fi

echo "Detected target machine:"
echo "  codename=${codename}"
echo "  version=${version}"
echo "  arch=${arch}"
echo
echo "Use this on your online machine:"
echo "./prepare_online_bundle.sh --target-codename ${codename} --target-version ${version} --target-arch ${arch}"
