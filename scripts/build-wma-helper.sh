#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
archive="$repo_dir/ThirdParty/FFmpeg/ffmpeg-8.1.2.tar.xz"
work_dir="$repo_dir/.build/wma-helper"
expected_sha="464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c"
output="$work_dir/universal/TheOldPodWMAConverter"
stamp="$work_dir/build.sha256"

actual_sha=$(shasum -a 256 "$archive" | awk '{print $1}')
if [ "$actual_sha" != "$expected_sha" ]; then
    echo "FFmpeg source checksum mismatch" >&2
    exit 1
fi

script_sha=$(shasum -a 256 "$0" | awk '{print $1}')
build_sha="$actual_sha-$script_sha"
if [ -x "$output" ] && [ -f "$stamp" ] && [ "$(sed -n '1p' "$stamp")" = "$build_sha" ]; then
    exit 0
fi

source_dir="$work_dir/source"
mkdir -p "$work_dir" "$work_dir/universal"
if [ ! -f "$source_dir/configure" ]; then
    rm -rf "$source_dir"
    mkdir -p "$source_dir"
    tar -xJf "$archive" -C "$source_dir" --strip-components=1
fi

common_args="--disable-everything --disable-autodetect --disable-network --disable-doc --disable-debug --disable-shared --enable-static --disable-gpl --disable-nonfree --disable-programs --enable-ffmpeg --enable-avcodec --enable-avformat --enable-avutil --enable-avfilter --enable-swresample --enable-zlib --enable-protocol=file --enable-demuxer=asf --enable-demuxer=mov --enable-demuxer=mp3 --enable-decoder=wmav1 --enable-decoder=wmav2 --enable-decoder=wmapro --enable-decoder=wmalossless --enable-decoder=mjpeg --enable-decoder=png --enable-parser=mjpeg --enable-parser=png --enable-encoder=aac --enable-muxer=mp4 --enable-muxer=mp3 --enable-filter=aformat --enable-filter=aresample --enable-small --target-os=darwin"

build_slice() {
    slice_arch="$1"
    slice_dir="$work_dir/$slice_arch"
    mkdir -p "$slice_dir"
    cd "$slice_dir"
    cross_arg=""
    assembly_arg=""
    if [ "$(uname -m)" != "$slice_arch" ]; then
        cross_arg="--enable-cross-compile"
    fi
    if [ "$slice_arch" = "x86_64" ]; then
        assembly_arg="--disable-x86asm"
    fi
    # Argument splitting here is intentional: FFmpeg configure accepts each
    # whitespace-delimited option, while the compiler value remains quoted.
    "$source_dir/configure" $common_args $cross_arg $assembly_arg \
        --arch="$slice_arch" \
        --cc="xcrun clang -arch $slice_arch" \
        --extra-ldflags="-arch $slice_arch"
    make -j4 ffmpeg
}

build_slice arm64
build_slice x86_64
xcrun lipo -create "$work_dir/arm64/ffmpeg" "$work_dir/x86_64/ffmpeg" -output "$output"
chmod 755 "$output"
printf '%s\n' "$build_sha" > "$stamp"

file "$output"
otool -L "$output"
