#!/bin/sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
repo_dir=$(CDPATH= cd -- "$script_dir/.." && pwd)
"$script_dir/build-wma-helper.sh"

helper_dir="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Helpers"
helper="$helper_dir/TheOldPodWMAConverter"
mkdir -p "$helper_dir"
cp "$repo_dir/.build/wma-helper/universal/TheOldPodWMAConverter" "$helper"
chmod 755 "$helper"

materials_dir="$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH/ThirdParty/FFmpeg"
mkdir -p "$materials_dir"
cp "$repo_dir/ThirdParty/FFmpeg/COPYING.LGPLv2.1" "$materials_dir/"
cp "$repo_dir/ThirdParty/FFmpeg/CONFIGURATION.txt" "$materials_dir/"
cp "$repo_dir/ThirdParty/FFmpeg/NOTICE.md" "$materials_dir/"
cp "$repo_dir/ThirdParty/FFmpeg/README.md" "$materials_dir/"
cp "$repo_dir/ThirdParty/FFmpeg/ffmpeg-8.1.2.tar.xz" "$materials_dir/"

signing_identity="${EXPANDED_CODE_SIGN_IDENTITY:--}"
/usr/bin/codesign --force --sign "$signing_identity" \
    --entitlements "$repo_dir/ThirdParty/FFmpeg/WMAHelper.entitlements" \
    --options runtime --timestamp=none "$helper"
