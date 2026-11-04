# Server compatibility

Serafin supports Jellyfin 10.10 and newer. This page records which Jellyfin versions Serafin was checked against, what changed in Jellyfin 12.0, how Serafin authenticates each request, and how to run the checks again.

## Versions checked

Checked on 4 November 2026 with `scripts/server_check.py` and jellyfin-sdk-swift 3.3.0 (`8ce10a1`), the version `Package.resolved` pins. Each server was a fresh container from Jellyfin's official image, with legacy authorization turned off wherever the server has that setting.

| Jellyfin | Image | Legacy authorization | API check | Live check |
| --- | --- | --- | --- | --- |
| 10.10.7 | `jellyfin/jellyfin:10.10.7` | no setting; every form accepted | passed | 32 of 32 |
| 10.11.11 | `jellyfin/jellyfin:10.11.11` | turned off (10.11's default is on) | passed | 32 of 32 |
| 12.4.0 | `jellyfin/jellyfin:12.4.20261026-211555`, `latest` | off, the default | passed | 32 of 32 |
| 13.0.0, unstable | `jellyfin/jellyfin:unstable`, build 2026110213 | off, the default | passed | 32 of 32 |

The demo server, which App Review and the App Store screenshots use, has run Jellyfin 12.2.0 since October. Legacy authorization is off there too, unless someone has turned it back on.

The "This Server Needs an Update" message names this range: 10.10 or newer, tested through `PublicServerInfo.newestTestedVersion`.

## What Jellyfin 12.0 changed

- **Legacy authorization is off.** Jellyfin 10.11 added `EnableLegacyAuthorization`, on by default. From 12.0 it defaults to off, and the `DisableLegacyAuthorization` migration turns it off on every server that upgrades (`Jellyfin.Server/Migrations/Routines/20260531160000_DisableLegacyAuthorization.cs`).
- **Two token forms remain.** With the setting off, the server reads a token only from an `Authorization` header with the `MediaBrowser` scheme and a `Token` field, or from an `ApiKey` query parameter. It refuses the `X-Emby-Authorization`, `X-Emby-Token` and `X-MediaBrowser-Token` headers, the `api_key` query parameter, and the `Emby` scheme (`Jellyfin.Server.Implementations/Security/AuthorizationContext.cs`). The live check shows each of these refused with 401 on 10.11, 12.4 and unstable.
- **The server's own addresses changed with it.** Jellyfin 10.10 writes `api_key` into the stream, subtitle and trickplay addresses it makes. From 10.11 it writes `ApiKey` (`MediaBrowser.Model/Dlna/StreamInfo.cs`, `Jellyfin.Api/Helpers/DynamicHlsHelper.cs`, `Jellyfin.Api/Controllers/SubtitleController.cs`).
- **Some requests need no token at all.** The original file at `/Videos/{id}/stream` and the image endpoints answer without one. HLS streams, trickplay tiles and subtitle playlists need one; their controllers carry `[Authorize]`.
- **Each version of a movie or an episode keeps its own progress.** When a client reports playing one version of an item, 12.0 and later record the position on that version (`GetProgressItem` in `Emby.Server.Implementations/Session/SessionManager.cs`), where 10.11 recorded it on the item, so every version shared one position. The item itself gets the played mark and the date of its version played most recently, but keeps its own position (`MediaBrowser.Controller/Library/VersionResumeData.cs`). Continue Watching lists the version left part way through rather than the item, and the item's page lists that version first (`SetAlternateVersionResumeStates` in `Emby.Server.Implementations/Library/MediaSourceManager.cs`). So Serafin reads each version's progress on a movie's or an episode's page and resumes from where it was left in whichever version that was (`ItemDetailModel`, `MediaVersions.resumePoint`). This is the same in 12.0, 12.2, 12.3, 12.4 and unstable, and a 12.4 and a 10.11 server here behaved as their sources say.

## How Serafin authenticates each request

Serafin sends no legacy form of its own, so nothing needed to change for 12.0.

| Request | Form | Code | Pinned by |
| --- | --- | --- | --- |
| API calls: browsing, PlaybackInfo, playback reports, played state, Quick Connect, sign-out | `Authorization: MediaBrowser DeviceId=…, Device=…, Client=…, Version=…, Token=…` | the SDK's `JellyfinClient.authorizationHeaders` | `LibraryRepositoryTests` |
| Images and trickplay tiles | the same header, with its values quoted | `DeviceIdentity.authorizationHeader`, `Artwork` | `DeviceIdentityTests`, `ImageURLsTests` |
| The original file, for direct play | an `ApiKey` query parameter and no header, because AVPlayer can't add one | `PlaybackNegotiator`, through the SDK's `url(with:queryAPIKey:)` | `NegotiationTests` |
| Repackaged or converted HLS, and its subtitles | the server's own address as it is: `ApiKey` from 10.11, `api_key` from 10.10, which accepts it | `PlaybackNegotiator`, `StreamLoader` | `NegotiationTests`, `SubtitlePlaylistsTests` |
| Downloads | the quoted header, with the token taken out of the server's address | `DownloadPlanner`, `Downloads` | `DownloadPlannerTests`, `DownloadsTests` |

## The checks

`scripts/server_check.py` runs two checks against a server.

- **API check.** It reads the server's OpenAPI document (`/api-docs/openapi.json`) and finds every endpoint Serafin's code calls through the SDK (`Paths.…`). It confirms the server still has each one, with the same method and path, and isn't marking it deprecated. Then it follows those endpoints' responses to every enum they can carry and confirms the pinned SDK decodes every value. The SDK's enums are plain `String` enums, so a single value they don't know fails the whole response, such as a new `BaseItemKind` failing a whole library page. This check needs no account and changes nothing, so it can run against any server.
- **Live check.** On a fresh server only, it finishes the setup wizard, adds a Movies library with trickplay on, creates a user who isn't an administrator, and turns legacy authorization off. Then it makes each request Serafin makes, in Serafin's form:
  - sign in with a password;
  - browse the libraries, latest items, Continue Watching, an item, and a version's progress;
  - load a poster and a trickplay tile;
  - fetch the original file with `ApiKey`;
  - fetch the converted HLS stream's playlists, segments and subtitles without a header;
  - download the original file and a converted one;
  - report playback, and mark the item played and unplayed;
  - sign in with Quick Connect, approved from another session;
  - sign out, after which the token no longer works.

  It also records how the server answers each legacy form, which shows what the setting refused.

```sh
python3 scripts/server_check.py http://localhost:8097          # the API check, against any server
python3 scripts/server_check.py http://127.0.0.1:8096 --setup  # both checks, against a fresh server only
```

The script reads the SDK's sources from the checkout that `swift package --package-path Packages/SerafinKit resolve` makes, or from `--sdk <folder>`, where it fetches the pinned revision if the folder doesn't exist.

### Every night

`.github/workflows/server-compatibility.yml` runs both checks at 06:17 UTC on fresh containers of `unstable`, `latest`, 10.11.11 and 10.10.7, each with a generated test video and subtitles. It also runs on any pull request that changes the script or the workflow, and from the Actions tab with Run workflow.

When a run fails, its log names the request, the endpoint or the enum value that broke. What to do depends on which image failed:

- **`unstable`:** the next Jellyfin will break Serafin. Fix it in Core, or move to an SDK release that knows the new values, before that version ships.
- **`latest`:** users on the current release are affected now.
- **10.10.7 or 10.11.11:** a change in Serafin, or the SDK it pins, broke an older server Serafin still supports.

GitHub's macOS runners can't run Docker, and SerafinCore can't build on Linux. So the nightly job replays Serafin's requests from Python rather than running Serafin's Swift code against the server. The tests named in the table above pin each form in Swift, and the script mirrors them. A change to one needs the same change in the other.

### By hand

The demo server's README, under "The next Jellyfin", runs the `unstable` image on a computer at home for the checklist on a phone. That checklist covers sign-in by password and Quick Connect, browsing, posters, direct and converted playback, trickplay, a download played in Airplane Mode, and sign-out.

### After a new Jellyfin release

Run the script against the new version. Add a row to the table above, and when it passes, raise `PublicServerInfo.newestTestedVersion`.
