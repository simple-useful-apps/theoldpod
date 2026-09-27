# Reproducing The Old Pod's FFmpeg helper

From the repository root on a Mac with Xcode selected, run:

```sh
scripts/build-wma-helper.sh
```

The script verifies the checked-in upstream archive checksum, builds isolated
arm64 and x86_64 static configurations without network, GPL, non-free, or
unneeded features. In addition to WMA conversion, the minimal build can
stream-copy MP3 and M4A files when the Mac app updates their metadata. It
combines the executables at:

`.build/wma-helper/universal/TheOldPodWMAConverter`

The Xcode Mac target runs `scripts/embed-wma-helper.sh`, which uses that build
script, copies the helper into `Contents/Helpers`, and signs it with only the
App Sandbox and inherited-sandbox entitlements before the parent app is signed.
The app bundle also contains this directory under Resources/ThirdParty/FFmpeg.
