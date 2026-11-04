# Serafin — implementation plan, part 3: from 1.0 to the best Jellyfin client on iOS

Serafin 1.0 is on the App Store. This document sets the roadmap from here: what ships in each release, in what order, and why. It supersedes the release order in `docs/PLAN-2.md` (Downloads shipped first), but the task content of PLAN-2's Phase 4 (Live TV) and Phase 6 (Music) still applies and is referenced rather than repeated. `AGENTS.md` still governs every task: one task per branch and PR, the definition of done, tests for Core and Playback, previews for Design, no new dependency without the owner's approval, no secrets or real library titles in the repo, and a gate the owner passes on a physical device before each release.

## 0. Where we stand and what the research says

Serafin 1.0 already covers the two complaints that dominate reviews of the official Jellyfin apps on iOS: Swiftfin has no offline downloads and basic lock-screen controls; Serafin has both (downloads in 1.1). What the other clients are chosen for, and Serafin still lacks, is a short list:

| Users ask for | Who has it today | Serafin |
| --- | --- | --- |
| Trickplay thumbnails while scrubbing, online and offline | Streamyfin, Infuse, Swiftfin | missing |
| Automatic switching between a server's local and remote address | Streamyfin | missing |
| Jellyseerr / Seerr requests | Streamyfin | missing |
| Grouping multiple versions of an episode (Jellyfin 12.0 adds it server-side) | nobody yet | missing |
| Translations | Swiftfin (Weblate) | English only |
| Music with CarPlay, Live TV, SyncPlay, widgets, remote control of other sessions | JellyPlay on Android has all of it; no iOS client does | planned |
| Dolby Vision profile 7, DTS and TrueHD decoded on device, ASS subtitle rendering | Infuse (its whole reason to be paid) | server-side only |
| A stable, fully featured open-source Apple TV client | nobody; Swiftfin is unstable for many, Infuse costs money | missing |

The strategy that follows from this: ship the small, visible gaps first so the first scroll through Serafin looks more complete than Swiftfin; then the cheap big feature everyone cites (Seerr) together with translations to widen the audience; then Music with CarPlay, which no iOS client has; then Live TV; then Apple TV as the 2.0 headline, which is the single largest open opportunity in this ecosystem. Everything is still gated by the four principles in `AGENTS.md`: pretty, native, simple, secure. A feature that cannot be finished to that bar in its release is cut from the release, not shipped half-done.

Release map:

| Release | Contents | Gate |
| --- | --- | --- |
| 1.1 | Downloads (built) + the polish pack: trickplay, server address switching, Jellyfin 12.0 compatibility, version picker | Gate 7 |
| 1.2 | Seerr requests + localization | Gate 8 |
| 1.3 | Music with CarPlay (PLAN-2 Phase 6, entitlement already granted) | Gate 6 |
| 1.4 | Live TV (PLAN-2 Phase 4) | Gate 4 |
| 2.0 | Apple TV app | Gate 10 |
| 2.x | SyncPlay, compatibility player, Play On, widgets, subtitle search, metadata editor, Mac app | per task |

Jellyfin endpoints below are REST paths; confirm each generated `Paths.*` name and model in the SDK checkout before use. Target server is Jellyfin 10.10 or newer, and 12.0 from 1.1 on. Apple APIs must be confirmed against the iOS 26 SDK headers; never invent a modifier.

---

## Release 1.1 — Downloads plus the polish pack

Downloads are built and tested; merge them first (task 7.0), then the four polish tasks. Target: TestFlight within two weeks of 1.0 going live, App Store a week later.

### 7.0 Merge downloads

Merge the downloads branch as planned in PLAN-2 Phase 5. Before merging, re-run Gate 5 on the current main (a movie as original, an MKV episode as remux, a season; Airplane Mode playback; progress sync when back online; kill-and-resume mid-download; storage numbers match iOS Settings within 5%). Demo server: App Review and the App Store screenshots both use the one `reviewer` account (there is no separate `screenshots` account), and "Allow media downloading" is already enabled for it. Add the download steps to the App Review notes (PLAN-2 section 7).

### 7.1 Trickplay thumbnails

