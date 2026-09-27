# FFmpeg used by The Old Pod

The macOS edition of The Old Pod includes a minimal FFmpeg 8.1.2 command-line
helper solely to decode WMA audio and encode AAC-in-M4A during local import,
and to stream-copy MP3/M4A audio while updating metadata. Metadata editing
does not re-encode audio. The helper is not present in the iPhone app and is
never used for DRM removal.

FFmpeg is Copyright (c) 2000-2026 the FFmpeg developers and is licensed under
the GNU Lesser General Public License version 2.1 or later. The included build
disables GPL and non-free components. See `COPYING.LGPLv2.1` for the license.

The exact, unmodified upstream source archive used for this build is included
as `ffmpeg-8.1.2.tar.xz`. Its SHA-256 checksum is:

`464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c`

Build configuration and reproduction instructions are in `CONFIGURATION.txt`
and `README.md`.
