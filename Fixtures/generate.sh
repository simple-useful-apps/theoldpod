#!/bin/zsh
# Regenerates the test-fixture MP3s. Requires ffmpeg (brew install ffmpeg).
# All audio is synthesized sine tones — no copyrighted material.
set -euo pipefail
cd "$(dirname "$0")"

# CBR, fully ID3v2-tagged, no artwork
ffmpeg -y -f lavfi -i "sine=frequency=440:duration=3" \
  -codec:a libmp3lame -b:a 128k -id3v2_version 3 \
  -metadata title="Fixture One" -metadata artist="The Fixtures" \
  -metadata album="Test Tones" -metadata track="1/4" -metadata date="2001" \
  -metadata genre="Electronic" \
  cbr-tagged.mp3

# VBR, fully tagged
ffmpeg -y -f lavfi -i "sine=frequency=523:duration=3" \
  -codec:a libmp3lame -q:a 4 -id3v2_version 3 \
  -metadata title="Fixture Two" -metadata artist="The Fixtures" \
  -metadata album="Test Tones" -metadata track="2/4" -metadata date="2001" \
  -metadata genre="Electronic" \
  vbr-tagged.mp3

# Tagged with embedded cover art
ffmpeg -y -f lavfi -i "color=c=0x8888ff:size=300x300:duration=0.04" -frames:v 1 cover.png
ffmpeg -y -f lavfi -i "sine=frequency=659:duration=3" -i cover.png \
  -map 0:a -map 1:v -codec:a libmp3lame -b:a 128k -c:v png \
  -id3v2_version 3 \
  -metadata title="Fixture Three" -metadata artist="Other Artist" \
  -metadata album="Covered" -metadata track="1/1" \
  -metadata:s:v title="Album cover" -metadata:s:v comment="Cover (front)" \
  art-tagged.mp3
rm cover.png

# No tags at all (title must fall back to filename)
ffmpeg -y -f lavfi -i "sine=frequency=330:duration=3" \
  -codec:a libmp3lame -b:a 128k -map_metadata -1 -write_id3v2 0 -write_xing 1 \
  untagged.mp3

echo "Fixtures regenerated."