Goal: scrubbing shows a thumbnail of the frame under the finger, the way the Apple TV app and Infuse do, online and for downloads.

Steps:

1. Request `Trickplay` in the item fields (`Fields=Trickplay`) for playable items. The DTO carries a dictionary keyed by media source id, then by tile width, each a `TrickplayInfo` (width, height, tileWidth, tileHeight, thumbnailCount, interval in ms, bandwidth). Confirm the exact SDK model name.
2. `TrickplayRepository` in Core: picks the best width for the display (the largest at or below 320 pt × scale on iPhone, 480 on iPad), builds tile URLs `GET /Videos/{itemId}/Trickplay/{width}/{index}.jpg?mediaSourceId=…` (confirm path in the SDK), and resolves a position to (tile index, column, row) from `interval`, `tileWidth`, `tileHeight`. Pure function, tested with two fixtures (a 10×10 tile layout and a 5×5 one).
3. Tiles load through the shared image pipeline (header auth, disk cache). Prefetch the tile for the current position and its neighbours while scrubbing; never fetch all tiles up front.
4. `ScrubberPreview` in Design: a 16:9 glass-framed thumbnail (radius 12) that floats above the scrubber knob, clamped to the screen edges, showing the time underneath in `caption`. Appears on drag start with a spring, tracks the knob, dismisses on release. When trickplay is absent for the item, the preview is the time label only, so the gesture feels the same. Reduce Motion: fade only. VoiceOver: scrubbing announces the time; the preview image is decorative.
5. Chapter marks: if the item has chapters, draw thin tick marks on the scrubber track at chapter starts and show the chapter name in the preview when the knob is within a chapter.
6. Offline: when a download is created, fetch and store the tiles for the chosen width next to the media file (bounded at 20 MB per item; skip if larger). The offline player reads them from disk through the same `TrickplayRepository` abstraction.
7. Performance: the preview must update within one frame of knob movement on an iPhone 15; decode tiles once and cache the cropped `CGImage` per index for the session.

Acceptance: scrubbing a movie with trickplay enabled on the server shows thumbnails that match the frame; a downloaded episode shows them in Airplane Mode; an item without trickplay scrubs exactly as before. Screen recording.

### 7.2 Server address switching

Goal: a server reachable at a local address at home and a public address elsewhere is one server in Serafin, and the app picks the right address without the user noticing.

Steps:

1. Identity: a server is identified by the `Id` from `GET /System/Info/Public`, never by its address. `ServerStore` keys servers by that id; tokens in `SessionStore` are keyed by server id + user id, so both addresses share one sign-in. Migrate existing records: on first launch after update, fetch public info for each stored address and merge records with the same id, keeping both addresses.
2. `ServerRecord` gains `addresses: [ServerAddress]` (ordered, at most four) with a kind for each: `.local` (private range, `.local`, Tailscale 100.64/10) or `.remote`, derived by the existing `PrivateNetwork.isPrivate`. The public info's `LocalAddress` is added automatically as a local candidate when it differs from what the user typed and resolves.
3. `AddressResolver` actor: on connect, and whenever `NWPathMonitor` reports a path change, race the candidates in order (local first on Wi-Fi or wired, remote first on cellular) with a 2-second timeout each against `GET /System/Info/Public`, accept the first whose `Id` matches, and remember the winner per network (keyed by the Wi-Fi SSID when available, else by interface type). A later launch tries the remembered winner first.
4. Never switch addresses during active playback or an in-flight download; queue the switch until playback stops. Image URLs and stream URLs are built from the current address at request time, never cached with an address baked in (audit `ImageURLs` and `PlaybackNegotiator` for this).
5. Settings › Accounts › server: show each address with its kind and a check by the one in use ("Connected via home network" / "Connected via remote address"), Add Address, Remove Address, and a Test button that reports which addresses respond.
6. Add Server flow: after a successful connection, if public info's `LocalAddress` differs from the typed address, offer "Also use 192.168.1.10:8096 at home?" as a one-tap addition.
7. Errors: when no address responds, the existing offline Home behaviour applies, and the banner names the server, not an address.

