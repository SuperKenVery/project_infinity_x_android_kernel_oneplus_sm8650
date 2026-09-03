# My own phone kernel

Changes:

- Kernel SU Next
- Enable features for DroidSpaces
- Patch for DroidVM

## Building

```sh
bash build-infinity.sh build
```

Recommended for ubuntu:

```sh
sudo apt install build-essential bc bison flex libssl-dev libelf-dev cpio
```

## Packing `boot.img`

```sh
mkdir boot-work
cd boot-work

magiskboot unpack -h /path/to/original-boot.img
cp ../out/arch/arm64/boot/Image kernel
magiskboot repack /path/to/original-boot.img custom-boot.img
```
