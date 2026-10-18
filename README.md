# Chainedbox Armbian images

RK3328 我家云 / L1 Pro 的 Armbian 构建脚本，支持 GitHub Actions 自动构建和手动发布。

## 构建版本

- **Armbian build framework:** [v26.5.1](https://github.com/armbian/build/releases/tag/v26.5.1)，固定 Git tag，避免跟踪不稳定的 trunk 版本。
- **默认内核分支:** `current`（该稳定构建框架的 rockchip64 current 基线为 Linux 6.18）；可手动选择 `edge`，但**未验证设备兼容性**。
- **默认发行版:** Ubuntu 24.04 Noble；也可在手动运行时选择 Debian Trixie。
- **构建主机:** `ubuntu-24.04`；编译环境依赖空间较大（上游建议约 50 GB 可用空间），标准 GitHub 托管 Runner 可能因空间不足而失败。

注意：**Armbian 系统发行版 26.8.3 与 `armbian/build` 的 Git tag 并非同一发布序列**。截至 2026-10-18，可确认的最新非 trunk `armbian/build` Release tag 为 `v26.5.1`；构建因此采用这个可复现的稳定源码版本，不会自动跟踪每周 trunk 构建。

## GitHub Actions

进入 **Actions → Build Chainedbox Armbian (stable) → Run workflow**，选择：

- `armbianBoard`: `l1pro` 或 `chainedbox`（默认 `l1pro`）。
- `armbianBranch`: `current`（推荐）或 `edge`。
- `armbianRelease`: `noble` 或 `trixie`。
- `cpuFrequency`: `1296mhz`（推荐）、`1392mhz` 或 `1512mhz`。
- `publishRelease`: 默认关闭；仅手动运行并勾选后，成功构建的镜像才会发布到 GitHub Releases。

推送到 `main` 或每周定时任务也会构建镜像，仅上传 Actions Artifacts（保留 14 天）；Pull Request 只执行快速配置/脚本检查，不自动发布。输出为 `.img.gz` 及对应的 `.sha256` 校验文件。

## 本地构建

需要 Ubuntu 24.04（或上游支持的容器环境）、足够的磁盘空间及 root 权限：

```bash
git clone --branch v26.5.1 --depth 1 https://github.com/armbian/build.git build
cp config/boards/{l1pro,chainedbox}.conf build/config/boards/
cd build
./compile.sh build BOARD=l1pro BRANCH=current RELEASE=noble BUILD_MINIMAL=no BUILD_DESKTOP=no KERNEL_CONFIGURE=no COMPRESS_OUTPUTIMAGE=img
cd ..
sudo bash ./rebuild-5.15.y.sh 1296mhz l1pro
```

## 硬件验证及限制

仓库内的 `dtbs/5.15.y-bsp` DTB 和 `loader/` 引导程序仍来自旧硬件适配，**不能因为新镜像编译通过就认定它能正常开机**。特别是 Linux 6.18 内核与旧版设备树、PWM 风扇、eMMC/USB/网卡之间存在兼容风险。首次使用请先在可恢复设备上检查串口启动日志、存储分区、网络、温度与风扇，保留原固件备份；未做真机测试前不建议替换生产设备系统。

历史脚本 `rebuild-5.10.y.sh` 保留作旧版参考；现行工作流使用已修正的 `rebuild-5.15.y.sh`（文件名为历史遗留）。新版镜像后处理只拆卸本次使用的 loop 设备，并沿用上游 `boot.scr` 及 `dtb/rockchip/` 路径。