Tests: resolver ordering on Wi-Fi vs cellular against a stubbed transport; record migration from single-address to multi-address; no address switch while a playback session is active.

Acceptance: with the owner's server reachable at both a LAN address and a public hostname, the app connects at home via the LAN address, keeps working after switching to cellular without re-signing in, and shows the right "Connected via" line in Settings.

### 7.3 Jellyfin 12.0 compatibility

Jellyfin 12.0 turns off deprecated authentication methods by default and adds multiple versions per episode. The API is otherwise frozen until 13.0, so this is the one compatibility pass needed for a while.

Steps:

1. Add a `jellyfin/jellyfin:unstable` service to `deploy/demo-server/` as an optional override (`docker-compose.12.yml`, separate config and ports, never exposed through Caddy) so the owner can run a 12.0 instance next to the demo server. Do not upgrade the demo server itself until 12.0 is stable and no review is in progress.
2. Audit every request Serafin makes for how it authenticates: the SDK's `Authorization` header for API calls, the query parameter on stream and trickplay URLs that AVPlayer fetches without headers, image requests, Quick Connect, and the logout call. Run the full app against the 12.0 instance with deprecated auth disabled and list what fails. Fix each in the SDK configuration or in Core; where a stream URL parameter is no longer accepted, find the supported form in the 12.0 API docs and switch to it. Record the findings in `docs/COMPATIBILITY.md` with the server versions tested.
3. Minimum server version stays 10.10; the version check's error text gains the tested range.
4. CI: a nightly job that spins up `jellyfin/jellyfin:unstable`, seeds it with the demo media via the existing scripts, and runs the Core integration tests against it, so a breaking server change is caught before users upgrade.

Acceptance: sign-in (password and Quick Connect), browsing, images, direct play, transcoded play, trickplay, downloads and sign-out all work against 12.0 with deprecated auth disabled, and against 10.10 unchanged.

### 7.4 Version picker

Goal: an item with more than one media source (a 4K and a 1080p movie today; episodes too from 12.0) shows as one item with a version choice, never as duplicates.

Steps:

1. Detail page: when `mediaSources.count > 1`, the Format section becomes a version list, one row per source with its name (`mediaSources[].name`, else derived "4K · HEVC · Dolby Vision · Atmos" from the streams), badges per the badge spec, and size. A check marks the version that will play. The Play pill plays the checked version.
2. Default choice: the user's last choice for that item if any; else the version whose resolution best matches the device and the current quality cap (prefer direct play over transcode); remember per item on this device.
3. Player: the Audio and Subtitles sheet gains a Version section with the same rows; switching re-negotiates at the same position.
4. Downloads: the download menu asks which version when more than one exists, with sizes.
5. Episodes under 12.0: confirm the SDK exposes the additional sources on episode DTOs and that the season's episode list returns one entry per episode; if the server still returns duplicates for a user without the merge applied, group by `indexNumber` client-side and treat the extras as versions.

Tests: default-choice logic with three fixtures (4K DV + 1080p on a device without DV; same on a device with DV; two 1080p sources with different audio).

### 7.5 Adaptive quality (stretch goal for 1.1; otherwise first in 1.2)

Goal: a playback mode that starts on the best option (direct play when possible) and, when the connection can't sustain it, re-negotiates to a lower server bitrate at the current position, then climbs back up when conditions recover, with no user action. This replaces the fixed Wi-Fi and cellular caps as the default behaviour.

Steps:

