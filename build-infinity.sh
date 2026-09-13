#!/usr/bin/env bash
# Reproduce the Infinity X / OnePlus Ace 3 Pro kernel build environment.

set -euo pipefail

KERNEL_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
WORK_ROOT="${INFINITY_WORK_ROOT:-$(dirname -- "${KERNEL_DIR}")}"
OUT_DIR="${OUT_DIR:-${WORK_ROOT}/out}"
JOBS="${JOBS:-$(nproc)}"

MODULES_DIR="${WORK_ROOT}/sm8650-modules"
DEVICETREES_DIR="${WORK_ROOT}/sm8650-devicetrees"
CLANG_DIR="${WORK_ROOT}/clang-r547379"
BUILD_TOOLS_DIR="${WORK_ROOT}/build-tools"
KERNEL_BUILD_TOOLS_DIR="${WORK_ROOT}/kernel-build-tools"

MODULES_REPO="https://github.com/OPACE3PRO/android_kernel_oneplus_sm8650-modules.git"
MODULES_COMMIT="e1f2eceb584f340bb31cca112453fd403351b6a9"
DEVICETREES_REPO="https://github.com/OPACE3PRO/android_kernel_oneplus_sm8650-devicetrees.git"
DEVICETREES_COMMIT="0bf6f2c1de8f7be644823c6af09106cb7111d694"
CLANG_REPO="https://github.com/KiTTYsh/android_prebuilts_clang_host_linux-x86_clang-r547379.git"
CLANG_COMMIT="6dbc9f0dc090ab0f8a72ceb8ab68c19fb9b80d7b"
BUILD_TOOLS_REPO="https://github.com/LineageOS/android_prebuilts_build-tools.git"
BUILD_TOOLS_COMMIT="f61cfbcb609173e1040753a2b9e8fbe8517343f9"
KERNEL_BUILD_TOOLS_REPO="https://github.com/pa-gr/android_kernel_prebuilts_build-tools.git"
KERNEL_BUILD_TOOLS_COMMIT="9c54986137a5f2215d7f977f4f9d1c22773d3892"
DEVICE_TREE_PATCH="${KERNEL_DIR}/patches/0001-corvette-fastcharge-shell-temp-plus-5c.patch"

die() {
    printf 'error: %s\n' "$*" >&2
    exit 1
}

require_command() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

verify_existing_repo() {
    local destination="$1"
    local expected_commit="$2"
    local actual_commit

    [[ -d "${destination}/.git" ]] || return 1
    actual_commit="$(git -C "${destination}" rev-parse HEAD)"
    if [[ "${actual_commit}" != "${expected_commit}" && "${ALLOW_UNPINNED:-0}" != 1 ]]; then
        die "${destination} is at ${actual_commit}, expected ${expected_commit}; set ALLOW_UNPINNED=1 to use it intentionally"
    fi
    return 0
}

clone_full_repo() {
    local name="$1"
    local repository="$2"
    local commit="$3"
    local destination="$4"
    local use_lfs="${5:-0}"

    if verify_existing_repo "${destination}" "${commit}"; then
        printf 'Using %s at %s\n' "${name}" "$(git -C "${destination}" rev-parse --short HEAD)"
        return
    fi
    [[ ! -e "${destination}" ]] || die "${destination} exists but is not a Git repository"

    printf 'Fetching %s...\n' "${name}"
    git init -q "${destination}"
    git -C "${destination}" remote add origin "${repository}"
    if [[ "${use_lfs}" == 1 ]]; then
        require_command git-lfs
        git -C "${destination}" lfs install --local
    fi
    git -C "${destination}" fetch --depth=1 origin "${commit}"
    git -C "${destination}" checkout --detach -q FETCH_HEAD
    if [[ "${use_lfs}" == 1 ]]; then
        git -C "${destination}" lfs pull origin
    fi
}

clone_sparse_repo() {
    local name="$1"
    local repository="$2"
    local commit="$3"
    local destination="$4"
    shift 4

    if verify_existing_repo "${destination}" "${commit}"; then
        printf 'Using %s at %s\n' "${name}" "$(git -C "${destination}" rev-parse --short HEAD)"
        return
    fi
    [[ ! -e "${destination}" ]] || die "${destination} exists but is not a Git repository"

    printf 'Fetching %s...\n' "${name}"
    git init -q "${destination}"
    git -C "${destination}" remote add origin "${repository}"
    git -C "${destination}" fetch --depth=1 origin "${commit}"
    git -C "${destination}" sparse-checkout init --no-cone
    git -C "${destination}" sparse-checkout set --no-cone "$@"
    git -C "${destination}" checkout --detach -q FETCH_HEAD
}

apply_device_tree_patch() {
    if git -C "${DEVICETREES_DIR}" apply --reverse --check "${DEVICE_TREE_PATCH}" >/dev/null 2>&1; then
        printf 'Using patched SM8650 device trees\n'
        return
    fi

    git -C "${DEVICETREES_DIR}" apply --check "${DEVICE_TREE_PATCH}" \
        || die "device-tree patch no longer applies cleanly"
    git -C "${DEVICETREES_DIR}" apply "${DEVICE_TREE_PATCH}"
}

