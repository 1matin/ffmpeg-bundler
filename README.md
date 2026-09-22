# ffmpeg-bundler

CI-built FFmpeg 9.0.2 bundles for Windows and macOS.

| Feature | Win x64 | Win ARM64 | macOS x64 | macOS ARM64 |
|---|:---:|:---:|:---:|:---:|
| libdav1d | ✓ | ✓ | ✓ | ✓ |
| libx264 | ✓ | ✓ | ✓ | ✓ |
| h264_mf | ✓ | ✓ | | |
| h264_videotoolbox | | | ✓ | ✓ |
| h264_nvenc | ✓ | | | |
| h264_qsv | ✓ | | | |
| h264_amf | ✓ | | | |

Windows ARM64 intentionally excludes NVENC, QSV and AMF.

## Artifacts

The workflow builds native Windows x64/ARM64 and macOS x64/ARM64 packages, plus a Universal 2 macOS package. Tags matching `v*` are also published as GitHub Releases.

Every package contains `ffmpeg`, `ffprobe`, SHA-256 hashes, build information, and collected dependency license files.

Hardware encoders are checked for registration. CI machines usually have no compatible discrete GPU, so actual NVENC/QSV/AMF/MF hardware initialization must be probed on the end user's machine.

## Runtime selection

Windows x64: prefer `h264_nvenc` on NVIDIA, `h264_qsv` on Intel, `h264_amf` on AMD, then `h264_mf -hw_encoding 1`, then `libx264`.

Windows ARM64: prefer `h264_mf -hw_encoding 1`, then `libx264`.

macOS: prefer `h264_videotoolbox`, then `libx264`.

Do a tiny probe encode before selecting a hardware backend. `ffmpeg -encoders` proves compilation, not usable hardware.

## Reproduction

Pins are in `scripts/versions.sh`. GitHub Actions is the reference build environment.

- macOS: `scripts/build-macos.sh x86_64` or `scripts/build-macos.sh arm64`
- Windows x64: run `scripts/build-windows-x64.sh` from MSYS2 MinGW64
- Windows ARM64: run `scripts/build-windows-arm64.sh` on Ubuntu x64; it cross-compiles a native ARM64 PE executable, which CI subsequently runs on a Windows ARM64 runner.

## Licensing

Because libx264 is enabled, FFmpeg is built with `--enable-gpl`. The builds do not use `--enable-nonfree`.

This repository does not make a legal determination about distributing these binaries with a proprietary application. Review the GPL obligations for your distribution model before shipping.
