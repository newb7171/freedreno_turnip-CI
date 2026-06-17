#!/bin/bash

set -euo pipefail

workdir="$(pwd)/turnip_workdir"
ndk="$workdir/r29/toolchains/llvm/prebuilt/linux-x86_64/bin"
sdkver="34"
mesasrc="https://gitlab.freedesktop.org/mesa/mesa.git"
BUILD_VERSION="26.2.0"

mkdir -p "$workdir"
cd "$workdir"

mkdir -p "$workdir/turnip"

wget https://github.com/SnowNF/ndk-aarch64-linux/releases/download/0.0.2/android-ndk-r29-linux-aarch64.tar.gz

tar -xzf android-ndk-r29-linux-aarch64.tar.gz

git clone $mesasrc --depth=1
cd mesa

echo "Pushing TU_VERSION..."
echo "#define TUGEN8_DRV_VERSION \"v$BUILD_VERSION\"" > ./src/freedreno/vulkan/tu_version.h

export CC=clang
export CXX=clang++
export AR=llvm-ar
export RANLIB=llvm-ranlib
export STRIP=llvm-strip
export OBJDUMP=llvm-objdump
export OBJCOPY=llvm-objcopy
export LDFLAGS="-fuse-ld=lld"

cat <<EOF >"android-aarch64.txt"
[binaries]
ar = '$ndk/llvm-ar'
c = '$ndk/aarch64-linux-android34-clang'
cpp = ['$ndk/aarch64-linux-android34-clang++', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '--start-no-unused-arguments', '-static-libstdc++', '--end-no-unused-arguments']
c_ld = '$ndk/ld.lld'
cpp_ld = '$ndk/ld.lld'
strip = '$ndk/llvm-strip'
pkg-config = ['env', 'PKG_CONFIG_LIBDIR=$ndk/pkg-config', '/usr/bin/pkg-config']

[host_machine]
system = 'android'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

cat <<EOF >"native.txt"
[binaries]
c = ['ccache', 'clang']
cpp = ['ccache', 'clang++']
ar = 'llvm-ar'
strip = 'llvm-strip'
c_ld = 'ld.lld'
cpp_ld = 'ld.lld'

[host_machine]
system = 'linux'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

meson setup build-android-aarch64 \
    --cross-file "android-aarch64.txt" \
    --native-file "native.txt" \
    --prefix "$workdir/turnip" \
    -Dbuildtype=release \
    -Dstrip=true \
    -Dplatforms=android \
    -Dvideo-codecs= \
    -Dplatform-sdk-version=34 \
    -Dandroid-stub=true \
    -Dgallium-drivers= \
    -Dvulkan-drivers=freedreno \
    -Dvulkan-beta=true \
    -Dfreedreno-kmds=kgsl \
    -Degl=disabled \
    -Dandroid-libbacktrace=disabled \
    -Dzstd=disabled \
    -Dspirv-tools=disabled

ninja -C build-android-aarch64 install

cd "$workdir/turnip/lib"

patchelf --set-soname vulkan.adreno.so libvulkan_freedreno.so

mv libvulkan_freedreno.so vulkan.adreno.so

cat <<EOF >"meta.json"
{
  "schemaVersion": 1,
  "name": "Turnip v$BUILD_VERSION",
  "description": "Built from source",
  "author": "JustCallMeJade",
  "packageVersion": "1",
  "vendor": "Mesa",
  "driverVersion": "Vulkan 1.4.335",
  "minApi": 28,
  "libraryName": "vulkan.adreno.so"
}
EOF

zip -9 "$workdir/turnip/V$BUILD_VERSION.zip" vulkan.adreno.so meta.json

echo "build complete."

exit 0
