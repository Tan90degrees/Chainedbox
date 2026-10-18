# Chainedbox / L1 Pro DTB sources

所有文件是 RK3328 **板卡设备树**，不是可跨设备互换的通用 RK3328 固件。

## legacy（原仓库，默认）

| Frequency | Git Blob SHA |
|---|---|
| 1296mhz | `6e5779b9d3738268b2e95b85ce632a9d6dce78ff` |
| 1392mhz | `be64ad067d37841e5755083b5b69217a38034f92` |
| 1512mhz | `b663cd1aadaff8b54c91a4453751f6789e7e7047` |

这三份 DTB 及随附反编译 DTS 从仓库原有 `dtbs/5.15.y-bsp/` 原样移动；原 `5.10.y-bsp/` 完全相同因此删除。原库注明来源：[恩山论坛历史帖](https://www.right.com.cn/forum/thread-4076037-1-1.html)。目录版本名不意味着已验证 Linux 5.15 或 Linux 6.18。

## ophub（实验性）

来源：[ophub/amlogic-s9xxx-armbian](https://github.com/ophub/amlogic-s9xxx-armbian)，锁定提交 `47bd9e4471a4d7b9720236a00c3f2b3af72ca4e5`，路径 `build-armbian/armbian-files/platform-files/rockchip/bootfs/dtb/rockchip/`。

| Frequency | Git Blob SHA |
|---|---|
| 1296mhz | `d7482c564d503df733413cc2aaf3aced37fcd3b7` |
| 1392mhz | `0dd349c1a67da4c5513c2fe1d1ccfc09e4151144` |
| 1512mhz | `3bfc3ad8e79241f152c240e233c57e5ddcbcc08c` |

文件已按字节复制，SHA 与上游完全一致。ophub 提供的是**编译后的 DTB**，没有在该仓库对应路径公开同版的原始 DTS。打包时执行：

```bash
dtc -I dtb -O dts -o Chainedbox_l1pro_ophub_1296mhz.dts dtbs/ophub/rk3328-l1pro-1296mhz.dtb
```

反编译的 DTS 作为 GitHub Actions 构建产物，不用于重编译启动设备树，避免改写上游二进制后产生偏差。ophub `rk3328-chainedbox.dtb` 是不同的板卡配置，**没有**当作 L1 Pro 文件使用。

仅切换 DTB 来源，**不切换** `loader/idbloader.bin`、`loader/uboot.img`、`loader/trust.bin`。不得把此操作视为官方 Rock64 兼容性验证。