1. Settings › Playback › Quality mode: **Adaptive** (default), **Fixed** (today's behaviour with the existing Wi-Fi and cellular caps), **Direct Play Only** (never transcode; show the error if the file can't play). Under Adaptive, the existing caps become the ceiling per network, labelled "Maximum quality on Wi-Fi / Cellular." The setting stays per server, as today.
2. Startup estimate: before the first PlaybackInfo on a remote address, run a 2-second bandwidth probe against `GET /Playback/BitrateTest?size=` (confirm the path and the size parameter in the SDK; about 3 MB, abort at 2 s) and cache the result for 10 minutes per network. The initial bitrate is 0.8 × measured, bounded by the ceiling; if the measurement exceeds the item's bitrate by 1.5×, start with direct play. On a local address, skip the probe and start with direct play.
3. `AdaptiveQualityController` in Playback observes `AVPlayerItem` access-log events (`observedBitrate`, `indicatedBitrate`, `numberOfStalls`, `durationWatched`), `isPlaybackLikelyToKeepUp`, and the buffered-ahead duration from `loadedTimeRanges`.
   - Downgrade when any of: two stalls within 60 s; buffered-ahead below 3 s for more than 5 s while playing; observed bitrate under 1.2× the current stream's bitrate for 20 s. The target is the next step down the ladder 40, 20, 12, 8, 4, 2 Mbps below 0.8 × observed, never above the ceiling.
   - Upgrade when the observed bitrate has exceeded 1.5× the next step's bitrate for 90 s with no stalls, one step at a time; back to direct play only when it exceeds 1.5× the file's bitrate.
   - Cooldowns: no change within 30 s of the previous one; after a second downgrade within 5 minutes, hold the level for 10 minutes.
   - Never change quality during the last 2 minutes of an item, during Picture in Picture transitions, or while the user is scrubbing.
   - Log every decision with its inputs at `.debug`.
4. Switching reuses the existing track-switch path: report progress, negotiate with the new `maxStreamingBitrate`, swap the `AVPlayerItem` at the same position with the same audio and subtitle selection, resume, report start. A brief glass toast ("Adjusting quality for your connection") shows on a downgrade only, never on an upgrade; the play-method indicator in the Audio and Subtitles sheet updates.
5. Downloads and Live TV are out of scope.

Tests: the controller is a pure state machine over a stream of synthetic observations, with fixture sequences for a clean connection (no change), a sudden drop (one downgrade, then hold), a flaky connection (downgrade, cooldown respected, no flapping) and a recovery (stepwise upgrades back to direct play); plus the ladder-selection function and the probe result bounding.

Acceptance: on cellular with the owner throttling the connection (Network Link Conditioner or a weak-signal spot), a 4K movie starts, downgrades within 30 s of the throttle, plays through without a stall, and returns to direct play within two minutes of the throttle lifting; the same movie on home Wi-Fi never leaves direct play. Screen recording with the play-method indicator visible.

### Gate 7

On the owner's phone and iPad: trickplay thumbnails while scrubbing a movie and a downloaded episode; address switching between home Wi-Fi and cellular with no re-sign-in; a 12.0 instance passes the 7.3 checklist; a multi-version movie plays the expected version and the picker switches it. Then TestFlight for at least a week with the r/jellyfin group, screenshots unchanged (no new tab), App Store "What's New" in three lines, benefits first.

---

## Release 1.2 — Seerr requests and localization

### 8.0 Seerr preconditions and App Store posture

- Serafin talks to Jellyseerr / Seerr only when the user connects one in Settings; with none connected the app is identical to 1.1. Nothing is scaffolded in the UI until a server is connected.
- Listing wording, everywhere Serafin publishes: "Request new titles from your server's administrator through Jellyseerr or Seerr." Never "download," never "get," never any word that implies where a file would come from. The demo server has no Seerr; the App Review notes say the feature is dormant without one and describe what it does in one sentence. No Seerr screens in the App Store screenshots.
- Seerr's API is documented at `<seerr>/api-docs` (OpenAPI). Confirm every path and field there before use; Jellyseerr and Seerr are compatible for the endpoints used here.
- A user's Jellyfin password is sent once to Seerr's Jellyfin sign-in endpoint and never stored, consistent with the security rules; only Seerr's session cookie is kept, in the Keychain, keyed by Seerr server + user.

### 8.1 Core: `SeerrClient` and `SeerrRepository`

