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
./configure --prefix="$PREFIX" --enable-static --disable-cli
make -j"$(nproc)"
make install
popd

clone_checkout https://code.videolan.org/videolan/dav1d.git "$DAV1D_VERSION" "$WORK/dav1d-$TARGET"
pushd "$WORK/dav1d-$TARGET"
meson setup build --wipe --prefix="$PREFIX" --default-library=static -Denable_tools=false -Denable_tests=false
ninja -C build -j"$(nproc)"
ninja -C build install
popd

clone_checkout https://github.com/FFmpeg/nv-codec-headers.git "$NV_CODEC_HEADERS_VERSION" "$WORK/nv-codec-headers"
make -C "$WORK/nv-codec-headers" PREFIX="$PREFIX" install

clone_checkout https://github.com/intel/libvpl.git "$LIBVPL_VERSION" "$WORK/libvpl-$TARGET"
git -C "$WORK/libvpl-$TARGET" apply --check "$ROOT/patches/libvpl-mingw-msvc-guard.patch"
git -C "$WORK/libvpl-$TARGET" apply "$ROOT/patches/libvpl-mingw-msvc-guard.patch"
cmake -S "$WORK/libvpl-$TARGET" -B "$WORK/libvpl-$TARGET/build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="$PREFIX" \
  -DBUILD_SHARED_LIBS=OFF
cmake --build "$WORK/libvpl-$TARGET/build" --parallel
cmake --install "$WORK/libvpl-$TARGET/build"

test -f "$PREFIX/lib/pkgconfig/vpl.pc"
echo "oneVPL pkg-config version: $(pkg-config --modversion vpl)"
echo "oneVPL static libs: $(pkg-config --libs --static vpl)"
cat > "$WORK/test-vpl.cpp" <<'EOF'
#include <vpl/mfxdispatcher.h>
int main() {
    mfxLoader loader = MFXLoad();
    if (loader) MFXUnload(loader);
    return 0;
}
EOF
c++ -O2 -static-libgcc -static-libstdc++ "$WORK/test-vpl.cpp" \
  $(pkg-config --cflags --libs --static vpl) -o "$WORK/test-vpl.exe"

clone_checkout https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git "$AMF_VERSION" "$WORK/amf"
mkdir -p "$PREFIX/include/AMF"
cp -R "$WORK/amf/amf/public/include/." "$PREFIX/include/AMF/"

clone_checkout https://git.ffmpeg.org/ffmpeg.git "$FFMPEG_TAG" "$WORK/ffmpeg-$TARGET"
pushd "$WORK/ffmpeg-$TARGET"
./configure \
  --prefix="$PREFIX/ffmpeg" \
  --target-os=mingw32 \
  --arch=x86_64 \
  --enable-gpl \
  --enable-libx264 \
  --enable-libdav1d \
  --enable-mediafoundation \
  --enable-libvpl \
  --enable-nvenc \
  --enable-amf \
  --extra-cflags="-I$PREFIX/include -I$PREFIX/include/AMF" \
  --extra-ldflags="-L$PREFIX/lib -static-libgcc -static-libstdc++" \
  --pkg-config-flags=--static \
  --disable-ffplay \
  --disable-debug
make -j"$(nproc)"
make install
popd

cp "$PREFIX/ffmpeg/bin/ffmpeg.exe" "$PREFIX/ffmpeg/bin/ffprobe.exe" "$OUT/"
write_manifest "$OUT" "$TARGET"
collect_licenses "$OUT" \
  "FFmpeg-GPL:$WORK/ffmpeg-$TARGET/COPYING.GPLv3" \
  "x264-COPYING:$WORK/x264-$TARGET/COPYING" \
  "dav1d-COPYING:$WORK/dav1d-$TARGET/COPYING" \
  "nv-codec-headers-LICENSE:$WORK/nv-codec-headers/LICENSE" \
  "oneVPL-LICENSE:$WORK/libvpl-$TARGET/LICENSE"

bash "$ROOT/scripts/verify.sh" "$OUT/ffmpeg.exe" "$TARGET" "$OUT/build-info.txt"

for exe in ffmpeg.exe ffprobe.exe; do
  {
    echo
    echo "PE imports for $exe:"
    objdump -p "$OUT/$exe" | grep -i "DLL Name:" || true
  } >> "$OUT/build-info.txt"
  if objdump -p "$OUT/$exe" | grep -Ei "DLL Name:.*(libstdc\+\+|libgcc|libwinpthread|msys-2)" >/dev/null; then
    echo "Unexpected MinGW/MSYS runtime dependency in $exe"
    objdump -p "$OUT/$exe" | grep -i "DLL Name:"
    exit 1
  fi
done

file "$OUT/ffmpeg.exe" >> "$OUT/build-info.txt"
(cd "$OUT" && sha256sum ffmpeg.exe ffprobe.exe > SHA256SUMS)
