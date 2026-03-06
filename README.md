# zsh-offline

[![Latest Release](https://img.shields.io/github/v/release/uranus0515/zsh-offline?display_name=tag)](https://github.com/uranus0515/zsh-offline/releases/latest)

用于在 Ubuntu 目标机完全离线的场景下安装 `zsh + oh-my-zsh + 常用插件/主题` 的构建与安装脚本集合。

## 项目目标

- 解决“目标机器离线，无法 `apt install` / `git clone`”的问题。
- 支持两阶段流程：在线构建离线包，离线机器安装。
- 避免误操作核心系统依赖链（例如 `libc6`）。

## 非目标

- 不做跨发行版（如 Debian/CentOS）通用安装器。
- 不保证所有 Ubuntu 组合都零风险，仍需做目标环境验收。
- 不在本仓库提交大体积构建产物（`.tar.gz` / `.deb`）。

## 两阶段工作流

1. 在线阶段：在可联网 Ubuntu 机器上运行 `prepare_online_bundle.sh` 构建离线包。
2. 离线阶段：将离线包拷贝到目标机器，执行 `install_offline.sh` 完成安装。

## 快速开始

### 1) 在目标离线机采集参数

```bash
bash collect_target_params.sh
```

示例输出：

```text
./prepare_online_bundle.sh --target-codename jammy --target-version 22.04.3 --target-arch amd64
```

### 2) 在在线 Ubuntu 机器构建包

```bash
./prepare_online_bundle.sh \
  --target-codename jammy \
  --target-version 22.04.3 \
  --target-arch amd64
```

输出示例：

```text
zsh-offline-bundle-ubuntu22.04.3-jammy-amd64-20260306-173000.tar.gz
```

脚本会输出带时间戳的阶段日志（如 `[INFO] [1/6]`），在 `apt` 刷新、`.deb` 下载、`git clone` 等耗时步骤会提示“可能需要几分钟”；若网络不稳定，也会给出重试/等待提示。

### 3) 在离线目标机安装

```bash
mkdir -p ~/zsh-offline
tar -xzf zsh-offline-bundle-ubuntu22.04.3-jammy-amd64-*.tar.gz -C ~/zsh-offline
cd ~/zsh-offline
chmod +x install_offline.sh
./install_offline.sh
```

## 关键约束

- 在线构建目标参数必须与离线机一致：`codename`、`version`、`arch`。
- 在线机器建议使用 Ubuntu（脚本依赖 `apt-get/apt-cache/dpkg`）。
- 脚本只解析 `zsh` 直接依赖，并显式排除 `libc6`。
- `powerlevel10k` 默认不启用，避免离线首启卡在 `fetching gitstatusd`。

## 脚本说明

- `collect_target_params.sh`
  - 在目标机读取 `codename/version/arch`，输出在线构建命令。
- `prepare_online_bundle.sh`
  - 从零构建 bundle：下载目标 `.deb`、拉取 oh-my-zsh 及插件/主题源码归档、打包输出。
- `fill_debs_on_ubuntu.sh`
  - 在已有 `bundle/archives` 时仅刷新 `.deb` 并重打包。
- `offline/install_offline.sh`
  - 离线安装入口，安装 zsh、部署 oh-my-zsh 和插件，写入 `.zshrc`，尝试 `chsh`。
- `offline/zshrc.template`
  - 默认 shell 配置模板。

## 常用参数

- `--target-codename`：如 `jammy` / `noble`
- `--target-version`：如 `22.04.3` / `24.04`
- `--target-arch`：如 `amd64` / `arm64`
- `--target-mirror` / `--target-security-mirror`：自定义源
- `--target-components`：默认 `main universe`

离线安装脚本支持：

- `TARGET_USER=<username>`
- `TARGET_HOME=/path/to/home`
- `SKIP_CHSH=1`

## 验收检查

```bash
getent passwd "$USER" | cut -d: -f7
zsh --version
ls -la ~/.zshrc ~/.oh-my-zsh
```

## 开源与许可

- 本仓库脚本与文档使用 MIT 许可，见 `LICENSE`。
- 构建产物内会包含第三方项目源码归档与 Ubuntu `.deb` 包，它们不适用本仓库 MIT，需遵循各自许可条款。
- 第三方来源列表见 `THIRD_PARTY.md`。

## 贡献

欢迎 PR/Issue。提交前至少运行：

```bash
bash -n collect_target_params.sh prepare_online_bundle.sh fill_debs_on_ubuntu.sh offline/install_offline.sh
```

仓库已配置 GitHub Actions CI，PR 时会自动执行语法检查、`shellcheck` 和基础 smoke 检查。

更多规范见 `CONTRIBUTING.md`。