- `SeerrClient`: base URL, session cookie storage via `SecretStore`, a `URLSession` with the same pinning delegate as Jellyfin, and the same HTTP policy (HTTPS by default, HTTP only on private addresses after the warning).
- Sign-in: `POST /api/v1/auth/jellyfin` with the Jellyfin username and password (the fields Seerr expects; confirm in the spec); on success keep the `connect.sid` cookie. `GET /api/v1/auth/me` to read the user's permissions (request, auto-approve, manage requests) and `GET /api/v1/settings/public` for server capabilities.
- Discovery: `GET /api/v1/discover/trending`, `/discover/movies`, `/discover/tv`, `/discover/movies/upcoming`, `/discover/tv/upcoming`, `GET /api/v1/search?query=`. Results carry a `mediaInfo` with a status (unknown, pending, processing, partially available, available) and, when available, the Jellyfin item id, which is how a result links back into Serafin's own library.
- Details: `GET /api/v1/movie/{tmdbId}`, `GET /api/v1/tv/{tmdbId}` (seasons with per-season availability), `GET /api/v1/person/{id}`.
- Requests: `POST /api/v1/request` with `mediaType`, `mediaId` (TMDB id), `seasons` for TV (specific seasons or all), `is4k` when the server offers 4K; `GET /api/v1/request?filter=…&take=…` for the user's requests; `DELETE /api/v1/request/{id}`; `POST /api/v1/request/{id}/approve` and `/decline` for users with manage permission.
- Artwork: TMDB image paths from the responses, built with the TMDB image base and sized (`w342` posters, `w780` backdrops); loaded through the shared pipeline without the Jellyfin auth header.

Tests: decoding fixtures for discover, search, movie, tv and request lists; status mapping; cookie persistence and clearing on sign-out.

### 8.2 Design: request components

- `AvailabilityBadge`: capsule in the badge style: Available (green dot, opens in Serafin), Requested, Pending Approval, Processing, Partially Available (TV), Not Requested (no badge, the Request button carries the affordance).
- `RequestButton`: a glass pill: "Request" → confirmation sheet → "Requested" (disabled, with a checkmark) → for TV a season picker sheet (`.medium`) with per-season availability and "All Seasons". Admins see "Approve" / "Decline" on pending items in the Requests screen.
- `DiscoverCard`: the existing `PosterCard` with an `AvailabilityBadge` overlay bottom-leading; TMDB artwork.
- `RequestRow`: poster, title, requested date, status, requester (admins), swipe to cancel own pending requests.

### 8.3 Screens

- Settings › Accounts › server › "Requests (Jellyseerr)": Connect with address field, sign-in with the Jellyfin account, test, disconnect. Show the connected Seerr user and permissions.
- Discover: when Seerr is connected, Search gains a "Not in your library" group beneath the library results, and a "Discover" row set appears at the bottom of Home (Trending, Popular Movies, Popular Shows, Coming Soon), each a `MediaRow` of `DiscoverCard`s with a header that opens a grid. No new tab; Seerr is an extension of Search and Home, which keeps the app simple for users without it.
- Title page for an item not in the library: hero from the TMDB backdrop, title, year, runtime, overview, genres, cast row, and the `RequestButton`; when the item becomes available it deep-links to the Jellyfin item page. An item that is in the library opens the normal Jellyfin page, with its `AvailabilityBadge` omitted.
- Requests screen: from the profile menu and Settings: My Requests (Pending, Approved, Available), and for managers an All Requests segment with approve/decline. Pull to refresh; a `ContentUnavailableView` when empty.
- Errors: Seerr unreachable (requests UI hides, Home rows hide, a one-line notice in Settings), session expired (re-sign-in prompt), request quota exceeded (Seerr returns the limit; show it).

### 8.4 Localization

Goal: Serafin ships in the languages the Jellyfin community actually uses, with translations maintained by the community, not by machine.

Steps:

