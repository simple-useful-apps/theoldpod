---
name: design-language
description: The theoldpod visual and interaction language. Load before ANY UI work on either platform — view code, DesignSystem tokens, empty states, or layout decisions.
---

# theoldpod design language

The iPod/iTunes spirit lives in **structure and feeling, not costume**. We evoke 2004 with density, clarity, and speed — never with leather, wood, brushed metal, fake LCDs, or hand-drawn glass. System Liquid Glass materials are the only "glass" allowed.

## Feel

- **Dense and legible.** Music apps are lists. Default row density, full-width hairline separators, no cards, no extra padding "to breathe." A library screen should show as many songs as the platform idiom allows.
- **Instant.** No loading spinners for local data; lists render from SwiftData immediately. Animations are system defaults only — nothing springy or showy.
- **Calm.** No badges, banners, or prompts. Empty states invite, never nag.

## Typography

- System fonts everywhere. Navigation uses large titles on iOS.
- Song title: `.body`; artist/album metadata: `.subheadline` + `.secondary`.
- **All time readouts use `OldPodTypography.timeReadout()`** (DesignSystem) — monospaced digits, the classic iTunes status-line nod. Durations format as `m:ss` (`h:mm:ss` at ≥ 1 hour). Never truncate a duration.

## Color & materials

- System backgrounds and label colors only; rely on light/dark adaptivity — never hardcode hex backgrounds.
- One accent color (system blue for now — a considered custom blue may land in M6; never introduce a second accent).
- Artwork is the only saturated element on a screen. Let it be the hero.

## Artwork

- Always square, `RoundedRectangle` clip: radius 4 at list size (~48pt), 8 at grid size, 16 on Now Playing.
- **Never blank.** Missing artwork shows the DesignSystem placeholder (music note on quaternary fill).

## Classic behaviors (the iPod soul)

- Sort ignores leading "The " for artists ("The Beatles" under B).
- Empty artist/album tags display as "Unknown Artist" / "Unknown Album" — never blank strings.
- Album track lists sort by disc then track number; songs lists sort by title.
- Every screen answers "what's playing, and what's next?" — once the player exists (M2+), a persistent now-playing surface is always reachable: mini-bar above the iOS tab bar, player bar at the top of the Mac window.

## Platform idioms

- **iOS:** TabView (Artists / Albums / Songs / Playlists), `NavigationStack` per tab, thumb-reachable actions, swipe actions for queue/playlist ops. Portrait-first.
- **macOS:** sidebar + content, sortable `Table` for songs, menu-bar commands with shortcuts (space = play/pause), mini-player window. It should feel like a Mac utility, not a ported phone app.

## Empty states

Every list handles empty: SF Symbol + one sentence + one concrete action or path, e.g. "Drop MP3s into ~/Music-folder-path to get started." Use `ContentUnavailableView`.

## Forbidden

Custom nav bars, hamburger menus, floating action buttons, onboarding carousels, card-based library layouts, skeleton shimmer loaders, confetti, haptic spam, second accent colors, skeuomorphic textures.