setup_environment() {
    [[ "$(uname -s)" == Linux ]] || die "only a Linux build host is supported"
    [[ "$(uname -m)" == x86_64 ]] || die "the pinned Android prebuilts require an x86_64 host"
    require_command git
    require_command make
    require_command perl
    require_command python3
    require_command rsync

    clone_full_repo "SM8650 modules" "${MODULES_REPO}" "${MODULES_COMMIT}" "${MODULES_DIR}"
    clone_full_repo "SM8650 device trees" "${DEVICETREES_REPO}" "${DEVICETREES_COMMIT}" "${DEVICETREES_DIR}"
    apply_device_tree_patch
    clone_full_repo "Android Clang r547379" "${CLANG_REPO}" "${CLANG_COMMIT}" "${CLANG_DIR}" 1
    clone_sparse_repo "Android build tools" "${BUILD_TOOLS_REPO}" "${BUILD_TOOLS_COMMIT}" "${BUILD_TOOLS_DIR}" \
        '/linux-x86/bin/flex' \
        '/linux-x86/bin/bison' \
        '/linux-x86/bin/m4' \
        '/linux-x86/bin/gavinhoward-bc' \
        '/linux-x86/lib64/**' \
        '/common/bison/**' \
        '/common/m4/**' \
        '/path/linux-x86/bc'
    clone_sparse_repo "Android kernel build tools" "${KERNEL_BUILD_TOOLS_REPO}" "${KERNEL_BUILD_TOOLS_COMMIT}" "${KERNEL_BUILD_TOOLS_DIR}" \
        '/linux-x86/bin/pahole' \
        '/linux-x86/bin/lz4' \
        '/linux-x86/lib64/**' \
        '/linux-x86/include/**'

    "${CLANG_DIR}/bin/clang" --version | sed -n '1p'
}

export_build_environment() {
    export PATH="${CLANG_DIR}/bin:${BUILD_TOOLS_DIR}/path/linux-x86:${BUILD_TOOLS_DIR}/linux-x86/bin:${KERNEL_BUILD_TOOLS_DIR}/linux-x86/bin:${PATH}"
    export LD_LIBRARY_PATH="${BUILD_TOOLS_DIR}/linux-x86/lib64:${KERNEL_BUILD_TOOLS_DIR}/linux-x86/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
    export BISON_PKGDATADIR="${BUILD_TOOLS_DIR}/common/bison"
    export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-infinity-x}"
    export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-builder}"
}

make_args=(
    -C "${KERNEL_DIR}"
    O="${OUT_DIR}"
    ARCH=arm64
    LLVM=1
    LLVM_IAS=1
    CC=clang
    LD=ld.lld
    AR=llvm-ar
    NM=llvm-nm
    OBJCOPY=llvm-objcopy
    OBJDUMP=llvm-objdump
    READELF=llvm-readelf
    STRIP=llvm-strip
    HOSTCC=clang
    HOSTCXX=clang++
    HOSTLD=ld.lld
    HOSTAR=llvm-ar
    LEX=flex
    YACC=bison
    M4=m4
    PAHOLE="${KERNEL_BUILD_TOOLS_DIR}/linux-x86/bin/pahole"
    LZ4="${KERNEL_BUILD_TOOLS_DIR}/linux-x86/bin/lz4"
    HOSTCFLAGS="-I${KERNEL_BUILD_TOOLS_DIR}/linux-x86/include"
    HOSTLDFLAGS="-Wl,-rpath,${KERNEL_BUILD_TOOLS_DIR}/linux-x86/lib64 -L${KERNEL_BUILD_TOOLS_DIR}/linux-x86/lib64 -fuse-ld=lld --rtlib=compiler-rt"
    CONFIG_OPLUS_DEVICE_DTBS=y
    CONFIG_CORVETTE_DTB=y
    TARGET_BOARD_PLATFORM=pineapple
)

run_make() {
    make "${make_args[@]}" "$@"
}

configure_kernel() {
    local fragment
    mkdir -p "${OUT_DIR}"
    cp "${KERNEL_DIR}/arch/arm64/configs/gki_defconfig" "${OUT_DIR}/.config"
    run_make olddefconfig

    for fragment in \
        "${KERNEL_DIR}/arch/arm64/configs/vendor/pineapple_GKI.config" \
        "${KERNEL_DIR}/arch/arm64/configs/vendor/oplus/pineapple_GKI.config"; do
        KCONFIG_CONFIG="${OUT_DIR}/.config" \
            "${KERNEL_DIR}/scripts/kconfig/merge_config.sh" -m -O "${OUT_DIR}" \
            "${OUT_DIR}/.config" "${fragment}"
        run_make olddefconfig
    done

    printf 'Config: %s\n' "$(sha256sum "${OUT_DIR}/.config" | cut -d' ' -f1)"
}

build_kernel() {
    local image="${OUT_DIR}/arch/arm64/boot/Image"
    local log="${OUT_DIR}/build.log"

    run_make -j"${JOBS}" Image 2>&1 | tee "${log}"
    [[ -f "${image}" ]] || die "build completed without producing ${image}"
    file "${image}"
    sha256sum "${image}"
}

build_device_trees() {
    local dtbo="${OUT_DIR}/arch/arm64/boot/dts/vendor/oplus/corvette-23814-pineapple-overlay.dtbo"

    run_make -j"${JOBS}" dtbs
    [[ -f "${dtbo}" ]] || die "build completed without producing ${dtbo}"
    file "${dtbo}"
    sha256sum "${dtbo}"
}

usage() {
    printf 'Usage: %s [setup|config|build]\n' "${0##*/}"
    printf '  setup   fetch the pinned companion repositories and toolchains\n'
    printf '  config  setup and regenerate the Infinity X corvette .config\n'
    printf '  build   setup, regenerate .config, and build Image plus corvette DTBO (default)\n'
}

action="${1:-build}"
case "${action}" in
    setup)
        setup_environment
        ;;
    config)
        setup_environment
        export_build_environment
        configure_kernel
        ;;
    build)
        setup_environment
        export_build_environment
        configure_kernel
        build_kernel
        build_device_trees
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        usage >&2
        exit 2
        ;;
esac