1. String audit: every user-facing string goes through `String(localized:)` with a comment for translators; plurals use inflection or `.stringsdict`-equivalent catalog entries; dates, durations and file sizes use `Date.FormatStyle`, `Duration.formatted` and `ByteCountFormatter`; no string concatenation of fragments. Run the app with the pseudo-language (Xcode "Double-Length Pseudolanguage" and "Right-to-Left Pseudolanguage") and fix every clipped or mirrored layout. Accessibility labels and App Intents phrases are strings too.
2. Translation platform: register the project on a hosted translation service that is free for open source (Hosted Weblate or Crowdin), connected to the repo so `Localizable.xcstrings` round-trips automatically. Add `TRANSLATING.md` with the link and a "Help translate Serafin" row in Settings › About.
3. First languages, by Jellyfin community size: German, French, Spanish, Dutch, Portuguese (Brazil), Italian, Simplified Chinese, Russian, Polish, Swedish. Machine-drafted strings may seed a language on the platform, but a language ships in the app only after a native speaker has reviewed it there; until then it stays unlisted in `CFBundleLocalizations`.
4. App Store: localized name stays "Serafin for Jellyfin"; localized subtitle, description and "What's New" for each shipped language; screenshots stay English until a language has a reviewer willing to retake them.
5. Intents and Siri: App Intents titles and parameter summaries localized; Siri phrases per language.

Acceptance: the pseudo-language run shows no clipped layouts on iPhone or iPad; at least three languages reviewed and shipped; switching the device language changes every string, including Settings, errors and intent phrases.

### Gate 8

Against the owner's Seerr: sign in, search for a title not in the library, request it, see it move through Pending → Processing → Available, and open it in Serafin when available; cancel a pending request; a manager approves another user's request. App Store wording reviewed by the owner against section 8.0 before submission. Localization acceptance met. Then TestFlight for a week, and a r/jellyfin post for this release ("the catch-up release": downloads, trickplay, address switching, Seerr, translations).

---

## Release 1.3 — Music with CarPlay

Build PLAN-2 Phase 6 as written (6.0 through 6.10), with these amendments:

- 6.0: the CarPlay Audio entitlement was granted on 7 Oct 2026 and is enabled on the App ID. Task 6.9 can start as soon as the music tab passes its own gate; add the entitlement key to `project.yml` in 6.9, not before.
- 6.0: the demo server gets a Music library of CC-licensed albums (Tears of Steel soundtrack, Free Music Archive CC BY) via `fetch-music.sh`, tagged with embedded metadata, before screenshots; the Music tab appears in the App Store screenshots for 1.3.
- 6.2: lyrics come from `GET /Audio/{id}/Lyrics`, which Jellyfin serves from embedded or sidecar lyrics and from the LrcLib-backed lyrics plugin when the admin installs it; the app does not call any lyrics service itself (no new network destinations, per the privacy posture).
- 6.3: the mini player returns as `tabViewBottomAccessory`, docked Apple Music style with no close button, for music only; video stays on Picture in Picture.
- Downloads for music (6.7) reuse the 1.1 download manager unchanged.

Gate 6 as written in PLAN-2, plus the CarPlay gate on the CarPlay Simulator and at least one real head unit.

---

## Release 1.4 — Live TV

Build PLAN-2 Phase 4 as written (4.0 through 4.9), with these amendments:

- The demo server gets the loop channel from PLAN-2 section 7 before screenshots; the 60-second review recording is hosted at `getserafin.app/review/livetv.mp4`.
- Wording stays "Live TV and DVR from your Jellyfin server's tuners, such as HDHomeRun"; the word IPTV never appears anywhere Serafin publishes.
- Jellyfin 12.0 fixed EPG issues with Schedules Direct; test guide data against both 10.11 and 12.0.
- Trickplay (7.1) does not apply to live streams; the scrubber preview shows the time only.

Gate 4 as written.

---

## Release 2.0 — Apple TV

Goal: the stable, fully featured, open-source Apple TV client the community keeps asking for, with the same design language as the iPhone app.

### 10.0 Preconditions

- The owner buys an Apple TV 4K (3rd generation or newer) and enrols it as a development device; tvOS 26 or newer.
- Packages add `.tvOS(.v26)` to `platforms`; `SerafinCore` and `SerafinPlayback` compile for tvOS unchanged (UIKit use is already fenced); `SerafinDesign` and `SerafinFeatures` gain tvOS variants where the interaction model differs (focus instead of touch).
- A new app target `SerafinTV` in `project.yml`, bundle id `app.getserafin.serafin.tv`, sharing the App Store record as a universal purchase so the listing stays one app.

### 10.1 Design for the focus engine

