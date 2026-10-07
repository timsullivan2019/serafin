# Serafin — implementation plan, part 2

Polish for 1.0, then Live TV, Downloads and Music as releases 1.1, 1.2 and 1.3.

This document extends `docs/PLAN.md`. Everything in `AGENTS.md` still applies: one task per branch and PR, the definition of done on every task, tests for Core and Playback, previews for Design, no new dependencies without approval, no secrets or real library titles in the repo. Work the phases in order; each ends at a gate that the owner passes on a physical device.

Release mapping:

| Release | Contents | Gate |
| --- | --- | --- |
| 1.0 | Current app plus Phase 3.5 polish | Gate 3 (beta) as already defined |
| 1.1 | Phase 4, Live TV | Gate 4 |
| 1.2 | Phase 5, Downloads | Gate 5 |
| 1.3 | Phase 6, Music (CarPlay follows as 1.3.x once Apple grants the entitlement) | Gate 6 |

Jellyfin endpoints below are REST paths; confirm each generated `Paths.*` name and model in the SDK checkout before use. Target server is Jellyfin 10.10 or newer. Apple APIs named below must be confirmed against the iOS 26 SDK headers in Xcode; never invent a modifier.

---

## 0. Design language addendum

The rules in `AGENTS.md` (glass is the control layer, content is never glass, system components first) are the constitution. These are the specifics for the screens this plan adds, taken from the Apple TV, Music, Podcasts and App Store apps on iOS 26.

### 0.1 Structure patterns to copy

- **Account and settings** live behind a profile button in the top-trailing toolbar of the root screens, presented as a sheet. No Apple media app spends a tab on Settings.
- **Section headers** are `title2` bold with a trailing chevron when the section opens a list. Already correct on Home; make it universal.
- **Empty, error and loading states** use `ContentUnavailableView` (the system component) with an SF Symbol, a title, a one-line description and, where useful, one action button. Use `ContentUnavailableView.search` for no search results. Loading uses geometry-matched skeletons, never a centred spinner on a blank screen.
- **Sheets** use `presentationDetents` (`.medium` for pickers and program details, `.large` for queues and lyrics) and the system's default glass background. No custom sheet chrome.
- **Sorting and filtering** use `Menu` with inline `Picker`s and `Toggle`s, or the existing glass chips. Never a custom popover.
- **Lists** are `List` with `.insetGrouped` style for settings-like content, `LazyVStack` for media rows. Row icons sit in rounded accent squares the way Settings already does them.
- **Grids** are `LazyVGrid` with adaptive columns: posters 2:3 at a 110 pt minimum on iPhone and 160 pt on iPad; album covers 1:1 at 150 pt and 190 pt; landscape 16:9 at 240 pt and 320 pt.
- **Context menus** on every card with a `preview` that shows the artwork, using `contextMenu(menuItems:preview:)`.
- **Pull to refresh** with `.refreshable` on every root list.
- **Toolbars** on the root screens are the system `.toolbar` with glass items; the back button is the system one.

### 0.2 Artwork rules

| Content | Shape | Image preference |
| --- | --- | --- |
| Movie, series, season | 2:3 poster, radius 12 continuous | Primary |
| Episode, movie in Continue Watching, recording, program | 16:9, radius 12 | Thumb → Backdrop → series Backdrop → Primary (never a 2:3 poster letterboxed into 16:9) |
| Album, playlist | 1:1, radius 8, hairline border at 10% white for light art | Primary |
| Artist | Circle | Primary; fallback is a `person` symbol on a tinted circle |
| Channel | 16:9 glass tile, logo centred at 60% width, padding 12 | Primary (channel logos are usually transparent PNGs; always render on a neutral tile, never on a photo) |
| Hero and Now Playing backgrounds | Full bleed | Backdrop; for music, a `MeshGradient` built from `ArtworkTint` colours of the current cover |

Always request sized images (`maxWidth` matching the view at screen scale). Crossfade on load; never pop.

### 0.3 Badges

Media badges follow the Apple TV app: 11 pt uppercase, semibold, thin 1 pt outline capsule in `textSecondary`, no fill. Order: resolution (4K, HD), range (HDR, HDR10+, Dolby Vision), audio (Dolby Atmos, 5.1, 7.1, Lossless), accessibility (CC, SDH, AD). Live content gets a filled red "LIVE" capsule; recordings in progress get a red dot.

### 0.4 Motion and haptics

- `.spring(.snappy)` for state changes, `.smooth` for layout, nothing on scroll.
- `glassEffectID` morphs between a card's play pill and the player's control cluster where both are on screen in sequence.
- Haptics: `.selection` on chip and tab changes, `.impact(.light)` on play, `.success` on a completed download or a set recording, `.warning` on a failed one. Never on scroll or on progress ticks.
- Honour Reduce Motion (no parallax, no morph; crossfade instead) and Reduce Transparency (plain material).

### 0.5 Accessibility baseline for every new screen

