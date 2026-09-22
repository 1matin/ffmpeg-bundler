#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
source "$ROOT/scripts/common.sh"
TARGET=windows-x64
PREFIX="$WORK/prefix-$TARGET"; OUT="$DIST/$TARGET"
export PKG_CONFIG_PATH="$PREFIX/lib/pkgconfig"
export PATH="$PREFIX/bin:$PATH"
rm -rf "$PREFIX" "$OUT"; mkdir -p "$PREFIX" "$OUT"

clone_checkout https://code.videolan.org/videolan/x264.git "$X264_COMMIT" "$WORK/x264-$TARGET"
pushd "$WORK/x264-$TARGET"
./configure --prefix="$PREFIX" --host=x86_64-w64-mingw32 --cross-prefix=x86_64-w64-mingw32- --enable-static --disable-shared --disable-cli
make -j"$(nproc)" && make install
popd

clone_checkout https://code.videolan.org/videolan/dav1d.git "$DAV1D_VERSION" "$WORK/dav1d-$TARGET"
pushd "$WORK/dav1d-$TARGET"
meson setup build --wipe --prefix="$PREFIX" --default-library=static -Denable_tools=false -Denable_tests=false
ninja -C build -j"$(nproc)" && ninja -C build install
popd

clone_checkout https://github.com/FFmpeg/nv-codec-headers.git "$NV_CODEC_HEADERS_VERSION" "$WORK/nv-codec-headers"
make -C "$WORK/nv-codec-headers" PREFIX="$PREFIX" install

clone_checkout https://github.com/intel/libvpl.git "$LIBVPL_VERSION" "$WORK/libvpl-$TARGET"
cmake -S "$WORK/libvpl-$TARGET" -B "$WORK/libvpl-$TARGET/build" -G Ninja -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX="$PREFIX" -DBUILD_SHARED_LIBS=OFF -DBUILD_TOOLS=OFF -DBUILD_EXAMPLES=OFF
cmake --build "$WORK/libvpl-$TARGET/build" --parallel && cmake --install "$WORK/libvpl-$TARGET/build"

clone_checkout https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git "$AMF_VERSION" "$WORK/amf"
mkdir -p "$PREFIX/include/AMF"
cp -R "$WORK/amf/amf/public/include/." "$PREFIX/include/AMF/"

clone_checkout https://git.ffmpeg.org/ffmpeg.git "$FFMPEG_TAG" "$WORK/ffmpeg-$TARGET"
pushd "$WORK/ffmpeg-$TARGET"
./configure --prefix="$PREFIX/ffmpeg" --target-os=mingw32 --arch=x86_64 --enable-gpl --enable-libx264 --enable-libdav1d --enable-mediafoundation --enable-libvpl --enable-nvenc --enable-amf --extra-cflags="-I$PREFIX/include -I$PREFIX/include/AMF" --extra-ldflags="-L$PREFIX/lib" --pkg-config-flags=--static --disable-ffplay --disable-debug
make -j"$(nproc)" && make install
popd
cp "$PREFIX/ffmpeg/bin/ffmpeg.exe" "$PREFIX/ffmpeg/bin/ffprobe.exe" "$OUT/"
write_manifest "$OUT" "$TARGET"
collect_licenses "$OUT" "FFmpeg-GPL:$WORK/ffmpeg-$TARGET/COPYING.GPLv3" "x264-COPYING:$WORK/x264-$TARGET/COPYING" "dav1d-COPYING:$WORK/dav1d-$TARGET/COPYING" "nv-codec-headers-LICENSE:$WORK/nv-codec-headers/LICENSE" "oneVPL-LICENSE:$WORK/libvpl-$TARGET/LICENSE"
"$ROOT/scripts/verify.sh" "$OUT/ffmpeg.exe" "$TARGET" "$OUT/build-info.txt"
file "$OUT/ffmpeg.exe" >> "$OUT/build-info.txt"
(cd "$OUT" && sha256sum ffmpeg.exe ffprobe.exe > SHA256SUMS)
