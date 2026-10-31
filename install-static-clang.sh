#!/bin/bash

# Stop at any error, show all commands
set -exuo pipefail

TOOLCHAIN_PATH=/opt/clang

# Download static-clang
DEFAULT_ARCH="$(uname -m)"
if [ "${STATIC_CLANG_ARCH:-}" == "" ]; then
	STATIC_CLANG_ARCH="${RUNNER_ARCH:-${DEFAULT_ARCH}}"
fi
case "${STATIC_CLANG_ARCH}" in
	ARM64|aarch64|arm64|arm64/*) GO_ARCH=arm64;;
	ARM|armv7l|armv8l|arm|arm/v7) GO_ARCH=arm;;  # assume arm/v7 for arm
	X64|x86_64|amd64|amd64/*) GO_ARCH=amd64;;
	X86|i686|386) GO_ARCH=386;;
	loongarch64) GO_ARCH=loong64;;
	ppc64le) GO_ARCH=ppc64le;;
	riscv64) GO_ARCH=riscv64;;
	s390x) GO_ARCH=s390x;;
	*) echo "No static-clang toolchain for ${CLANG_ARCH}">2; exit 1;;
esac
STATIC_CLANG_VERSION=23.1.3.0
STATIC_CLANG_FILENAME="static-clang-linux-${GO_ARCH}.tar.xz"
STATIC_CLANG_URL="https://github.com/mayeut/static-clang-images/releases/download/v${STATIC_CLANG_VERSION}/${STATIC_CLANG_FILENAME}"
pushd /tmp
cat<<'EOF' | grep "${STATIC_CLANG_FILENAME}" > "${STATIC_CLANG_FILENAME}.sha256"
bac4d694b29767f18a12282cf686792e4e815facb6576bacedce73d34c4ddd58  static-clang-linux-386.tar.xz
740fa55455fd04bb90a3f21e98a9fffb239822267c7d4e8b32313370c654cb50  static-clang-linux-amd64.tar.xz
97ecca238a1366fe1d7821ea22cf2797643ba12b892057f4998597f0b7fa3650  static-clang-linux-arm.tar.xz
a8d7068dfb8f5d6c9bfd93d7b945f5d9c5b6e2dd8d23aeee2c3d170d57ef6b42  static-clang-linux-arm64.tar.xz
c81c3b053f019d7d4245a7203d4c76018db68b517688df08b9f42b81f2bc6422  static-clang-linux-loong64.tar.xz
5516344b4ed079585292ad52c064aa1bee305785dc25987664ee23689f94543c  static-clang-linux-ppc64le.tar.xz
32be05ab19425c41b324b91257da83827dc13b0564805b38d68cdd5a8f7350aa  static-clang-linux-riscv64.tar.xz
b5296b59fc190150df18afdf7acbc57b8ea9777249e0e313b0f51921b84a4c83  static-clang-linux-s390x.tar.xz
EOF
curl -fsSLO "${STATIC_CLANG_URL}"
sha256sum -c "${STATIC_CLANG_FILENAME}.sha256"
tar -C /opt -xf "${STATIC_CLANG_FILENAME}"
popd

# configure target triple
DEFAULT_POLICY="manylinux_2_38"
if ldd /bin/ls 2>&1 | grep -q 'musl'; then
	DEFAULT_POLICY="musllinux_1_2"
fi
if [ "${AUDITWHEEL_POLICY:-}" == "" ]; then
	AUDITWHEEL_POLICY="${DEFAULT_POLICY}"
fi
if [ "${AUDITWHEEL_ARCH:-}" == "" ]; then
	AUDITWHEEL_ARCH="${DEFAULT_ARCH}"
fi
if [ "${AUDITWHEEL_PLAT:-}" == "" ]; then
	AUDITWHEEL_PLAT="${AUDITWHEEL_POLICY}-${AUDITWHEEL_ARCH}"
fi
case "${AUDITWHEEL_PLAT}" in
	manylinux*-armv7l) TARGET_TRIPLE=armv7-unknown-linux-gnueabihf;;
	musllinux*-armv7l) TARGET_TRIPLE=armv7-alpine-linux-musleabihf;;
	manylinux*-ppc64le) TARGET_TRIPLE=powerpc64le-unknown-linux-gnu;;
	musllinux*-ppc64le) TARGET_TRIPLE=powerpc64le-alpine-linux-musl;;
	manylinux*-*) TARGET_TRIPLE=${AUDITWHEEL_ARCH}-unknown-linux-gnu;;
	musllinux*-*) TARGET_TRIPLE=${AUDITWHEEL_ARCH}-alpine-linux-musl;;
esac
case "${AUDITWHEEL_PLAT}" in
	*-riscv64) M_ARCH="-march=rv64gc";;
	*-x86_64) M_ARCH="-march=x86-64";;
	*-armv7l) M_ARCH="-march=armv7a";;
	manylinux*-i686) M_ARCH="-march=k8 -mtune=generic";;  # same as gcc manylinux2014 / manylinux_2_28
	musllinux*-i686) M_ARCH="-march=pentium-m -mtune=generic";;  # same as gcc musllinux_1_2
esac
GCC_TRIPLE=$(gcc -dumpmachine)

pushd "${TOOLCHAIN_PATH}/bin"
ln -s clang "${TOOLCHAIN_PATH}/bin/gcc"
ln -s clang "${TOOLCHAIN_PATH}/bin/cc"
ln -s clang-cpp "${TOOLCHAIN_PATH}/bin/cpp"
ln -s clang++ "${TOOLCHAIN_PATH}/bin/g++"
ln -s clang++ "${TOOLCHAIN_PATH}/bin/c++"
ln -s lld "${TOOLCHAIN_PATH}/bin/ld"
popd

cat<<EOF >"${TOOLCHAIN_PATH}/bin/${AUDITWHEEL_PLAT}.cfg"
	-target ${TARGET_TRIPLE}
	${M_ARCH:-}
	--gcc-toolchain=${DEVTOOLSET_ROOTPATH:-}/usr
	--gcc-triple=${GCC_TRIPLE}
EOF

cat<<EOF >"${TOOLCHAIN_PATH}/bin/clang.cfg"
	@${AUDITWHEEL_PLAT}.cfg
	-fuse-ld=lld
EOF

cat<<EOF >"${TOOLCHAIN_PATH}/bin/clang++.cfg"
	@${AUDITWHEEL_PLAT}.cfg
	-fuse-ld=lld
EOF

cat<<EOF >"${TOOLCHAIN_PATH}/bin/clang-cpp.cfg"
	@${AUDITWHEEL_PLAT}.cfg
EOF