VoiceOver labels on every element with state ("Downloading, 42 percent"); custom actions on cards; Dynamic Type through AX5 with layout that wraps rather than truncates; minimum 44 pt hit targets; colour never the sole carrier of meaning (the live badge has text, the progress ring has a label).

---

## Phase 3.5 — Polish for 1.0 (from the screenshot review)

Ship these in 1.0. Each is small; together they decide whether the first screenshots look finished.

### 3.5.1 Move Settings off the tab bar

- Add a profile button to the top-trailing toolbar of Home, Library and Search: a 28 pt circle showing the user's Jellyfin avatar (`/Users/{id}/Images/Primary`) or their initial on an accent circle. Tapping presents the existing Settings screen as a sheet with `.large` detent and a Done button.
- Tab bar becomes Home, Library, Search (search role). Reserve the adaptive Live TV and Music tabs in code behind feature flags, inserted between Library and Search when their phases ship.
- Keep the Settings screen unchanged otherwise.

Acceptance: three tabs; profile button on every root; Settings sheet opens and dismisses with the standard gesture; no regression in deep links.

### 3.5.2 Library landing

The current screen is two rows and a Browse link with 70% of the screen empty.

- Top section: one 16:9 tile per library view, two per row on iPhone, three on iPad. Image is the view's own Primary image when the admin set one; otherwise a client-generated 2×2 collage of the four newest posters in that library, cached. Overlay: library name in `headline` and item count in `caption`, bottom-leading on a bottom gradient.
- Browse section (insetGrouped list with accent icons): Genres, Collections (only if `/Items?IncludeItemTypes=BoxSet` returns any), Favourites, Recently Added, Unwatched. Downloads is added here in Phase 5.
- Genres screen stays a list but each row gets a 36 pt square collage of two posters from that genre.

Acceptance: no empty space below the fold on an iPhone 17 with two libraries; tiles load without pop; previews with `MockLibrary`.

### 3.5.3 Home fixes

- Continue Watching for a movie must use Thumb → Backdrop → Primary, never the poster. Check `LandscapeCard` honours the artwork rules table.
- One card width per row. The first card in Continue Watching renders wider than the second; if that is a deliberate "peek" it must be consistent across rows, otherwise fix the width.
- Section headers that scroll under the status bar must fade through the system top edge effect; apply `.scrollEdgeEffectStyle(.soft, for: .top)` on the root scroll view (iOS 26 API; confirm name) so "Next Up" is never clipped behind the clock.
- Hero: nothing to change. It is correct.

### 3.5.4 Detail page additions

