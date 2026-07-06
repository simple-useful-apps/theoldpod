# theoldpod

A music player for people who own their music.

**theoldpod** is a pair of apps — iPhone and Mac — that play the MP3s you already have. There is no store, no streaming, no account, no subscription, no ads, no recommendations, and no server anywhere. Your library is a folder of files in your iCloud Drive; the apps are two views onto that folder. Drag an album in from the Finder, and it's on your phone. Delete a file, and it's gone everywhere. The files are the truth; the apps never hold your music hostage.

It should feel the way iTunes and the iPod felt before they got complicated: you see your music — Artists, Albums, Songs, Playlists — you pick something, and it plays. The whole app can be understood in one sitting. Every screen answers "what's playing, and what's next?"

## Principles

1. **Local-first, files-first.** MP3 files in a visible iCloud Drive folder are the single source of truth. The database is just an index and can always be rebuilt from the files. Works fully offline; works (locally) with no iCloud account at all.
2. **Utilitarian, but beautiful.** Modern, idiomatic SwiftUI on both platforms — native navigation, native gestures, Liquid Glass where the system provides it. The iPod/iTunes spirit comes through in *structure and feeling*, not skeuomorphic costume: dense legible lists, album art treated as the hero, a persistent "what's playing" surface, instant response to every tap, and a few loving touches (a circular scrubber that nods to the click wheel, classic sort orders, the old status-line typography for time readouts).
3. **Calm.** No badges, no upsells, no "engagement." The app wants nothing from you.
4. **Each platform its native self.** The iPhone app is a great iPhone app (one-handed browsing, lock-screen and Control Center transport, background audio). The Mac app is a great Mac app (sidebar, searchable song table, media keys, mini-player) — old iTunes in spirit, current macOS in idiom.

## v1 delivers

Library import & indexing from the shared folder; Artists/Albums/Songs/Playlists browsing; play/pause/next/previous, queue, shuffle, repeat; Now Playing with artwork; playlists (create, edit, reorder); lock-screen/Control Center (iOS) and Now Playing/media keys (Mac).

## Non-goals

**Forever:** streaming services, a store, social features, cloud databases, analytics, ads.

**For v1:** video, podcasts-as-a-feature, smart playlists, EQ, AirPlay 2 multi-room, CarPlay, library editing of ID3 tags.
