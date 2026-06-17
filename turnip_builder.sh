#!/bin/bash -e

#Define variables
green='\033[0;32m'
red='\033[0;31m'
nocolor='\033[0m'
deps="git meson ninja patchelf unzip curl pip flex bison zip glslang glslangValidator"
workdir="$(pwd)/turnip_workdir"
base_workdir="$(pwd)"
magiskdir="$workdir/turnip_module"
ndkver="android-ndk-r29"
ndk="$workdir/$ndkver/toolchains/llvm/prebuilt/linux-x86_64/bin"
sdkver="34"
mesasrc="https://gitlab.freedesktop.org/mesa/mesa.git"

clear

#There are 4 functions here, simply comment to disable.
#You can insert your own function and make a pull request.
run_all(){
	echo "====== Begin building TU V$BUILD_VERSION! ======"
	echo "Current directory: $base_workdir"
	check_deps
	prepare_workdir
	# This has path slash in the branch name and thus needs some workarounds
	build_lib_for_android turnip/gen8 turnip-gen8 
	build_lib_for_android turnip/gen8 turnip-gen8-sync apply
	#build_lib_for_android gen8-yuck
}

check_deps(){
	echo "Checking system for required Dependencies ..."
		for deps_chk in $deps;
			do
				sleep 0.25
				if command -v "$deps_chk" >/dev/null 2>&1 ; then
					echo -e "$green - $deps_chk found $nocolor"
				else
					echo -e "$red - $deps_chk not found, can't countinue. $nocolor"
					deps_missing=1
				fi;
			done

		if [ "$deps_missing" == "1" ]
			then echo "Please install missing dependencies" && exit 1
		fi

	echo "Installing python Mako dependency (if missing) ..." $'\n'
		pip install mako &> /dev/null
}

prepare_workdir(){
	echo "Preparing work directory ..." $'\n'
		mkdir -p "$workdir" && cd "$_"

	wget https://github.com/SnowNF/ndk-aarch64-linux/releases/download/0.0.2/android-ndk-r29-linux-aarch64.tar.gz
	
	echo "Exracting android-ndk ..." $'\n'
		tar -xzf android-ndk-r29-linux-aarch4.tar.gz

	echo "Downloading mesa source ..." $'\n'
		git clone $mesasrc --depth=1
		cd $srcfolder
		
	echo "Pushing TU_VERSION..."
	echo "#define TUGEN8_DRV_VERSION \"v$BUILD_VERSION\"" > ./src/freedreno/vulkan/tu_version.h
	#Workaround for using Clang as c compiler instead of GCC
	mkdir -p "$workdir/bin"
	ln -sf "$ndk/clang" "$workdir/bin/cc"
	ln -sf "$ndk/clang++" "$workdir/bin/c++"
	export PATH="$workdir/bin:$ndk:$PATH"
	export CC=clang
	export CXX=clang++
	export AR=llvm-ar
	export RANLIB=llvm-ranlib
	export STRIP=llvm-strip
	export OBJDUMP=llvm-objdump
	export OBJCOPY=llvm-objcopy
	export LDFLAGS="-fuse-ld=lld"

	echo "Generating build files ..." $'\n'
		cat <<EOF >"android-aarch64.txt"
[binaries]
ar = '$ndk/llvm-ar'
c = ['ccache', '$ndk/aarch64-linux-android$sdkver-clang']
cpp = ['ccache', '$ndk/aarch64-linux-android$sdkver-clang++', '-fno-exceptions', '-fno-unwind-tables', '-fno-asynchronous-unwind-tables', '--start-no-unused-arguments', '-static-libstdc++', '--end-no-unused-arguments']
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
[build_machine]
c = ['ccache', 'clang']
cpp = ['ccache', 'clang++']
ar = 'llvm-ar'
strip = 'llvm-strip'
c_ld = 'ld.lld'
cpp_ld = 'ld.lld'
system = 'linux'
cpu_family = 'aarch64'
cpu = 'armv8'
endian = 'little'
EOF

		meson setup build-android-aarch64 \
			--cross-file "android-aarch64.txt" \
			--native-file "native.txt" \
			--prefix /tmp/turnip \
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
			-Dandroid-libbacktrace=disabled

	echo "Compiling build files ..." $'\n'
		ninja -C build-android-aarch64 install
		
	echo "Making the archive"
	
	cd /tmp/turnip/lib
	
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
  "libraryName": "libvulkan_freedreno.so"
}
EOF
zip -9 /root/turnip/V$BUILD_VERSION.zip vulkan.adreno.so meta.json
cd -
if ! [ -a /tmp/a8xx-$2-V$BUILD_VERSION.zip ]; then
	echo -e "$red Failed to pack the archive! $nocolor"
fi
}

run_all