- Every card, button and row becomes focusable with the system focus effect (`.focusable`, `.focusEffect`, lift and parallax from the system; no custom focus rings). Rows use the system `ScrollView` with `.focusSection` so focus moves predictably between rows.
- Hero on tvOS: full-bleed backdrop with the logo and a single focused Play button; the Home layout follows the Apple TV app's tvOS Watch Now.
- Player: the system transport bar from `AVPlayerViewController` on tvOS (it is the native experience there: swipe to scrub with trickplay previews, info panel for audio and subtitles, chapters). Serafin adds its Skip Intro pill and Next Episode card as overlays through the controller's custom overlay API; no custom transport bar on tvOS.
- Siri Remote gestures: tap to show controls, swipe for scrubbing, Menu to dismiss; respect the system's own handling to avoid the "catches people out" complaint about Swiftfin.
- Text input is minimal: Quick Connect first on tvOS (the right default there), with the on-screen keyboard as fallback; Who's Watching profiles with optional PIN.
- Top Shelf extension: Continue Watching and Next Up as the app's top shelf content.

### 10.2 Playback on tvOS

- AVPlayer on tvOS supports 4K, HDR10, Dolby Vision (profiles 5 and 8; profile 7 goes through the server as on iOS) and Dolby Atmos passthrough for EAC3; the device profile gains the tvOS capabilities (`AVPlayer.eligibleForHDRPlayback`, display criteria matching for frame rate and dynamic range, which tvOS exposes through `AVDisplayCriteria`; confirm APIs).
- Match frame rate and dynamic range to content when the user's tvOS setting allows it.
- Everything else (negotiation, progress reporting, segments, next episode, Now Playing) is the shared Playback package.

### 10.3 Scope for 2.0

Home, Library, Search, movie and show pages, player, settings, multiple servers and users, Live TV and Music if they have shipped on iOS by then (same packages). Downloads do not apply to tvOS. Seerr requests apply.

### Gate 10

On the owner's Apple TV: sign in with Quick Connect, browse, play a 4K HDR movie with frame-rate matching, play an episode with Skip Intro and Next Episode, switch audio and subtitles from the system info panel, resume from the phone's progress, and navigate every screen with the Siri Remote without a focus trap. tvOS screenshots on the demo server. TestFlight for two weeks with the r/jellyfin group, since tvOS testers find different bugs.

---

## 2.x — after Apple TV, in rough priority

Each is one phase in a future plan document; listed here so the architecture keeps room for them.

- **SyncPlay (watch together):** Jellyfin's SyncPlay API (`/SyncPlay/List`, `/SyncPlay/New`, `/SyncPlay/Join`, `/SyncPlay/Leave`, playback commands) plus the server WebSocket for group state; AVPlayer rate and seek nudges to keep within the group's tolerance; a glass "Watching with 3 people" chip in the player. Requires the WebSocket client in Core, which also enables live library updates.
- **Compatibility player:** libmpv via the MPVKit package (new dependency; owner approval), as an opt-in per server or per item for files the server cannot serve well: Dolby Vision profile 7, DTS and TrueHD decoded on device, ASS/SSA subtitle rendering with styling. Costs PiP, AirPlay and some Now Playing behaviours while in use, which the UI must say plainly. This is the only path to the users who pay for Infuse.
- **Play On (remote control):** `GET /Sessions` to list other sessions for the user (the TV, the browser), `POST /Sessions/{id}/Playing` and `/Command` to send play, pause, seek and "play this here"; a route-picker-style sheet next to AirPlay. Serafin can also be a target, which needs the WebSocket client.
- **Widgets:** WidgetKit Continue Watching and Next Up (small, medium, lock screen), fed from the cached Home snapshot through an App Group; a tap deep-links to the item or plays it through the intent. Honour the app lock (widgets show nothing when locked).
- **Subtitle search:** `GET /Items/{id}/RemoteSearch/Subtitles/{language}` and the download endpoint, available when the admin has the OpenSubtitles plugin; a "Find Subtitles" row in the Audio and Subtitles sheet for users with the permission.
- **Metadata and artwork editor:** for admins, from the More menu: edit title, overview, dates, genres; choose artwork from the providers via `GET /Items/{id}/RemoteImages`; identify via `POST /Items/RemoteSearch/Movie` and `/Series`. Keeps the web client out of the loop for common fixes.
- **Mac app:** a native macOS target on the same packages once tvOS has proven the split; menu bar commands, keyboard-first navigation, window sizing, a sidebar. Not Catalyst, not "Designed for iPad."
- **Server dashboard for admins:** active sessions, scheduled tasks, server health, read-only at first.

