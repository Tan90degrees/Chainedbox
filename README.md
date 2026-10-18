# Chainedbox / L1 Pro Armbian build

为 RK3328 我家云 / L1 Pro 构建 Armbian；GitHub Actions 支持 **legacy**（原仓库）与 **ophub**（实验性）两种 DTB 来源。板卡别名 `l1pro` 与 `chainedbox` 共用硬件参数，只有板卡标识不同。

## 固定版本及来源

- Armbian build framework：[v26.5.1](https://github.com/armbian/build/releases/tag/v26.5.1)；`current` 为 Linux 6.18，`edge` 仅用于测试。
- `dtbs/legacy/`：保留本仓库原有的三档 DTB；旧 `5.10.y-bsp` 与 `5.15.y-bsp` 文件逐字节重复，现已去重。本目录内反编译 DTS 为历史参考文件，不等于 6.18 内核的可重编译源码。
- `dtbs/ophub/`：从 [ophub/amlogic-s9xxx-armbian](https://github.com/ophub/amlogic-s9xxx-armbian/tree/47bd9e4471a4d7b9720236a00c3f2b3af72ca4e5/build-armbian/armbian-files/platform-files/rockchip/bootfs/dtb/rockchip) 固定提交 `47bd9e4471a4d7b9720236a00c3f2b3af72ca4e5` 复制的同名 DTB，**Git Blob SHA 相同**。
- ophub 对应目录只发布 DTB、没有原始 DTS。本构建使用**原始 DTB 二进制**启动；同时用 `dtc -I dtb -O dts` 导出反编译 DTS 作为产物供比较，**不宣称这是 ophub 官方 DTS 源码**。
- `loader/` 中仍是本仓库原有的 Chainedbox 引导二进制（与 ophub/u-boot 不同），**切换 DTB 来源不会切换 Bootloader**。
- `dts/` 是原仓库保留的可编辑历史 L1 Pro 设备树源码，未自动参与 `6.18` 内核 DTB 生成。

更多来源和文件哈希见 [dtbs/README.md](dtbs/README.md)。

## GitHub Actions

打开 [Build Chainedbox Armbian](https://github.com/Tan90degrees/Chainedbox/actions/workflows/build-5.15.y.yml) → **Run workflow**。主要参数：

| 参数 | 默认值 | 说明 |
| --- | --- | --- |
| `armbianBoard` | `l1pro` | 可选 `chainedbox`（相同底层板级配置） |
| `armbianBranch` | `current` | 可选 `edge`，但未验证 |
| `armbianRelease` | `noble` | 可选 `trixie` |
| `cpuFrequency` | `1296mhz` | 可选 `1392mhz`、`1512mhz`（存在稳定性风险） |
| **`dtbSource`** | **`legacy`** | **`ophub` 为实验性 DTB/DTS 对照构建** |
| `publishRelease` | `false` | 手动构建时是否发布预发行版 |

推送到 `main` 会自动尝试构建并发布预发行固件；定时运行只上传 Actions artifact。每次上传 `.img.gz`、镜像 `.sha256`、**所选原始 `.dtb` 与由它反编译的 `.dts`**。发布文件名包含 `legacy` 或 `ophub`，避免混淆。

**GitHub-hosted runner 可能磁盘空间不足**：上游建议约 50 GB 可用磁盘，GitHub Actions 成功不代表真机可以启动。

## 本地构建

在 Ubuntu 24.04 上安装 `device-tree-compiler`、`u-boot-tools`、`util-linux` 等依赖，并提供足够空间。克隆本仓库后在仓库根目录执行：

```bash
git clone --branch v26.5.1 --depth 1 https://github.com/armbian/build.git build
cp config/boards/{l1pro,chainedbox}.conf build/config/boards/
cd build
./compile.sh build BOARD=l1pro BRANCH=current RELEASE=noble BUILD_MINIMAL=no BUILD_DESKTOP=no KERNEL_CONFIGURE=no COMPRESS_OUTPUTIMAGE=img
cd ..
# 使用 ophub DTB；最后一个参数也可以是 legacy
sudo bash ./rebuild-5.15.y.sh 1296mhz l1pro ophub
```

本脚本仅接受磁盘镜像中的根分区为 **p1 且偏移不小于 16 MiB 的非 GPT 布局**；不兼容时将拒绝写入历史引导扇区。不会照搬 ophub 配套的 `rootdev=/dev/mmcblk0p2` 配置。

## 风扇与兼容性

`legacy` 模式为保持旧行为继续安装原有 `pwm-fan.pl` 服务，存在与内核 `pwm-fan` 竞争的历史风险；`ophub` 模式**不安装/启用该用户态服务**，由 ophub DTB 的内核 `pwm-fan` 与 thermal cooling maps 处理风扇。

目前 **legacy、ophub 和官方 Rock64 DTB 不相同**。Rock64 官方设备树缺少我家云专用的硬盘供电和风扇节点，网卡延迟也不同，不能直接替换。ophub DTB 与 legacy 共有关键 eMMC、硬盘、网卡参数，但在风扇、厂商 DMC 配置上有差异。

首次测试务必备份原有 eMMC / 固件，保留可恢复路径，并使用串口检查：启动、eMMC、网卡、USB、硬盘供电、温度和风扇。**未经过真机测试，全部镜像仅供实验**。

## 仓库整理

- 去除重复的 `5.10.y-bsp` 与 `5.15.y-bsp` 二进制/反编译设备树副本，统一到 `dtbs/legacy/`。
- 删除现行流程完全未引用的旧启动模板、空壳脚本和危险的 `rebuild-5.10.y.sh`（其中包含 `losetup -D`）。
- 两份不同的板卡配置、历史 `dts/` 可编辑源码及实际使用的 `loader/` 保留，不误当作重复文件删除。
- 旧的 `rebuild-5.15.y.sh` 名称继续保留，方便已有调用者兼容；新增第三参数 `legacy|ophub`。
