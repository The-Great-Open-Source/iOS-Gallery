<div align="center">

# Good Gallery

**A better home for your memories.**

A native iOS app that organises your *existing* Photos library into your own collections — without copying, moving or modifying a single photo — with a Liquid Glass interface and built-in local media tools.

`SwiftUI` · `SwiftData` · `PhotoKit` · `AVFoundation` · iOS 17+ · zero dependencies

</div>

---

## Why Good Gallery

Apple Photos is great for viewing, but hard to organise around *your* life. Good Gallery lets you create collections like **Travel**, **University**, **Family** or **Cars**, drop existing photos and videos into them, and keep going — while your Photos library stays exactly as it is.

- **One photo, many collections.** Collections store PhotoKit identifiers only. Nothing is duplicated.
- **Private by design.** No accounts, analytics, servers or third-party SDKs. Everything runs on-device.
- **Safe by default.** Removing an item from a collection never deletes it. Deleting from the library is an explicit, double-confirmed action.

## Features

| Area | What you get |
| --- | --- |
| **Library** | Two-column collection cards with photo covers, create / rename / describe / re-cover / reorder / delete, an *Uncategorized* section, first-run empty state |
| **Collections** | Lazy photo/video grid, sorting, statistics, multi-select, share, remove, handling for assets that went missing |
| **Picker** | Multi-select browser over the whole library, already-added items dimmed, limited-access aware |
| **Viewer** | Immersive full-screen paging, pinch & double-tap zoom, video playback, favourite / share / add / remove / delete / info |
| **Favorites** | In-app favourites (★), deliberately separate from Apple's ♥︎ |
| **Albums** | Your existing Apple Photos albums, kept distinct from Good Gallery collections |
| **Search** | Collections, albums, file names, months/years ("June 2025"), media types — plus **smart search** by content ("sunny days", "beach", "party") using on-device Vision classification |
| **Backup** | Optional, off by default. Google Drive (manual + automatic) and your own Telegram bot (manual), with a maximum file size |
| **Video Compressor** | Three quality presets, 1080p/720p/480p, honest size estimate, progress, cancel, preview, save to Photos or Files |
| **Media Inspector** | Resolution, format, size, dates, codec, frame rate, location coordinates |
| **Settings** | Appearance (Dark / Light / System), permission status, cache & storage, privacy policy, About, feedback |
| **Design** | Dark editorial palette with champagne accent, serif headings, Liquid Glass surfaces (material fallback on iOS 17–18), haptics |

## Getting started

Requirements: Xcode 26+ recommended (builds with Xcode 27), iOS 17.0+ deployment target.

```bash
git clone https://github.com/The-Great-Open-Source/iOS-Gallery.git
cd iOS-Gallery
open "Good Gallery.xcodeproj"
```

1. Select an iPhone simulator or a connected device and set your signing team (*Signing & Capabilities*).
2. Run. On first launch, allow Photos access (*Full* or *Selected Photos* both work).
3. On the simulator, add test media with:
   ```bash
   xcrun simctl addmedia booted path/to/photo.jpg path/to/video.mp4
   ```

The privacy strings (`NSPhotoLibraryUsageDescription`, `NSPhotoLibraryAddUsageDescription`) are set through `INFOPLIST_KEY_*` build settings.

## Architecture

```
Good Gallery/
├── App/            Entry point, RootView (permission gate + tabs), DEBUG-only harness
├── DesignSystem/   Tokens, glass modifier, button styles, cards, thumbnails, grids
├── Data/           SwiftData models + CollectionStore (all metadata mutations)
├── Media/          PhotoLibrary, ImageLoader, MediaInfo, MediaExporter,
│                   VideoCompressor, MediaSearchIndex
└── Features/       Library · Collections · Picker · Viewer · Favorites ·
                    Albums · Tools · Search · Settings
```

**Layering.** Views contain no business logic. They talk to `CollectionStore` (metadata), `PhotoLibrary` (authorisation & change notifications) and the media layer. Dependencies are injected as environment objects together with the SwiftData `modelContainer`.

**Data model.**

```
MediaCollection ──< CollectionMedia >── (PhotoKit localIdentifier)
FavoriteMedia          (PhotoKit localIdentifier)
CompressionRecord      (history of compressions)
```
Deleting a `MediaCollection` cascades only to its join rows.

**Performance.** Grids are `LazyVGrid`; the picker walks a lazy `PHFetchResult`; thumbnails go through `PHCachingImageManager` with cancellation and a ~80 MB `NSCache`; fetches and enumeration run in detached tasks; the full-screen viewer uses a lazy horizontal pager and loads images progressively, including iCloud download progress.

