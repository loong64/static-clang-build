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
STATIC_CLANG_VERSION=22.1.6.0
STATIC_CLANG_FILENAME="static-clang-linux-${GO_ARCH}.tar.xz"
STATIC_CLANG_URL="https://github.com/mayeut/static-clang-images/releases/download/v${STATIC_CLANG_VERSION}/${STATIC_CLANG_FILENAME}"
pushd /tmp
cat<<'EOF' | grep "${STATIC_CLANG_FILENAME}" > "${STATIC_CLANG_FILENAME}.sha256"
8caec011807fefa10eff39a58e673c09c0c2406d3ea4f4185dac981ce268f6ea  static-clang-linux-386.tar.xz
057c929cafb12e2f56e9fa12365cfdc8dc8af1cdb211cc96bd8af86f2bcf5f3a  static-clang-linux-amd64.tar.xz
bce1918addf376201ed41772dfb41732a2249db7cd5b2456ec7a817bfe903232  static-clang-linux-arm.tar.xz
768f4ad605ab7be4c4be78c6453a0935a084a71af768e6a7a180a65dffbb3ad4  static-clang-linux-arm64.tar.xz
ee5ba5f3035e6d969d66e1d10a9b9fa05cdd465605291d1438d0eba1286eb684  static-clang-linux-loong64.tar.xz
384cc140300bff4533e62c9f1007b0fdfc7fc48893f352267e4682dd17223e76  static-clang-linux-ppc64le.tar.xz
e984dc59947b2101857eb26915a6d0a34c053b28dfbaca40a79d3ad3c46d341c  static-clang-linux-riscv64.tar.xz
de6b6166b219068a6d93a30a8fe177b3e238ffb818cdba2d59b42c07c04123ae  static-clang-linux-s390x.tar.xz
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