---

## Ruled out, and why

| Feature | Why not |
| --- | --- |
| Chromecast / Google Cast | Needs Google's closed Cast SDK with its own telemetry, which contradicts the "Data Not Collected" label and the no-third-party-SDK rule; AirPlay covers the Apple audience. |
| Radarr / Sonarr queue management, indexers, download clients | The feature that gets apps removed from the App Store. Seerr requests are the safe boundary: a request to a server admin, nothing more. |
| In-app updates, alternative distribution channels | Not permitted on the App Store; TestFlight is the beta channel. |
| Analytics, ads, crash SDKs | Ruled out for good under the privacy rules. Apple's opt-in crash reports only. |
| watchOS app | No clear use; revisit only if users describe one. |
| Books and photos | Low demand on a phone; the web client serves them. Revisit if requests accumulate. |
| Custom themes beyond the accent colour, OLED toggles | Apple's system appearance is the design; glass handles both modes. |

---

## Every release: process

- **Versioning:** 1.1.0, 1.2.0 and so on; builds increment on every upload. Tag releases in git; the GitHub release notes are the App Store "What's New" plus a link to the changelog.
- **Beta:** every release goes to TestFlight for at least one week with the public r/jellyfin group (two weeks for 2.0). `beta-blocker` label for crashes and security; a release does not ship with one open.
- **App Store:** screenshots refreshed for any release that adds a tab (1.3, 1.4, 2.0); review notes updated per PLAN-2 section 7; privacy label stays Data Not Collected; "What's New" is three lines, benefits first, never internal names.
- **Demo server:** media additions land before the release's screenshots; the Jellyfin image stays pinned during any review window; upgrade to 12.0 only after 7.3 passes and no review is pending.
- **Listening loop:** GitHub issue templates (bug with device, iOS and server version; feature request with the problem it solves), GitHub Discussions for requests, a public roadmap as a GitHub Project board mirroring this document, App Store reviews read weekly, and the jellyfin.org client-list submission now that 1.0 is live. The roadmap order above is the default; a request that shows up repeatedly in reviews or issues can move a 2.x item forward, with the owner's call.
- **Gates:** every release ends with the owner on a physical device; nothing from a later release is scaffolded early. A tab the user cannot use is worse than no tab.

---

## Order of work

1. 7.0 merge downloads → 7.1 trickplay → 7.2 address switching → 7.3 Jellyfin 12.0 compatibility → 7.4 version picker → 7.5 adaptive quality (stretch; else first in 1.2) → Gate 7 → TestFlight → 1.1.
2. 8.1 Seerr Core → 8.2 components → 8.3 screens → 8.4 localization → Gate 8 → TestFlight → 1.2.
3. PLAN-2 Phase 6 with the amendments above → Gate 6 → CarPlay gate → 1.3.
4. PLAN-2 Phase 4 with the amendments above → Gate 4 → 1.4.
5. Phase 10 → Gate 10 → 2.0.
6. 2.x items as a new plan document, ordered by what users ask for.

## Coordinator prompt

> Read `docs/PLAN-3.md` completely; it supersedes the release order in `docs/PLAN-2.md` but not the task content of PLAN-2's Phases 4 and 6, which it references. `AGENTS.md` still applies in full. Start with task 7.0: re-run Gate 5's checklist on current main for the downloads branch, report the results, and stop for my merge approval. Then 7.1 through 7.4 in order, one PR each, with the five-line file plan first. Confirm every SDK path and model and every iOS 26 API against the checkout and headers before use; where the plan says "confirm," do that and record what you found in the PR. Do not start anything from Release 1.2 or later until I say Gate 7 passed. For 7.3, set up the 12.0 unstable override and tell me what to run; do not upgrade the demo server.
