# Serafin — implementation plan

Work the tasks in order. Each task is sized for one branch and one PR. A phase ends at its gate; do not start the next phase until the gate passes. `AGENTS.md` holds the rules that apply to every task and is not repeated here.

Phases:

- **0 Foundation** — scaffold, design system on mock data, app shell. Gate: every component looks App Store ready in previews.
- **1 Core** — real server, sign-in, home, library, detail, player. Gate: a movie and a TV episode play end to end on the owner's server.
- **2 Delight** — transitions, iPad, search, filters, Now Playing polish, app lock, accessibility, intents. Gate: the native-feel checklist passes on iPhone and iPad in light and dark.
- **3 Beta** — threat model, data-flow review, TestFlight. Gate: two weeks of beta with no open crash or security issue.

Jellyfin API references below use REST paths. The Swift SDK exposes each one as a `Paths.*` function and a matching `JellyfinAPI` model; confirm the generated name in `.build/checkouts/jellyfin-sdk-swift` before use. Target server version is Jellyfin 10.10 or newer.

---

## Phase 0 — Foundation

### 0.1 Repository scaffold

Goal: a buildable, testable, CI-checked skeleton with the four package targets and an app that launches to an empty tab bar.

Steps:

1. `project.yml` for XcodeGen: one target `Serafin` (iOS app, deployment target 26.0, bundle ID `app.getserafin.serafin`, display name `Serafin`, supports iPhone and iPad, portrait and landscape on iPad, portrait on iPhone except the player). Link the local package products `SerafinFeatures` and `SerafinDesign`. Info.plist keys: `NSLocalNetworkUsageDescription` ("Serafin looks for Jellyfin servers on your network."), `NSBonjourServices` with `_jellyfin._tcp` only if discovery uses Bonjour (Jellyfin discovery is UDP broadcast on port 7359, so this key is probably not needed; add only if the discovery implementation requires it), `UIBackgroundModes` = `audio`, `NSAppTransportSecurity` with `NSAllowsLocalNetworking` = true and nothing else, `ITSAppUsesNonExemptEncryption` = false.
2. `Packages/SerafinKit/Package.swift`: swift-tools-version 6.0, platforms `.iOS(.v26)`, `.macOS(.v26)`. Targets `SerafinCore`, `SerafinPlayback`, `SerafinDesign`, `SerafinFeatures` with the dependency graph from `AGENTS.md`. Dependencies: `jellyfin-sdk-swift` (latest tagged release, pin exact), `Nuke` (latest tagged release, pin exact). Test targets for Core, Playback and Design. Set `swiftLanguageModes: [.v6]` and `-strict-concurrency=complete` via `swiftSettings`.
3. `App/SerafinApp.swift`: `@main` App with a `WindowGroup` showing `RootView()` from Features. `RootView` is an empty `TabView` for now.
4. `.gitignore` (Xcode, SwiftPM `.build`, `*.xcodeproj`, `xcuserdata`, `.DS_Store`), `.swift-format` (4-space indent, 120 columns, ordered imports), `README.md` (one paragraph, build instructions, status badge), `LICENSE` (MIT, owner's name), `TRADEMARK.md` (the Serafin name and icon are not covered by the MIT licence; forks must use a different name and icon).
5. `.github/workflows/ci.yml`: on push and PR, macOS runner with Xcode 26 selected, `brew install xcodegen`, `xcodegen generate`, build for the iPhone 17 simulator, run `xcodebuild test`, run `swift format lint --recursive --strict App Packages`.

Acceptance:

- Fresh clone, `xcodegen generate`, build and test all succeed with zero warnings.
- CI is green on the PR.
- The app launches in the simulator to an empty tab bar with no crash.

### 0.2 Design tokens

Goal: the vocabulary every component uses, in `SerafinDesign`.

Steps:

1. `Theme`: semantic colours as `Color` extensions (`background`, `surface`, `textPrimary`, `textSecondary`, `accentFallback`) that resolve for light and dark from the asset catalog in the package's resources.
2. `Typography`: named text styles mapping to system Dynamic Type styles (`largeTitle`, `title`, `headline`, `body`, `caption`), no custom fonts.
3. `Spacing` scale (4, 8, 12, 16, 24, 32) and `Radius` scale (12, 16, 24, continuous).
4. `Motion`: `Animation.serafinSnappy` (`.spring(.snappy)`) and a `reduceMotion`-aware helper.
5. `ArtworkTint`: a function that takes a `CGImage` and returns a dominant `Color` suitable as a glass tint (average of the mid-saturation pixels, clamped to a brightness range so text stays legible). Pure function, unit tested with three generated images (red, dark blue, near-white).

Acceptance: a `TokensPreview` showing every token; `ArtworkTint` tests pass.

### 0.3 Mock fixtures

Goal: realistic, offline data for previews and tests, with no copyrighted material.

Steps:

1. `MockMedia` in `SerafinDesign`: value types `MediaCard` (id, title, year, kind movie/series/episode, runtime, progress 0...1, played, favourite, overview, series and season info for episodes). Twelve movies and four series with seasons and episodes, using public-domain titles only (Blender open films: Big Buck Bunny, Sintel, Tears of Steel, Elephants Dream, Cosmos Laundromat, Spring, Charge; plus archive.org public-domain features).
2. Artwork: generated in code, not shipped as files. `PlaceholderArt.poster(seed:)` and `.backdrop(seed:)` return deterministic gradients with a soft noise overlay, so previews look like real art without using any.
3. `MockLibrary` groups: Continue Watching (with progress), Next Up, Latest, and two library views (Movies, Shows).

Acceptance: previews render instantly offline; no image assets in the repo other than the app icon.

### 0.4 Components

Goal: the reusable pieces, each finished to the App Store bar before any networking exists.

Build, in this order, each with light, dark and AX5 previews and a VoiceOver label:

1. `PosterCard` — 2:3, continuous radius 12, title and year beneath, thin progress bar overlaid at the bottom edge, played check badge, press scale on touch, `.hoverEffect(.lift)`, `.contextMenu` slot.
2. `LandscapeCard` — 16:9 thumb, episode title, series and episode code ("S2 E4"), runtime, progress bar.
3. `HeroHeader` — full-bleed backdrop with a vertical fade into the background colour, optional logo image, title fallback, metadata line (year, runtime, rating), and a glass play pill (`.glassEffect(.regular.interactive())`) that reads "Play" or "Resume · 32 min left".
4. `GlassChip` — a selectable pill for filters and sort, inside a `GlassEffectContainer` when several appear together.
5. `PlayerControls` — static layout only in this task: play/pause, skip back and forward 10 s, scrubber with elapsed and remaining, tracks button, AirPlay button slot, PiP button slot, all on glass, grouped in one `GlassEffectContainer`.
6. `MiniPlayer` — the compact bar for `tabViewBottomAccessory`: thumb, title, play/pause, close.
7. `MediaRow` — a horizontally scrolling row with a header and a "See all" affordance, generic over card type.
8. `EmptyState`, `ErrorState`, `LoadingState` — designed, not defaulted.

Acceptance:

- The owner reviews a `ComponentGallery` preview and approves each component on looks alone.
- Every component passes Dynamic Type AX5 without truncating the title (titles may wrap to two lines, then truncate).
- Reduce Transparency renders every glass control as a plain material.

### 0.5 App shell

Goal: the navigation skeleton on mock data.

Steps:

1. `RootView`: `TabView` with `Tab("Home", systemImage: "house")`, `Tab("Library", systemImage: "square.grid.2x2")`, `Tab(role: .search)`, `Tab("Settings", systemImage: "gearshape")`. `.tabViewStyle(.sidebarAdaptable)`, `.tabBarMinimizeBehavior(.onScrollDown)`, `.tabViewBottomAccessory` showing `MiniPlayer` when a `PlaybackCoordinator` reports an active item (stub for now).
2. One `NavigationStack` per tab with a typed `Route` enum (`.item(id)`, `.library(id)`, `.season(id)`, `.person(id)` reserved).
3. `HomeView` with `MediaRow`s from `MockLibrary`; `LibraryView` with a `LazyVGrid` of `PosterCard`s and a `GlassChip` row for sort; `SearchView` with `searchable` and mock results; `SettingsView` with a static list.
4. `ItemDetailView` using `HeroHeader` and mock data; poster-to-detail uses `.navigationTransition(.zoom)` with `.matchedTransitionSource`.
5. `PlayerView` shell presented full screen with `PlayerControls` over a black placeholder.

Acceptance: the owner can tap through every screen on the simulator with mock data and the transitions, tab bar minimising and mini player behave like a shipping app. Rotation on iPad keeps the sidebar.

### Gate 0

Every component and screen looks App Store ready in previews and on the simulator, approved by the owner. Only then does Phase 1 start.

---

## Phase 1 — Core

### 1.1 Stores and identity (SerafinCore)

Steps:

1. `SecretStore` protocol (`get`, `set`, `delete` by key) with `KeychainSecretStore` (accessibility `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`, `kSecAttrSynchronizable` false) and `InMemorySecretStore` for tests.
2. `DeviceIdentity` actor: a UUID generated once and stored in the Keychain; client name `Serafin`; version from the bundle. Produces the SDK's authorization header values.
3. `ServerStore` actor: persisted list of servers (id, name, URL, last-used user id, pinned certificate fingerprint if any) in a JSON file under Application Support with file protection complete; no secrets in it.
4. `SessionStore` actor: access tokens keyed by `server id + user id` in the `SecretStore`; current session selection persisted as plain ids.
5. `ClientFactory`: builds a `JellyfinClient` for a server with the device identity and, when present, the token; installs the pinning `URLSessionDelegate` from 1.2.

Tests: Keychain store round trip (on simulator), in-memory store, device identity stability across instances, server store JSON round trip, session store token isolation between servers.

### 1.2 Connecting to a server

Steps:

1. `ServerAddress.parse(_:)`: accepts `host`, `host:port`, `scheme://host[:port][/path]`; when no scheme is given, defaults to `https` on 443 for a public host (most self-hosters use a reverse proxy) and `http` on 8096 for a private address; rejects anything that is not http or https. The connect step in 1.5 retries the Jellyfin defaults (8920 for https, 8096 for http) once if the first attempt fails. Pure function, exhaustively tested.
2. `PrivateNetwork.isPrivate(host:)`: RFC 1918 ranges, loopback, link-local, `.local`, bare hostnames without a dot. Tested.
3. HTTP policy: when the parsed scheme is `http` and the host is public, refuse with `SerafinError.insecureTransport`. When `http` and private, allow after the warning sheet in 1.5 is accepted once per server.
4. Certificate pinning: `PinningDelegate: URLSessionDelegate` that, on a TLS failure for a host with a stored pin, compares the leaf public key SHA-256 to the pin and accepts only on match. First-connection flow: fetch fails → show fingerprint → user pins → retry. Pins stored via `SecretStore`.
5. Public info: `GET /System/Info/Public` to confirm it is a Jellyfin server and read the name and version. Reject versions below 10.10 with a clear message.
6. Local discovery: UDP broadcast of `who is JellyfinServer?` to port 7359 and parse replies (use the SDK's `ServerDiscovery` if its API suffices; otherwise `NWConnection` with the local network permission prompt).

Tests: parser and private-range tests; pinning delegate tested with generated certificates; public info decoding from a fixture.

### 1.3 Sign-in

Steps:

1. Quick Connect, the default path: the SDK's `QuickConnect` helper. Show the code large, poll, and on success store the token. Handle "Quick Connect disabled on this server" by falling back to password login with a one-line explanation.
2. Password login: `JellyfinClient.signIn(username:password:)` (wraps `POST /Users/AuthenticateByName`). The password lives only in the text field's state and is cleared on submit.
3. Sign out: `POST /Sessions/Logout`, then delete the token and clear per-user caches.
4. Multiple servers and users: add server, add user to a server, switch, remove; the current selection drives the whole app through an `AppSession` observable in Features.

Tests: auth flows against a stubbed transport (success, wrong password, server down, Quick Connect disabled); sign-out removes the Keychain item.

### 1.4 Library data

Steps:

1. `LibraryRepository` (actor, in Core) with async functions, each backed by one endpoint:
   - `userViews()` → `GET /UserViews`
   - `resume(limit:)` → `GET /UserItems/Resume`
   - `nextUp(limit:)` → `GET /Shows/NextUp`
   - `latest(in view:, limit:)` → `GET /Items/Latest`
   - `items(in parent:, types:, sort:, order:, filters:, start:, limit:)` → `GET /Items` with `recursive` true, `fields` limited to what the cards need (`PrimaryImageAspectRatio`, `Overview`, `MediaSources` only on detail)
   - `item(id:)` → `GET /Items/{id}`
   - `seasons(series:)` → `GET /Shows/{id}/Seasons`; `episodes(series:season:)` → `GET /Shows/{id}/Episodes`
   - `similar(to:)` → `GET /Items/{id}/Similar`
   - `search(term:)` → `GET /Items` with `searchTerm`, grouped by type
   - `markPlayed(id:)`, `markUnplayed`, `setFavourite(id:,on:)` → `POST`/`DELETE /UserPlayedItems/{id}` and `/UserFavoriteItems/{id}`
2. `ImageURLs`: builds `/Items/{id}/Images/{Primary|Backdrop|Logo|Thumb}` with `maxWidth`, `tag` and `quality`; episodes fall back to series art when missing.
3. Shared `ImagePipeline` in Core using a `DataLoader` whose `URLSession` carries the `Authorization` header for the current server, with disk cache limits (200 MB) and downsampling enabled.
4. A small in-memory cache keyed by request so returning to Home does not refetch within 60 seconds; pull-to-refresh bypasses it.

Tests: each repository function decodes a recorded fixture; `ImageURLs` is a pure function with tests; fallback behaviour for episodes.

### 1.5 Screens on real data

Steps:

1. Connect flow: `AddServerView` (address field, discovered servers list, HTTP warning sheet, certificate fingerprint sheet), `SignInView` (Quick Connect first, password second), server and user switcher in Settings.
2. `HomeView`: Continue Watching (`LandscapeCard`), Next Up, Latest per library view. Loading, empty and error states from Design.
3. `LibraryView`: grid per view with sort (name, date added, premiere date, rating) and filters (unplayed, favourites, genre, year) as `GlassChip`s; paged loading in `LazyVGrid` with `onAppear` prefetch.
4. `ItemDetailView` for movie, series, season and episode: `HeroHeader`, overview, cast row, similar row, season and episode lists; mark played and favourite from the toolbar and from card context menus.
5. `SearchView`: live results from `search(term:)`, grouped.
6. `SettingsView`: servers and users, playback quality caps for Wi-Fi and cellular (max bitrate), clear cache, licences, version.

Acceptance: the owner browses their real library on iPhone and iPad; images are sharp and never load full size in grids; every error path shows a designed state.

### 1.6 Playback engine (SerafinPlayback)

Steps:

1. `DeviceProfile.serafin(maxBitrate:)`: what AVPlayer can direct play (containers mp4, m4v, mov; video h264, hevc; audio aac, mp3, ac3, eac3, alac, flac; subtitles mov_text embedded and vtt external), a transcoding profile of HLS fMP4 with hevc and h264 video and aac, eac3, ac3 audio, `breakOnNonKeyFrames`, and subtitle profiles vtt (external and hls) with ass and ssa marked for burn-in. Exclude AV1 and Dolby Vision from direct play in 1.0 (transcode instead); note as a Phase 2 follow-up. Use Swiftfin's native-player profile as a reference for what AVPlayer handles; write ours from scratch.
2. `PlaybackNegotiator`: `POST /Items/{id}/PlaybackInfo` with the profile, `userId`, `maxStreamingBitrate`, `startTimeTicks`, and chosen `audioStreamIndex` / `subtitleStreamIndex`. From the response choose the media source and produce a `PlaybackPlan`: `.directPlay(url)` built from `/Videos/{id}/stream?static=true&mediaSourceId=…&api_key=…`, or `.transcode(url)` from `transcodingUrl`, plus `playSessionId`.
3. `PlayerEngine` (`@Observable @MainActor`): wraps `AVPlayer`; state `idle / loading / ready / playing / paused / ended / failed`; exposes elapsed, duration, buffered, rate; `seek`, `skip(seconds:)`, track selection via `AVMediaSelectionGroup` when the asset exposes it, otherwise re-negotiates with new stream indices and resumes at the same position.
4. `ProgressReporter`: `POST /Sessions/Playing` on start, `/Sessions/Playing/Progress` every 10 seconds and on pause, seek and resume, `/Sessions/Playing/Stopped` on dismiss, app background, item end and track re-negotiation. Position in ticks (seconds × 10,000,000). Resume uses `UserData.playbackPositionTicks`.
5. Audio session `.playback` with `.moviePlayback` mode, activated on play, deactivated on stop.
6. Now Playing: `MPNowPlayingSession` with the player, automatic info publishing on, artwork from the pipeline, plus `MPRemoteCommandCenter` handlers for play, pause, toggle, skip 10, change position.
7. Picture in Picture: `AVPlayerLayer` in a `UIViewRepresentable`, `AVPictureInPictureController` with `canStartPictureInPictureAutomaticallyFromInline`.
8. AirPlay: `AVRoutePickerView` representable, `allowsExternalPlayback` true.
9. Next episode: for an episode, prefetch the next item via `GET /Shows/NextUp` or the season list and expose `nextItem` for autoplay.

Tests: `DeviceProfile` snapshot test against a committed JSON (any change is a deliberate diff); negotiator chooses direct play, direct stream and transcode correctly from three fixtures; tick conversions; progress reporter sends the right sequence against a stub transport.

### 1.7 Player screen

Steps:

1. `PlayerView` full screen, landscape on iPhone, `PlayerControls` wired to `PlayerEngine`, controls auto-hide after 3 seconds, tap to show, drag on the scrubber with time preview, double-tap sides to skip.
2. Tracks sheet: audio and subtitle lists from the media source streams; selection re-negotiates or switches in place.
3. Playback speed menu (0.75, 1, 1.25, 1.5, 2).
4. Resume prompt on the hero play pill ("Resume · 32 min left" or "Start over" in the context menu).
5. Autoplay next: at the end of an episode, a 10-second countdown card with the next episode's `LandscapeCard`; cancel returns to the detail screen.
6. Mini player in the tab bar accessory while audio continues in the background; tapping returns to the full player.

Acceptance (Gate 1): on the owner's server, a movie and a TV episode each play from start to end with correct resume, audio and subtitle switching, PiP, AirPlay, lock-screen controls, and progress visible in the Jellyfin dashboard. Direct play, direct stream and transcode have each been exercised at least once (use a mkv to force a direct stream and a bitrate cap to force a transcode).

---

## Phase 2 — Delight

Each item is one task; order is flexible within the phase.

- 2.1 Transitions: `glassEffectID` morphs between the hero play pill and the mini player; chip containers animate selection; skeleton loading that matches card geometry.
- 2.2 iPad: three-column layouts for detail, pointer hover on every card, keyboard shortcuts (space, arrows for seek, F for full screen, Cmd-F for search), Stage Manager sizes.
- 2.3 Haptics pass with `.sensoryFeedback` per the design rules.
- 2.4 Collections and genres as browsable groups; letter index on long grids.
- 2.5 Skip intro and credits via `GET /MediaSegments/{itemId}` when the server provides segments; a glass "Skip intro" pill that appears for the segment's duration.
- 2.6 App lock with `LocalAuthentication`, optional, with a grace period setting.
- 2.7 Accessibility audit: VoiceOver rotor through every screen, Dynamic Type at AX5, Reduce Motion and Reduce Transparency, Bold Text, Increase Contrast. Fix everything found.
- 2.8 App Intents: "Continue watching", "Play [item]", "Search Serafin"; Spotlight indexing of library items with artwork; Siri phrases registered.
- 2.9 Settings polish: per-server quality caps, subtitle appearance (size, background), default audio and subtitle language.
- 2.10 Performance: cold launch under one second to interactive on an iPhone 15, scroll at 120 Hz in grids with 2,000 items, memory under 200 MB after ten minutes of browsing; instrument with Instruments and fix.
- 2.11 Error and offline behaviour: cached Home renders when the server is unreachable, with a clear banner.
- 2.12 Dolby Vision and AV1 direct-play detection by device capability (`AVURLAsset.isPlayable`, `VTIsHardwareDecodeSupported`), extending the DeviceProfile accordingly.
- 2.13 AVPlayer limits, documented and handled. AVPlayer can't natively play MKV containers, DTS or TrueHD audio, or ASS/SSA subtitles, so these go through the server. MKV with h264/hevc and AAC/AC3/EAC3 is a cheap remux (direct stream, no quality loss). DTS/TrueHD is a cheap audio-only transcode. ASS/SSA forces burn-in, which is a full video transcode; image subtitles (PGS, VobSub, DVB) are burned in the same way. Show which of the three is happening, with this exact wording, used identically in the player and in a short Settings explanation: "Direct play"; "Repackaged on server (no quality loss)" for a direct stream; "Transcoding on server" for a transcode. A compatibility player for users who want everything direct played is post-1.0: when we get there, evaluate libmpv (via the MPVKit package) and VLCKit for format coverage, licence, and the loss of PiP, AirPlay and Now Playing. Out of scope for 1.0; do not add either dependency now.
  - Done:
    - The device profile sends MKV, DTS, TrueHD and styled or image subtitles through the server, and burns in the subtitles AVPlayer can't show.
    - `PlaybackNegotiator` classifies every stream as direct play, direct stream or transcode. Jellyfin never reports a direct stream itself; it sends repackaging and conversion through the same HLS address. So the negotiator follows the server's own copy rules: a stream is a direct stream when the server's only reasons are the container, HEVC's codec tag, or a text subtitle it adds to the stream, and the stream accepts the original codecs. A burned-in subtitle makes it a transcode. Progress reports carry that play method.
    - One `PlaybackDelivery` type holds the three names, so the player and Settings can't drift apart. The player's Audio and Subtitles sheet shows the current one under its title, and Settings explains all three under "How Videos Play".
    - A debug log line names the container, codecs and the server's reasons, without identifying the item.
- 2.14 Home hero. Home's top third was a large "Home" title over empty space. Like the Apple TV app's Watch Now on iPhone, Home now opens on a full-bleed featured item under the status bar, with its title, one prominent action, and the first row rising out of the fade. Restraint over the look of Jellyfin's Media Bar plugin.
  - `HomeHero` in `SerafinDesign`, on `MockMedia`, with light, dark and AX5 previews:
    - A horizontally paged hero of 3 to 5 `HeroItem`s. Swipe to page, no auto-advance. A small, tappable glass capsule of page dots sits bottom-trailing.
    - Each page's backdrop is full-bleed, aspect-filled and under the status bar, about 62% of the screen's height on iPhone and 48% on iPad. A gradient runs from clear at 45% to the background colour at 100%, with a faint top scrim for the status bar. Without a backdrop, the primary image is scaled and blurred instead.
    - Bottom-leading over the fade: the logo (`/Items/{id}/Images/Logo`, at most 72 pt high and 70% wide), or the title in bold `largeTitle`. Under it, one metadata line in `textSecondary`: "Sherlock Holmes · S1 E3 · A Case of Identity" for an episode, "1927 · 1 hr 32 min · NR" for a movie. Then the overview, at most two lines, hidden at accessibility text sizes.
    - Actions in a `GlassEffectContainer`: a `.glassProminent` pill tinted with `ArtworkTint` from the backdrop, saying "Resume · 9 min left", "Play S1 E1" for an unwatched series, or "Play" for a movie; and a circular glass info button that opens the detail screen. Long-press opens the standard item context menu.
    - Tapping the artwork opens detail with the zoom transition. The backdrop has a slight parallax (about 0.3 of the vertical scroll) and stretches on overscroll, both off under Reduce Motion. Under Reduce Transparency the pills are plain material.
    - Each page is one accessibility element, such as "Featured: Sherlock Holmes, A Case of Identity, 9 minutes left", with Resume and Show Details actions. The pager announces "page 2 of 4".
  - `HomeHeroModel` in `SerafinFeatures` picks up to five: the most recently played item in progress, the first Next Up episode, then the newest additions across Movies and Shows. It skips repeats and anything with neither a backdrop nor a primary image. A server with no history shows its newest additions. The next page's backdrop is prefetched through the shared pipeline at screen width × scale. Images crossfade and never pop.
  - Home: no large "Home" title, since the hero is the top of the screen; an inline title appears only once scrolled, with no toolbar background over the hero. Every row header gets the chevron and opens its list. Continue Watching cards drop the played check. Sections are 24 pt apart. "Latest in Shows" follows "Latest in Movies". The hero's skeleton has its geometry, so nothing jumps.
  - Acceptance: before-and-after screenshots on iPhone 17 and iPad in light and dark, and at AX5. The hero appears on first launch, scrolls at 120 Hz with no image pop-in, and the first row's top edge sits inside the fade. Previews work offline. No new dependencies.

Gate 2: the native-feel checklist in the project plan passes on iPhone and iPad in light and dark, verified by the owner.

---

## Phase 3 — Beta

- 3.1 `docs/SECURITY.md`: threat model (assets, actors, trust boundaries), the security table from `AGENTS.md` with where each control lives in code, and a data-flow diagram. Reviewed against the code, not written from memory.
- 3.2 Dependency audit: `Package.resolved` pinned, each dependency's network behaviour checked, licence list screen in Settings generated from the packages.
- 3.3 Demo server: a hosted Jellyfin with public-domain content and a `reviewer` account; credentials go in App Review notes only.
- 3.4 App Store Connect: privacy nutrition label "Data Not Collected", age rating 4+, screenshots on 6.9", 6.5" and 13" devices taken on the demo server, layered app icon for iOS 26, subtitle "A Liquid Glass client for Jellyfin", description with no official-status claims and no piracy adjacent words.
- 3.5 TestFlight: internal build, then a public link for r/jellyfin and the Jellyfin forum. Triage with GitHub issues; label `beta-blocker` for crashes and security.

Gate 3: two weeks of beta with no open `beta-blocker`. Then submit.

---

## First prompt for the coding agent

Paste this to start:

> Read `AGENTS.md` and `docs/PLAN.md` completely. Confirm the toolchain by running `xcodebuild -version` and `xcodegen --version`, and list the available iOS simulators. Then start task 0.1 exactly as written: post your five-line file plan first, implement it, run the definition-of-done checklist, and open a PR titled "0.1 Repository scaffold". Do not start 0.2 until I have reviewed the PR.
