# Infinity X / OnePlus Ace 3 Pro 内核构建

这个入口复现 Infinity X `corvette`（OnePlus Ace 3 Pro）的 ROM 侧内核配置与编译链。它会固定配套源码和工具版本，并按 ROM 中的顺序合并：

1. `gki_defconfig`
2. `vendor/pineapple_GKI.config`
3. `vendor/oplus/pineapple_GKI.config`

构建时还会传入 `CONFIG_OPLUS_DEVICE_DTBS=y`、`CONFIG_CORVETTE_DTB=y` 和 `TARGET_BOARD_PLATFORM=pineapple`。

## 主机要求

- x86_64 Linux
- `git`、`git-lfs`、`make`、`perl`、`python3`、`rsync`
- 首次准备约需 7 GB 磁盘空间；完整输出还需数 GB

`bc`、Flex、Bison、Clang、LLD、pahole 和 LZ4 均由脚本使用固定版本的 Android 预编译工具，不依赖发行版里的随机版本。

## 使用

```bash
git clone -b 16.0 https://github.com/SuperKenVery/project_infinity_x_android_kernel_oneplus_sm8650.git
cd project_infinity_x_android_kernel_oneplus_sm8650

# 只下载并检查环境
./build-infinity.sh setup

# 生成配置并编译 Image
./build-infinity.sh build
```

默认目录结构如下，脚本会自动建立除内核仓库外的各目录：

```text
工作目录/
├── project_infinity_x_android_kernel_oneplus_sm8650/
├── sm8650-modules/
├── sm8650-devicetrees/
├── clang-r547379/
├── build-tools/
├── kernel-build-tools/
└── out/
```

产物位于 `../out/arch/arm64/boot/Image`，完整日志位于 `../out/build.log`。可以用环境变量调整行为：

```bash
JOBS=16 OUT_DIR=/path/to/out ./build-infinity.sh build
```

## 已固定的基线

| 组件 | 提交 |
| --- | --- |
| 内核 `android_kernel_oneplus_sm8650` | `c209d7422c61c1152e1897449e9e14b5ed04e1b0` |
| 外部模块 `sm8650-modules` | `e1f2eceb584f340bb31cca112453fd403351b6a9` |
| 设备树 `sm8650-devicetrees` | `0bf6f2c1de8f7be644823c6af09106cb7111d694` |
| Android Clang `r547379` | `6dbc9f0dc090ab0f8a72ceb8ab68c19fb9b80d7b` |
| Android build-tools | `f61cfbcb609173e1040753a2b9e8fbe8517343f9` |
| Android kernel-build-tools | `9c54986137a5f2215d7f977f4f9d1c22773d3892` |

如果后续有意修改配套模块仓库的提交，可以设置 `ALLOW_UNPINNED=1`。内核仓库本身不会被脚本强制到某个提交，因此可以直接在新分支上开发自定义内核。

## 刷入前注意

这里生成的是裸 `Image`，不是可直接 fastboot 刷入的 `boot.img`。在制作刷机包前，还需要从当前 Infinity X 版本提取原始启动镜像，保持 ramdisk、启动头、AVB 参数以及 vendor 模块 ABI 匹配。不要把裸 `Image` 直接写入手机分区。
