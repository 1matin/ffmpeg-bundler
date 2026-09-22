#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/common.sh"
TARGET=windows-arm64
PREFIX="$WORK/prefix-$TARGET"; OUT="$DIST/$TARGET"
TOOLROOT="$WORK/llvm-mingw"
rm -rf "$PREFIX" "$OUT"; mkdir -p "$PREFIX" "$OUT"

if [[ ! -x "$TOOLROOT/bin/aarch64-w64-mingw32-clang" ]]; then
  curl -fL "https://github.com/mstorsjo/llvm-mingw/releases/download/$LLVM_MINGW_VERSION/llvm-mingw-$LLVM_MINGW_VERSION-ucrt-ubuntu-22.04-x86_64.tar.xz" -o "$WORK/llvm-mingw.tar.xz"
  rm -rf "$TOOLROOT.tmp"; mkdir -p "$TOOLROOT.tmp"
  tar -xf "$WORK/llvm-mingw.tar.xz" -C "$TOOLROOT.tmp" --strip-components=1
  mv "$TOOLROOT.tmp" "$TOOLROOT"
fi
export PATH="$TOOLROOT/bin:$PATH"
export CC=aarch64-w64-mingw32-clang
export CXX=aarch64-w64-mingw32-clang++
export AR=aarch64-w64-mingw32-ar
export RANLIB=aarch64-w64-mingw32-ranlib
export STRIP=aarch64-w64-mingw32-strip
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
CROSS="$WORK/cross-arm64.ini"
cat > "$CROSS" <<EOF
[binaries]
c = '$CC'
cpp = '$CXX'
ar = '$AR'
strip = '$STRIP'
windres = 'aarch64-w64-mingw32-windres'
[host_machine]
system = 'windows'
cpu_family = 'aarch64'
cpu = 'aarch64'
endian = 'little'
EOF

clone_checkout https://code.videolan.org/videolan/x264.git "$X264_COMMIT" "$WORK/x264-$TARGET"
pushd "$WORK/x264-$TARGET"
./configure --prefix="$PREFIX" --host=aarch64-w64-mingw32 --cross-prefix=aarch64-w64-mingw32- --enable-static --disable-cli
make -j"$(nproc)" && make install
popd

clone_checkout https://code.videolan.org/videolan/dav1d.git "$DAV1D_VERSION" "$WORK/dav1d-$TARGET"
pushd "$WORK/dav1d-$TARGET"
meson setup build --wipe --cross-file "$CROSS" --prefix="$PREFIX" --default-library=static -Denable_tools=false -Denable_tests=false
ninja -C build -j"$(nproc)" && ninja -C build install
popd

clone_checkout https://git.ffmpeg.org/ffmpeg.git "$FFMPEG_TAG" "$WORK/ffmpeg-$TARGET"
pushd "$WORK/ffmpeg-$TARGET"
./configure --prefix="$PREFIX/ffmpeg" --target-os=mingw32 --arch=aarch64 --cross-prefix=aarch64-w64-mingw32- --cc="$CC" --cxx="$CXX" --pkg-config=pkg-config --enable-cross-compile --enable-gpl --enable-libx264 --enable-libdav1d --enable-mediafoundation --disable-nvenc --disable-libvpl --disable-amf --extra-cflags="-I$PREFIX/include" --extra-ldflags="-L$PREFIX/lib" --pkg-config-flags=--static --disable-ffplay --disable-debug
make -j"$(nproc)" && make install
popd

cp "$PREFIX/ffmpeg/bin/ffmpeg.exe" "$PREFIX/ffmpeg/bin/ffprobe.exe" "$OUT/"

# LLVM-MinGW links these runtime DLLs dynamically by default. Bundle every
# non-system runtime DLL our ARM64 binaries import so they launch on a clean
# Windows ARM64 machine.
for dll in libc++.dll libunwind.dll; do
  src="$(find "$TOOLROOT" -type f -iname "$dll" -print -quit)"
  [[ -n "$src" ]] || { echo "Required runtime DLL not found: $dll"; exit 1; }
  cp "$src" "$OUT/$dll"
done

write_manifest "$OUT" "$TARGET"
collect_licenses "$OUT" "FFmpeg-GPL:$WORK/ffmpeg-$TARGET/COPYING.GPLv3" "x264-COPYING:$WORK/x264-$TARGET/COPYING" "dav1d-COPYING:$WORK/dav1d-$TARGET/COPYING"
file "$OUT/ffmpeg.exe" >> "$OUT/build-info.txt"
(cd "$OUT" && sha256sum ffmpeg.exe ffprobe.exe libc++.dll libunwind.dll > SHA256SUMS)