- **Badges row** under the metadata line, built from `mediaStreams`: height ≥ 2160 → 4K, ≥ 720 → HD; `videoRangeType` → HDR, HDR10+, Dolby Vision; audio codec and channels → Dolby Atmos (eac3 with Atmos flag or truehd), 5.1, 7.1, Lossless (flac, alac, truehd); subtitle streams with SDH or forced flags → SDH / CC.
- **Play pill state**: "Resume · 42 min left" with a thin progress line inside the pill when `userData.playbackPositionTicks > 0`; long-press menu offers "Play from beginning". Episodes of a series show "Play S2 E4" with the next episode's title in the metadata line.
- **Trailers row** when `remoteTrailers` is non-empty: 16:9 cards; tapping opens the URL in `SFSafariViewController` (YouTube links) or plays local trailers (`localTrailerCount > 0`, via `/Users/{id}/Items/{id}/LocalTrailers`) in the normal player.
- **Chapters row** when `chapters` is non-empty: 16:9 chapter thumbnails from `/Items/{id}/Images/Chapter/{index}` with the chapter name and start time; tapping starts playback at that position.
- Toolbar: keep the glass capsule with played and favourite; add a `Menu` (ellipsis) with Mark Unplayed, Refresh Metadata (admin only), Share (link to the item on the server's web UI).

Acceptance: badges match the Jellyfin web client's media info for five test items; chapter and trailer rows hide cleanly when absent.

### 3.5.5 Settings fixes

- Section header shows the server's name from `/System/Info/Public` (such as "Living Room"), never the server ID.
- The address line under the server shows a `lock.fill` symbol for HTTPS, or "Local network" in `caption` for a private-address HTTP server, so the user can see at a glance why the warning was accepted.
- Move the accent colour grid into its own screen ("Accent Colour › Red") to shorten the root list; keep the live preview.

### 3.5.6 Search

- Show "Recent" (last ten searches, stored locally) and "Suggested" (six random unplayed titles) when the field is empty, as the Apple TV app does.
- Group results in this order: Shows, Movies, Episodes, People, Collections. People open a person page listing their items (`/Items?PersonIds=`).

### 3.5.7 Sign-in flow, phone-first

The flow led with Quick Connect. On iPhone and iPad, lead with a password and offer Quick Connect as the alternative. Keep Quick Connect first in any future tvOS target, where typing a password is the hard part.

1. The server address field accepts a hostname, IP, host:port or full URL, as now.
2. After the server responds, fetch `GET /Users/Public`. If it returns users, show them as avatar tiles, the Jellyfin web login pattern; tapping one fills in the username.
3. Username and password fields use `textContentType(.username)` and `.password`, so iOS Password AutoFill works, including the system's prompt to save the password after a successful sign-in. The app itself never persists the password, the same rule as before.
4. A secondary "Sign In with Quick Connect" button, hidden when `GET /QuickConnect/Enabled` returns false.
5. Remember the last username per server. Keep the HTTP warning and certificate-pinning sheets exactly as they are.

Acceptance: signing in with a password saved in iCloud Keychain takes two taps and Face ID; Quick Connect still works; no password appears in logs, UserDefaults or the Keychain store.

### 3.5.8 Design pass from the second screenshot review

One PR, with screenshots before and after for each point.

1. Library tiles: remove the centred library-name overlay; keep the bottom-leading name and count; deepen the bottom gradient to 70% at the edge.
2. Library grids: remove the filled sort button from the chip scroller; add a toolbar `Menu` with `arrow.up.arrow.down` containing the sort options as an inline `Picker`.
3. Settings sheet: replace the filled checkmark with a plain glass circle xmark close button.
4. Information > Languages: show three, then "and N more" expanding inline; if more than ten, open a sheet listing them.
5. Hide Information rows whose value is zero or empty; a series' Run Time shows the average episode runtime when available.
6. Accent Colour preview: render the real `HeroHeader` play pill, a tab bar fragment and a Settings row, not a solid fill.
7. Confirm the Search tab uses the system bottom search field on iPhone; if it is custom, switch to the system one.
8. Chapter cards without an image show a dark tile with the chapter number.

### Gate 3.5

Owner review on device of Home, Library, a movie detail, a series detail, Search, Settings and sign-in in light and dark. Then 1.0 proceeds through Phase 3.

---

## Phase 4 — Live TV (release 1.1)

### 4.0 Preconditions

- The owner's server has a tuner and guide data configured; the demo server gets the loop channel described in section 7.
- API inventory (confirm each in the SDK): `GET /LiveTv/Info`; `GET /LiveTv/Channels`; `POST /LiveTv/Programs` (body with `channelIds`, `minStartDate`, `maxStartDate`, `enableImages`, `imageTypeLimit`, `sortBy`) and `GET /LiveTv/Programs/Recommended`; `GET /LiveTv/Programs/{id}`; `GET /LiveTv/Recordings`; `GET /LiveTv/Timers`, `GET /LiveTv/Timers/Defaults?programId=`, `POST /LiveTv/Timers`, `DELETE /LiveTv/Timers/{id}`; `POST /LiveTv/SeriesTimers` and `DELETE /LiveTv/SeriesTimers/{id}` (reserved for 4.x follow-up); `POST /Items/{channelId}/PlaybackInfo`; `POST /LiveStreams/Close?liveStreamId=`; `POST`/`DELETE /UserFavoriteItems/{channelId}`.
- Live playback device profile: HLS with MPEG-TS segments (`container: ts`, `protocol: hls`, video h264 and hevc copy, audio aac, ac3, eac3, mp2 passthrough where AVPlayer supports it, transcode to aac otherwise). Verify on the owner's server that `transcodingUrl` comes back as an `.m3u8` AVPlayer accepts; only then try fMP4 segments as an optimisation.

### 4.1 Core: `LiveTvRepository` and models

In `SerafinCore`, an actor with:

- `info()` → enabled flag and tuner presence. The Live TV tab exists only when `isEnabled` and the current user is in `enabledUsers` (or the list is empty).
- `channels(favouritesOnly:)` → channels with `currentProgram`, sorted by the server's default channel order, paged 100 at a time. Cached for 60 s.
- `programs(channelIds:from:to:)` → guide data in two-hour windows, merged into an in-memory `GuideCache` keyed by channel and hour, evicting outside a ±12 h window around "now".
- `onNow(limit:)` → recommended airing programs with images, for the top row.
- `program(id:)`, `recordings()`, `timers()`, `timerDefaults(programId:)`, `createTimer(_:)`, `deleteTimer(id:)`, `setChannelFavourite(id:on:)`.
- `ChannelLogoURL` and `ProgramImageURL` builders following the artwork rules.

Models: `Channel` (id, number, name, logoURL, isFavourite, currentProgram, nextProgram), `Program` (id, channelId, title, episodeTitle, overview, start, end, isLive, isNew, isRepeat, isMovie, isSports, isNews, isKids, genres, imageURL, timerId, seriesTimerId), `Recording` (reuses the item model with a `status` of scheduled, inProgress, completed), `Timer`.

Tests: decoding fixtures for each endpoint; `GuideCache` merge and eviction; "on now" and "next" derivation from program windows at a fixed clock.

### 4.2 Design: Live TV components

All in `SerafinDesign`, previews from new `MockLiveTv` fixtures (channels, 24 h of programs, recordings), light, dark, AX5.

- `ChannelTile` — 16:9 glass-neutral tile with the logo per the artwork rules; a small number label bottom-trailing; favourite star overlay state.
- `ChannelRow` — tile at 88 × 50, then channel name (`headline`) and number (`caption`), current program title, a time-based progress bar (elapsed of the current program), and "Next: title at 9:30". Swipe actions: favourite, record current program.
- `OnNowCard` — 16:9 program image (falls back to the channel tile on a gradient), program title, channel tile 24 pt and name, elapsed progress bar, LIVE badge.
- `GuideGrid` — the schedule grid. Time header row pinned at top with half-hour ticks; channel column pinned at leading edge with `ChannelTile` at 64 × 36 and number; program cells sized at 6 pt per minute (minimum 44 pt), title and time, truncation to one line, a filled accent tint on the currently airing cell, a vertical glass "now" line across all rows, record badge on cells with a timer. Horizontal scroll is shared by every row; vertical scroll is lazy. A "Now" button in the toolbar scrolls to the current time.
- `ProgramSheet` — `.medium` detent: image, title, episode title, channel, time range and remaining, overview, badges (NEW, LIVE, HD), and one primary button: Watch (if airing) or Record (if upcoming), with a secondary "Record series" menu item reserved for the follow-up task.
- `RecordButton` — a glass circle with `record.circle`; states: idle, scheduled (filled red ring), recording (pulsing red dot, respects Reduce Motion).
- `LiveBadge` and `LivePlayerControls` — the existing player controls plus a LIVE badge at leading, a "Jump to Live" pill that appears when the user is behind the live edge, a Guide button that opens a compact `ProgramSheet` for the current channel, and channel up/down affordances.

### 4.3 Live TV tab: Channels

- Tab appears adaptively (see 3.5.1), symbol `tv`, title "Live TV".
- Layout: "On Now" horizontal row of `OnNowCard`s at the top; then a `List` of `ChannelRow`s with a segmented control in the toolbar: All, Favourites, by group if the server provides `channelGroup` (confirm field; hide otherwise). Search field filters by name and number.
- Tapping a row plays the channel immediately. Long-press shows a context menu: Favourite, View Guide, Record current.
- Empty states: no tuner ("Live TV isn't set up on this server", with a link to Jellyfin's docs), no channels, no guide data (channels still list, with "No guide data" in place of the program line).

### 4.4 Guide

- Push from the toolbar "Guide" button or the On Now row's chevron. Full-screen `GuideGrid`, starting at the current half-hour, with the "now" line visible on open.
- Tapping a cell opens `ProgramSheet`. Tapping a channel tile plays that channel.
- Data loads in two-hour windows as the user scrolls; a thin skeleton fills cells not yet loaded. Favourites filter persists from the Channels screen.
- Performance budget: 200 channels × 24 hours scrolls at 120 Hz on an iPhone 15 with no dropped frames in Instruments; first paint under 400 ms from cached data.

### 4.5 Program detail and recording

- `ProgramSheet` as designed. Record: fetch `timerDefaults(programId:)`, show a confirmation with pre and post padding pickers (defaults from the server), then `createTimer`. Success haptic and the cell gains the record badge. Cancel recording: `deleteTimer`.
- Timers list under the Recordings screen's "Scheduled" segment; swipe to cancel.

### 4.6 Live player

- `PlaybackNegotiator.live(channelId:)` builds the live plan from `PlaybackInfo`; `PlayerEngine` plays the HLS URL with `automaticallyWaitsToMinimizeStalling` on and a live-edge monitor based on `seekableTimeRanges`.
- Controls: `LivePlayerControls`. Pause is allowed (the HLS window buffers); "Jump to Live" seeks to the live edge. Scrubbing is limited to the seekable range.
- Channel up and down: vertical swipe on the player surface, with a glass channel tile toast ("12 · WNBC") during the switch, and a `Menu` of favourite channels on the Guide button for direct jumps.
- On stop, background, or switch: report playback stopped and call `/LiveStreams/Close` with the `liveStreamId`. Never leave a tuner held.
- PiP and AirPlay work as for VOD. Now Playing shows the channel name and program title; artwork is the program image or channel logo on a neutral tile.
- Errors: tuner busy ("All tuners are in use. Try again in a moment."), channel unavailable, stream stalled for more than 10 s (offer Retry). Each is a designed overlay, not an alert.

### 4.7 Recordings

- Recordings screen from the Live TV toolbar: segments Recorded, In Progress, Scheduled. Recorded items use `LandscapeCard`s grouped by series name when applicable, and play through the normal VOD player with resume and progress reporting. In-progress recordings play live from the start with a red dot badge. Delete via swipe (`DELETE /Items/{id}` only if the user policy allows media deletion; otherwise no delete affordance).
- Recordings also appear in Library › Browse when any exist.

### 4.8 Edge cases and server variance

- Guide data missing for some channels: show the program line as "No guide data" and still allow playback.
- EPG with overlapping programs: trust `start` and clip to the next program's `start`.
- Channels without logos: tile shows the channel name set in `caption` bold, centred.
- Time zones: all times come from the server as UTC and render in the device zone; the grid's "now" line uses `Date.now` and the server's clock difference is ignored unless it exceeds five minutes, in which case a one-time notice appears.
- Jellyfin's Live TV has rough edges server-side. The app's job is to make them look intentional: never a raw error string, never an empty black player.

### 4.9 Settings and Intents

- Settings › Live TV: default guide range (12 h, 24 h, 48 h), start playback on tap or show details first, recording padding defaults (display only; the server owns them).
- App Intents: "Watch [channel] in Serafin", "Record [program]". Spotlight indexes favourite channels.

### Gate 4

On the owner's server: watch three channels end to end, switch channels from the player, pause and jump to live, set and cancel a recording, play a finished recording, confirm the tuner is released after each stop (Jellyfin dashboard shows no active stream). On the demo server: the loop channel plays, appears in the guide, and records. Guide performance budget verified in Instruments.

---

## Phase 5 — Downloads (release 1.2)

### 5.0 Preconditions and policy

- Downloads are offered only when the user's policy has `enableContentDownloading` (from `GET /Users/Me`). Otherwise the UI shows no download affordances and Settings explains why.
- The demo server's `reviewer` and `screenshots` accounts get "Allow media downloading" enabled before 1.2 is submitted (update `deploy/demo-server/README.md`).
- Two download paths, decided per media source by `DownloadPlanner`:
  1. **Original file** via `GET /Items/{id}/Download` when the container is mp4, m4v or mov and the video and audio codecs are in the AVPlayer direct-play set. Exact copy, resumable with `Range`.
  2. **Remux** otherwise: `GET /Videos/{id}/stream` with `static=false`, `container=mp4`, `videoCodec=copy` (or `h264,hevc`), `audioCodec=aac,ac3,eac3` (copy when already supported), the chosen `audioStreamIndex`, `subtitleMethod=Embed` for text subtitles and `Encode` (burn-in) when the user picks an image-based subtitle, `mediaSourceId`, `api_key`. The response is a progressive MP4 with unknown length; progress shows as "indeterminate" with bytes received. The agent must verify on the owner's server that the output is seekable and plays from disk; if it is not, fall back to `AVAssetDownloadURLSession` against the HLS remux and store the resulting package, reporting playback progress to the server during the download so the transcode is not throttled.
- Never a transcode that re-encodes video by default; offer "Download in lower quality" (720p h264, 4 Mbps) as an explicit option for cellular users.

### 5.1 Core: store and manager

- `DownloadRecord` (SwiftData): id, serverId, userId, itemId, mediaSourceId, kind (movie, episode), state (queued, downloading, paused, completed, failed), bytesReceived, bytesExpected (optional), path, audioStreamIndex, subtitleStreamIndex, subtitleMode, createdAt, completedAt, lastPlayedAt, autoDelete flag, and an `ItemSnapshot` JSON (title, series, season, episode numbers, runtime, overview, badges, image file paths) so the item displays fully offline.
- `DownloadManager` (actor): wraps a background `URLSession` (identifier `app.getserafin.serafin.downloads`, `isDiscretionary = false`, `sessionSendsLaunchEvents = true`, `allowsCellularAccess` from Settings, `waitsForConnectivity = true`). Concurrency: two active downloads, the rest queued. Persists task identifiers to records so a relaunch reattaches. Handles `handleEventsForBackgroundURLSession` through the `UIApplicationDelegateAdaptor`.
- Files: `Application Support/Downloads/<serverId>/<itemId>/<mediaSourceId>.mp4` plus `poster.jpg`, `thumb.jpg`, `backdrop.jpg` at sensible sizes. Directory excluded from iCloud backup; files written with `.completeUntilFirstUserAuthentication` protection.
- `StorageMonitor`: available space, Serafin's usage, and a low-space guard (refuse to start a download that would leave under 1 GB free).
- `PendingProgressQueue` (SwiftData): playback start, progress and stop reports captured while offline, flushed in order when `NWPathMonitor` reports the server reachable; duplicates collapsed.

Tests: planner decisions for five media-source fixtures; record state machine; queue flush ordering; storage guard.

### 5.2 Design: download components

- `DownloadButton` — a 28 pt control with four states, following the App Store's pattern: `arrow.down.circle` idle; a circular progress ring with a stop square while downloading (indeterminate ring animates when size is unknown); `checkmark.circle.fill` done (opens a menu: Play Offline, Delete); `exclamationmark.circle` failed (Retry). VoiceOver reads the state and percentage.
- `DownloadRow` — `LandscapeCard` thumbnail, title and series line, size, state, progress bar, swipe to delete or pause.
- `StorageBar` — Settings component showing Serafin downloads vs other vs free, like iOS Storage.
- `OfflineBanner` — a thin glass banner under the toolbar: "You're offline. Showing downloads." with a Retry.

### 5.3 Download actions

- Movie detail: `DownloadButton` in the toolbar capsule next to favourite.
- Episode row and episode detail: `DownloadButton` trailing.
- Season screen: "Download Season" in the toolbar menu; a confirmation sheet lists episodes, total size (from `mediaSources[].size`; "about" when remuxing), chosen audio and subtitle, and quality (Original or Lower). Series screen: "Download Next 5 Unwatched".
- Audio and subtitle choice uses the same picker as the player; the default is the user's language preference from Settings.
- Cards everywhere: context menu gains Download / Remove Download.

### 5.4 Downloads library and management

- Library › Browse › Downloads (row appears when there is at least one record). Screen groups by series, then movies; sections for In Progress and Completed; total size in the header. Edit mode for multi-delete.
- Settings › Downloads: Download over cellular (off), Download quality (Original / Lower), Auto-delete after watching (off), Delete All Downloads, and the `StorageBar`.
- Low Power Mode pauses new downloads unless the user overrides.

### 5.5 Offline playback

- `PlayerEngine.load(local:)` plays the file URL; resume position comes from the record (synced with the server's `playbackPositionTicks` when online, local when not).
- Progress reporting goes to the server when reachable, otherwise into `PendingProgressQueue`. Mark played and favourite work the same way.
- Track selection offline: embedded tracks via `AVMediaSelectionGroup`; the player indicates "Downloaded · Direct play".
- Offline Home: when the server is unreachable at launch, Home renders cached rows plus a Downloads section at the top with the `OfflineBanner`. Library shows only Downloads. Search searches downloads.

### 5.6 Lifecycle

- Downloads resume after relaunch, device restart and app update. Interrupted remuxes restart from zero (the server cannot resume a transcode); originals resume by range.
- Signing out or removing a server deletes that server's downloads after a confirmation that states the size.
- A download whose item was deleted on the server stays playable and is flagged "No longer on server".

### Gate 5

Download a movie (original), an MKV episode (remux) and a season on Wi-Fi; put the phone in Airplane Mode; play all three with resume and track switching; mark one played; return online and confirm the progress and played state reached the server in order. Kill the app mid-download and confirm it resumes. Storage numbers in Settings match iOS Settings › Storage within 5%.

---

## Phase 6 — Music (release 1.3)

### 6.0 Preconditions

- The owner has filed the CarPlay Audio entitlement request (developer.apple.com/contact/carplay/); CarPlay work (6.9) starts only after Apple grants it.
- A test music library exists on the owner's server and on the demo server: at least 20 CC-licensed albums with correct tags (Blender's Tears of Steel soundtrack, Free Music Archive CC BY albums), so artists, albums, genres and playlists all have real data. Tag with MusicBrainz Picard so Jellyfin's metadata is complete.
- API inventory (confirm in the SDK): `GET /Artists/AlbumArtists`, `GET /Artists`, `GET /Items` with `IncludeItemTypes=MusicAlbum|Audio|Playlist`, `ArtistIds`, `GenreIds`, `SortBy`, `Filters=IsFavorite`; `GET /Items/{albumId}` plus `GET /Items?ParentId={albumId}&SortBy=ParentIndexNumber,IndexNumber`; `GET /Items/{id}/InstantMix`; `GET /Audio/{id}/Lyrics`; `GET /Playlists/{id}/Items`, `POST /Playlists`, `POST /Playlists/{id}/Items`, `DELETE /Playlists/{id}/Items`, `POST /Playlists/{id}/Items/{itemId}/Move/{index}`; `GET /Genres?IncludeItemTypes=MusicAlbum`; `GET /Items/Latest?IncludeItemTypes=MusicAlbum`; playback reporting through the existing `/Sessions/Playing*` endpoints; streaming via `GET /Audio/{id}/universal`.
- Streaming URL: `/Audio/{id}/universal` with `userId`, `deviceId`, `maxStreamingBitrate` (from Settings: Wi-Fi and cellular), `container=mp3,aac,m4a|aac,m4b|aac,flac,alac,m4a|alac,wav,aiff`, `transcodingContainer=mp4`, `transcodingProtocol=hls`, `audioCodec=aac`, `enableRedirection=true`, `enableRemoteMedia=false`, `api_key`. Direct play for supported formats; HLS AAC for the rest (ogg, opus, wma, dsf).

### 6.1 Core: `MusicRepository`

An actor with `albumArtists(page:)`, `artists(page:)`, `albums(sort:page:)`, `albums(artistId:)`, `tracks(albumId:)`, `tracks(artistId:)` (for Play All), `songs(sort:page:)`, `playlists()`, `playlist(id:)`, `createPlaylist(name:ids:)`, `addToPlaylist`, `removeFromPlaylist`, `movePlaylistItem`, `genres()`, `albums(genreId:)`, `recentlyAdded()`, `recentlyPlayed()`, `mostPlayed()`, `favourites(kind:)`, `instantMix(id:)`, `lyrics(trackId:)`, `setFavourite`. All paged with a persistent on-disk cache keyed by server and user (SwiftData `MusicCacheEntry` with an ETag-style `dateLastSaved` check) so a 20,000-track library opens instantly.

Tests: decoding fixtures; disc and track ordering; playlist mutation sequences against a stub.

### 6.2 Playback: `AudioQueueEngine`

In `SerafinPlayback`, an `@Observable @MainActor` engine separate from the video `PlayerEngine`, sharing the audio session and Now Playing plumbing.

- Queue model: `Queue` of `QueueItem` (track, source URL, albumId, artwork URL); current index; history; shuffle (Fisher–Yates with the current item pinned first); repeat off / all / one.
- `AVQueuePlayer` with the next two items pre-created for gapless transitions; on HLS fallbacks gapless is best-effort.
- Audio session `.playback`, mode `.default`; interruption handling (pause on interruption, resume if `shouldResume`); route change handling (pause when headphones disconnect).
- `MPNowPlayingSession` with artwork, title, artist, album, elapsed and duration; `MPRemoteCommandCenter` play, pause, toggle, next, previous, change position, shuffle, repeat, like.
- Reporting: start, progress every 10 s, and stop to the server for every track so play counts and Last.fm scrobbling (server plugin) work.
- Sleep timer (15, 30, 45, 60 minutes, end of track).
- State persists across launches: queue, index, position, shuffle and repeat, restored on next launch without auto-playing.

Tests: queue operations (shuffle pins current, repeat-one, insert next, move), persistence round trip, reporting sequence against a stub.

### 6.3 Design: music components

All in `SerafinDesign` with `MockMusic` fixtures.

- `AlbumCard` — 1:1 cover per artwork rules, title (`subheadline` semibold, two lines), artist (`caption`, one line), year optional.
- `ArtistCircle` — 96 pt circle, name below.
- `TrackRow` — track number (or an animated equaliser glyph for the playing track, respecting Reduce Motion), title, artist when differing from album artist, explicit badge if the server exposes it, duration, trailing `Menu` (ellipsis): Play Next, Play Last, Add to Playlist, Go to Album, Go to Artist, Favourite, Download, Instant Mix.
- `PlaylistCard` — 1:1 with a 2×2 collage of its first four album covers.
- `NowPlayingView` — full screen sheet (`.large`): background is a `MeshGradient` of four `ArtworkTint` colours from the cover, animating slowly (static under Reduce Motion); cover art at 85% width with radius 12 and a drop shadow, scaled to 0.82 when paused (Apple Music's gesture); title and artist with a marquee only when truncated; a glass scrubber with elapsed and remaining; glass transport cluster (previous, play/pause large, next) in one `GlassEffectContainer`; bottom glass row: lyrics, AirPlay (`AVRoutePickerView`), queue. Swipe down to dismiss to the mini player.
- `MiniPlayer` — the existing component extended for tracks: cover, title and artist, play/pause and next; tapping opens `NowPlayingView`. It lives in `tabViewBottomAccessory` across all tabs and morphs via `glassEffectID` into the full view.
- `QueueSheet` — `.large` detent, "Playing Next" list with drag to reorder (`onMove`), swipe to remove, Shuffle and Repeat toggles in the header, "Clear".
- `LyricsView` — synced lines from `/Audio/{id}/Lyrics` (`start` in ticks), current line at `title2` with the others dimmed, auto-scroll with user scroll override for five seconds; unsynced lyrics render as a scrollable block; no lyrics shows `ContentUnavailableView`.

### 6.4 Music tab

- Tab appears when the user has at least one music library view (`collectionType == "music"`), symbol `music.note`, title "Music".
- Root follows Apple Music's Library screen: a `List` of destinations with accent icons (Recently Added, Artists, Albums, Songs, Playlists, Genres, Favourites, Downloaded — the last two appear when non-empty), then a "Recently Added" grid of `AlbumCard`s below, two per row on iPhone, four on iPad.
- Artists: alphabetical `List` of `ArtistCircle` rows with a section index; Artist page: hero with the artist image blurred as a header, "Play" and "Shuffle" glass pills, Albums grid, Top Songs (by play count), Appears On (albums where the artist is not album artist), Similar Artists (`/Artists/{id}/Similar` if the SDK exposes it; otherwise omit).
- Albums: grid with sort menu (Title, Artist, Year, Recently Added) and a filter for Favourites; Album page: cover, title, artist (tappable), year · genre · track count · duration, "Play" and "Shuffle" pills, `TrackRow` list with disc headers for multi-disc, "More by [artist]" row.
- Songs: paged list with the section index, sort by Title, Artist, Recently Added, Play Count.
- Playlists: grid of `PlaylistCard`s, New Playlist in the toolbar; Playlist page: header with collage, Play and Shuffle, editable track list (reorder, remove), rename and delete in the menu.
- Genres: list; Genre page: albums grid.
- Everything plays through `AudioQueueEngine` with the standard semantics: tapping a track in an album plays that album from that track; "Play" plays from the top; "Shuffle" shuffles the set.

### 6.5 Playlists and favourites

- Add to Playlist sheet: existing playlists with their collages, "New Playlist" at the top, multi-add from album and artist pages ("Add album to playlist").
- Favourite from any row's menu, the Now Playing heart, and the lock screen Like command.

### 6.6 Search, Siri and Spotlight

- Search tab gains Artists, Albums and Songs groups when music is present; results play inline with a mini play button on song rows.
- App Intents: "Play [album] in Serafin", "Play [artist]", "Shuffle my music", "Play playlist [name]". Spotlight indexes albums and playlists with artwork.

### 6.7 Downloads for music

Reuse Phase 5: tracks and albums download through `/Items/{id}/Download` (original files; AVPlayer handles the common formats) or through `/Audio/{id}/universal` with `transcodingProtocol=http` as an AAC file when the format is unsupported. Album and playlist download buttons. Downloaded tracks are badged in rows and play offline through the same engine.

### 6.8 Settings › Music

Streaming quality on Wi-Fi and cellular (Original, High 320 kbps AAC, Normal 192 kbps), crossfade off (not offered in 1.3), gapless on, show lyrics on lock screen if the API allows, download quality.

### 6.9 CarPlay (after the entitlement)

- Entitlement `com.apple.developer.carplay-audio` in the entitlements file; `UIApplicationSceneManifest` gains a `CPTemplateApplicationSceneSessionRoleApplication` scene with a `CarPlaySceneDelegate`.
- `CPTabBarTemplate` with four `CPListTemplate`s: Recently Added, Artists, Albums, Playlists. Rows are `CPListItem`s with artwork at the template's size, titles and subtitles; drilling into an artist or album lists its tracks; tapping plays through `AudioQueueEngine` and pushes `CPNowPlayingTemplate.shared`, which gets shuffle and repeat buttons.
- Siri in the car uses the same App Intents.
- Loading states use `CPListTemplate`'s built-in loading; errors use `CPAlertTemplate` only for sign-in-required.
- Test with the CarPlay Simulator in Xcode's Additional Tools and on at least one real head unit.

### 6.10 Performance budgets

Music root opens from cache in under 300 ms with a 20,000-track library; album grid scrolls at 120 Hz; track start under 500 ms on Wi-Fi for direct play; mini player updates artwork within one frame of a track change; memory under 250 MB after an hour of playback with the app in the background.

### Gate 6

On the owner's server: play an album gapless, shuffle an artist, build and reorder a playlist, favourite from the lock screen, lyrics scroll in sync, interruption by a phone call resumes correctly, headphone disconnect pauses, AirPlay to a speaker works, a day of background playback does not exceed the memory budget. Downloads of one album play in Airplane Mode. On the demo server: every screen has real data for screenshots. CarPlay gate is separate: all four tabs and Now Playing verified in the simulator and on a head unit.

---

## 7. Demo server additions (in `deploy/demo-server/`)

Add before each corresponding release is submitted.

- **Live TV loop channel (for 1.1):** a `livetv/` folder with a `docker-compose.override.yml` adding an `ffmpeg` service that loops Big Buck Bunny into HLS (`-re -stream_loop -1 -i bbb.mp4 -c copy -f hls -hls_time 6 -hls_list_size 10 -hls_flags delete_segments+omit_endlist` into a shared volume) and an internal Caddy site on port 8080 that file-serves it; a `demo.m3u` with one entry named "Serafin Demo 1" pointing at `http://caddy:8080/livetv/demo1/index.m3u8` with a `tvg-logo`; a `make-xmltv.sh` that writes 48 hours of hour-long "Serafin Demo Hour" programs with descriptions; README steps to add the M3U tuner and the XMLTV guide in Jellyfin's Live TV dashboard and to set a recording path. A second channel looping Sintel is optional.
- **Music library (for 1.3):** `fetch-music.sh` downloading the Tears of Steel soundtrack from `download.blender.org/demo/movies/ToS/Tears-Of-Steel-OST/` and a curated list of Free Music Archive CC BY albums (URLs kept in a text file with their licence lines), tagging with embedded metadata, placed under `media/Music/<Artist>/<Album>/`; README steps to add the Music library.
- **Permissions (for 1.2):** enable "Allow media downloading" for `reviewer` and `screenshots`.
- **Review notes:** append to the existing text, per release: how to find Live TV (the demo channel), how to download Big Buck Bunny and test offline, how to find Music. Live TV also gets a 60-second screen recording hosted at `getserafin.app/review/livetv.mp4` for the reviewer.

---

## 8. App Store per release

- "What's New" is three lines, benefits first ("Watch Live TV from your Jellyfin tuners"), never internal names.
- Listing wording: "Live TV and DVR from your Jellyfin server's tuners, such as HDHomeRun." Live TV is described only in terms of tuners. Internet television playlists are never named or suggested anywhere Serafin publishes, including the GitHub README and release notes.
- Screenshots refreshed on the demo server for every release that adds a tab.
- Privacy label stays "Data Not Collected"; CarPlay adds no data collection.
- Each release goes to TestFlight first for at least one week with the r/jellyfin beta group.

---

## 9. Order of work

1. Phase 3.5, then finish Phase 3 and submit 1.0.
2. Phase 4 behind the adaptive tab; TestFlight; 1.1.
3. Phase 5; TestFlight; 1.2.
4. Phase 6.0–6.8; TestFlight; 1.3. Then 6.9 when the entitlement arrives.

Nothing from a later phase is scaffolded early. A tab the user cannot use is worse than no tab.