### Video compression

`AVAssetReader` → `AVAssetWriter` with explicit bitrate control:

- Presets set a target bits-per-pixel (HEVC when available, H.264 fallback) and are capped below the source bitrate so files never grow needlessly.
- Resolution limits the *shorter* side (1080 / 720 / 480) and never upscales.
- The estimate and the encoder share one `CompressionPlan`, so they can't disagree; the real output size is always shown afterwards.
- Cancellation, free-space check, background grace time, preview, save to Photos / Files. The original is never touched unless you explicitly choose *Delete Original*.

### Permissions & limited access

Photos access is requested after an explanatory welcome screen. Under **Limited Access**, assets outside the shared selection can look "missing", so Good Gallery **never auto-prunes** them; clean-up is offered only with full access. A banner offers *Select More Photos* and a shortcut to Settings.

## Backup

Backup is opt-in (Settings → Backup) and sends files straight from the phone to the user's *own* accounts — nothing passes through any server of ours.

- **Limits:** a maximum file size (10 MB – 2 GB), include photos and/or videos, Wi-Fi-only option. Oversized files are skipped and reported. Items already sent are remembered (`BackupRecord`) and never re-sent.
- **Telegram (manual):** each user creates their own bot with @BotFather, pastes the token (stored in the Keychain) and taps *Detect Chat*. Files go via `sendDocument`; the Bot API caps uploads at **50 MB**, so the lower of the two limits applies.
- **Google Drive (manual + automatic):** OAuth 2.0 + PKCE through `ASWebAuthenticationSession` (no SDK), scope `drive.file`, resumable uploads streamed from disk into *Good Gallery Backup / <collection>*. Automatic mode backs up new items of the collections the user selects, when the app becomes active and via a `BGProcessingTask` (iOS decides when it runs).
- **One-time setup for Drive:** create an OAuth **iOS** client ID in Google Cloud Console (Drive API enabled, bundle ID `com.harshanacz.Good-Gallery`) and paste it into `GoogleDriveConfig.clientID` (`Media/Backup/GoogleDriveService.swift`). Until then the Drive controls stay hidden.

## Smart search

`PhotoTagIndexer` classifies each photo once with Apple's `VNClassifyImageRequest` (≈1,300 labels), stores the top labels locally (`PhotoTags`) and resumes where it left off. Queries are mapped to labels through a curated concept map (`SearchConcepts`, e.g. *sunny* → `sun`, `blue_sky`, `sky`) plus exact label words, then photos are ranked by label confidence. Everything runs on-device; iCloud-only photos are skipped until they're local. A CLIP-style model could replace the concept map later for fully free-text search.

## Privacy

Good Gallery stores only lightweight metadata locally (collection names, which assets belong to which collection, favourites, compression history, backup history, on-device image labels). It never uploads media on its own — the only exception is the opt-in Backup feature, which sends files directly to the user's own Drive/Telegram. No accounts, no analytics, no third-party SDKs. See the in-app *Privacy Policy*.

## Debug harness

DEBUG builds accept launch arguments for verifying flows without UI scripting:

| Argument | Effect |
| --- | --- |
| `-gg-seed` | Create sample collections from your library |
| `-gg-tab favorites\|albums\|tools` | Start on a tab |
| `-gg-open collection\|uncategorized` | Auto-navigate |
| `-gg-viewer N` | Open the viewer at item N |
| `-gg-selftest` | Compress real videos, test cancel, inspector, save and share; logs `SELFTEST …` |

## Known limitations

- `localIdentifier`s can change after a restore/migration. Planned: also store `PHCloudIdentifier` and remap on launch.
- Collections are reordered via a sheet, not by dragging in the grid; multi-select of collections isn't implemented yet.
- Slo-mo / composition videos aren't supported by the compressor; HDR sources are re-encoded as 8-bit SDR.
- Slo-mo-like cases aside, Telegram backup is limited to 50 MB per file by Telegram; automatic backup depends on iOS background scheduling.
- Smart search understands a curated vocabulary (sky, beach, food, people, cars, pets, …), not arbitrary sentences.
- The feedback address (`AppInfo.feedbackEmail`) is a placeholder.

## Roadmap

Cloud-identifier reconciliation · drag-to-reorder · iPad layout · widgets · on-device smart suggestions (opt-in).

## Contributing

Issues and pull requests are welcome. Please keep changes focused, follow the existing layering (no business logic in views) and keep everything on-device.
