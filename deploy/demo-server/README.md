# Demo server

`https://demo.getserafin.app` is a stock Jellyfin with a few Blender open films on it. App Review signs in to it to try Serafin, and the App Store screenshots are taken on it, so neither ever shows anyone's personal library. The files in this folder are the ones running on the server, copied from `/opt/serafin-demo`.

No password belongs in this folder or anywhere else in the repo. The account passwords live in the owner's password manager and in the App Review notes in App Store Connect.

## Host

- Hetzner Cloud CPX02 (1 vCPU AMD, 1 GB RAM, 20 GB NVMe, 20 TB traffic) in Nuremberg, Ubuntu 26.04, hostname `serafin-demo`.
- Root login by SSH key only.
- `ufw` allows OpenSSH, 80/tcp, 443/tcp and 443/udp, nothing else. Unattended upgrades are on.
- Docker from get.docker.com, plus `ffmpeg` and `unzip` for `fetch-media.sh`.

Every file the films need is H.264 and AAC in an MP4 with faststart, so Jellyfin direct plays them and the single vCPU never transcodes. Hardware acceleration is off.

## DNS

The domain is on Cloudflare. `demo.getserafin.app` is an `A` record to the server's IPv4 address with the proxy status **DNS only** (grey cloud). It must stay unproxied: Caddy gets its certificate from Let's Encrypt directly over TLS-ALPN, and video must stream straight from the server, never through Cloudflare's proxy. There is no `AAAA` record.

## Stack

`docker-compose.yml` runs two containers on one network, `web`:

- `jellyfin`, with no host ports. `./config`, `./cache` and `./media` (read only) are mounted, and `JELLYFIN_PublishedServerUrl` is the public address so the server advertises the right URL.
- `caddy`, on 80, 443/tcp and 443/udp (HTTP/3). `Caddyfile` compresses responses, sends HSTS and proxies everything to `jellyfin:8096`. Certificates are kept in the `caddy_data` volume and renew on their own.

To set it up on a new host:

```sh
mkdir -p /opt/serafin-demo && cd /opt/serafin-demo
# copy docker-compose.yml, Caddyfile and fetch-media.sh here
./fetch-media.sh
docker compose up -d
```

Then finish the Jellyfin setup wizard at the public address and set the dashboard as described under Jellyfin below.

Jellyfin is pinned to an exact build tag (`12.2.20261005-225228`, Jellyfin 12.2) so a restart never upgrades the server under App Review. To update, pick the new dated tag from Docker Hub, change it in `docker-compose.yml` here and on the server, then run `docker compose pull jellyfin && docker compose up -d`. Check the version with `docker compose exec jellyfin /jellyfin/jellyfin --version`. Never run `docker compose down -v`: it deletes the certificates along with the volumes.

## Media

Eleven Blender open films and the three Caminandes shorts as one show, about 2.3 GB in all, every one under a CC BY licence. [SOURCES.md](SOURCES.md) lists each title's licence and where it comes from. Agent 327 is left out because it is CC BY-ND.

`fetch-media.sh` needs `yt-dlp` as well as `curl`, `unzip` and `ffmpeg`. It downloads each film, then `normalise` remuxes it to MP4 with the first video and audio track, AAC stereo audio and faststart, re-encoding the video to H.264 only when it is something else. YouTube downloads ask for H.264 at up to 1080p, so nothing is re-encoded. Each download is deleted once normalised, and anything already in the library is skipped, so the script can be run again after a change:

```sh
cd /opt/serafin-demo && nohup ./fetch-media.sh > fetch.log 2>&1 &
```

Movie folders carry the TMDB ID (`Movies/Spring (2019) [tmdbid-593048]/Spring (2019).mp4`) because titles like Spring, Hero and Charge are shared with other films. TMDB lists the Caminandes films as three movies rather than a series, so `fetch-media.sh` writes the show's `tvshow.nfo` and episode NFOs itself and cuts its poster and backdrop from stills of the film.

Big Buck Bunny comes from Kodi's mirror at `mirrors.mit.edu`, because Blender zipped its original folder in 2023 and the old URL returns 404. Tears of Steel is not included: blender.org returns 404 for it and the Purdue mirror is gone. Debian's mirror at `cdimage.debian.org/mirror/blender.org/demo/movies/` is the working fallback when a blender.org download disappears.

After a fetch, run a library scan from the dashboard (Libraries, Scan All Libraries) and check that every title has a poster.

## Jellyfin

- Setup wizard complete. Libraries: Movies (`/media/Movies`) and Shows (`/media/Shows`), TMDB metadata, English, United States.
- Dashboard, Networking: published server URL `https://demo.getserafin.app`, known proxy `caddy`.
- Dashboard, Playback: hardware acceleration None.
- Quick Connect enabled.

### Users

| User | For | Permissions |
| --- | --- | --- |
| `admin` | the owner only | administrator |
| `reviewer` | App Review | Movies and Shows only. No server management, no deletion, no remote control, no downloading. Playback and transcoded playback allowed. |
| `screenshots` | App Store screenshots | the same as `reviewer` |

Screenshots for the App Store are taken only with the `screenshots` account on this server. Guideline 5.2.1 rejects screenshots that show third-party copyrighted content, and every title here is a Blender open film.

## Checking it works

1. `ssh serafin-demo 'cd /opt/serafin-demo && docker compose ps'` shows both containers up and `jellyfin` healthy.
2. `curl -sI https://demo.getserafin.app/System/Info/Public` returns 200 over a valid certificate.
3. On an iPhone on cellular, not Wi-Fi, sign in to Serafin as `reviewer` and play Big Buck Bunny. The player's info shows Direct play.

This was last done on 9 October 2026.

## App Review notes

Paste into App Store Connect, App Review Information, Notes, and fill in the passwords there:

```text
Serafin is a client for Jellyfin, a free media server people run themselves. It has no content of its own and no accounts of its own; it connects to a server the user names. We run a demo server with Blender Foundation open films for review.

Server: https://demo.getserafin.app
Username: reviewer
Password: <reviewer password>

To sign in:
1. Open Serafin. On the Welcome to Serafin screen, enter https://demo.getserafin.app as the Server Address and tap Connect.
2. Enter the username and password above and tap Sign In.
3. Open any title, for example Big Buck Bunny, and tap Play.

A second account, screenshots (password <screenshots password>), has the same access and was used for the App Store screenshots.

Serafin collects no data and contains no third-party SDKs, analytics or advertising. The only network connection it makes is to the server the user signs in to.
```
