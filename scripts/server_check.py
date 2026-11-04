#!/usr/bin/env python3
"""Checks a Jellyfin server against what Serafin sends it and what Serafin reads back.

The API check reads the server's OpenAPI document and confirms two things for every endpoint Serafin's code calls
through the Jellyfin SDK: that the server still has it, with the same method and path, and that every enum value its
responses can carry is one the pinned SDK can decode. The SDK's enums are plain String enums, so one value they don't
know fails the whole response. This check needs no account and changes nothing, so it can run against any server.

The live check makes each request Serafin makes, authenticated the way Serafin authenticates it, from sign-in to
sign-out. It needs a fresh server, because it finishes the setup wizard, adds a Movies library from /media/Movies with
trickplay on, creates a user, and turns off legacy authorization where the server has that setting, so that only the
forms Jellyfin 12 accepts by default can pass. Never point --setup at a server anyone uses.

What Serafin sends, and the code and tests that pin it:

- API calls: `Authorization: MediaBrowser DeviceId=…, Device=…, Client=…, Version=…, Token=…`, unquoted, as the
  SDK's JellyfinClient.authorizationHeaders writes it (LibraryRepositoryTests).
- Images and trickplay tiles: the same header with its values quoted, from DeviceIdentity.authorizationHeader and
  Artwork (DeviceIdentityTests, ImageURLsTests).
- The original file for playing: `/Videos/{id}/stream?static=true&…&ApiKey=…`, the only token form AVPlayer can send
  (PlaybackNegotiator.staticURL, NegotiationTests).
- Converted playback: the server's own HLS address, unchanged, with whatever token query it wrote (PlaybackNegotiator).
- Downloads: `/Items/{id}/Download`, or the server's converted address with its token taken out, sent with the quoted
  header (DownloadPlanner, Downloads, DownloadPlannerTests, DownloadsTests).
- Quick Connect and sign-out: the SDK's requests, with the header (AccountsTests).

Usage, from the repository root:

    python3 scripts/server_check.py http://localhost:8097          # the API check alone, against any server
    python3 scripts/server_check.py http://127.0.0.1:8096 --setup  # both checks, against a fresh server

It reads the SDK's sources from the checkout `swift package --package-path Packages/SerafinKit resolve` makes, or with
--sdk from a folder of your choice, fetching the revision Package.resolved pins when the folder doesn't exist yet.
.github/workflows/server-compatibility.yml runs both checks every night. docs/COMPATIBILITY.md has the results.
"""

import argparse
import http.client
import json
import pathlib
import re
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
SOURCES = ROOT / "Packages/SerafinKit/Sources"
RESOLVED = ROOT / "Packages/SerafinKit/Package.resolved"
DEFAULT_SDK = ROOT / "Packages/SerafinKit/.build/checkouts/jellyfin-sdk-swift"
SDK_REPOSITORY = "https://github.com/jellyfin/jellyfin-sdk-swift.git"
DEVICE_ID = "serafin-server-check"


class Server:
    """Plain HTTP requests to one server, retried while it's still starting."""

    def __init__(self, base):
        self.base = base.rstrip("/")

    def request(self, method, path, headers=None, body=None, limit=None, timeout=120):
        """Returns (status, body bytes, headers). Waits out the 503s and dropped connections of a server that is still
        starting: 10.11 answers 503 during its first migrations, then restarts its listener."""
        result = (0, b"", {})
        for _ in range(60):
            try:
                result = self._once(method, path, headers, body, limit, timeout)
            except (ConnectionError, urllib.error.URLError, http.client.HTTPException) as error:
                result = (0, str(error).encode(), {})
            if result[0] not in (0, 503):
                return result
            time.sleep(2)
        return result

    def json(self, method, path, headers=None, body=None):
        status, data, _ = self.request(method, path, headers, body)
        try:
            return status, json.loads(data) if data else None
        except ValueError:
            return status, None

    def _once(self, method, path, headers, body, limit, timeout):
        url = path if path.startswith("http") else self.base + path
        data = json.dumps(body).encode() if body is not None else None
        request = urllib.request.Request(url, data=data, method=method, headers=dict(headers or {}))
        if data is not None:
            request.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(request, timeout=timeout) as response:
                return response.status, response.read(limit) if limit else response.read(), dict(response.headers)
        except urllib.error.HTTPError as error:
            return error.code, error.read(2048), dict(error.headers or {})


def authorization(token=None, scheme="MediaBrowser", device_id=DEVICE_ID):
    """The header as DeviceIdentity.authorizationHeader writes it for images and downloads: values quoted."""
    fields = [("Client", "Serafin"), ("Device", "Server check"), ("DeviceId", device_id), ("Version", "1.1.0")]
    if token:
        fields.append(("Token", token))
    return scheme + " " + ", ".join(f'{name}="{value}"' for name, value in fields)


def sdk_authorization(token=None, device_id=DEVICE_ID):
    """The header as the SDK's JellyfinClient.authorizationHeaders writes it for API calls: values unquoted."""
    fields = [("DeviceId", device_id), ("Device", "Server check"), ("Client", "Serafin"), ("Version", "1.1.0")]
    if token:
        fields.append(("Token", token))
    return "MediaBrowser " + ", ".join(f"{name}={value}" for name, value in fields)


# MARK: - API check


def sdk_revision():
    pins = json.loads(RESOLVED.read_text())["pins"]
    return next(pin["state"]["revision"] for pin in pins if pin["identity"] == "jellyfin-sdk-swift")


def check_sdk_checkout(sdk):
    """Fetches the pinned SDK revision into `sdk` when nothing is there, and refuses a checkout at another revision,
    which would check the wrong SDK."""
    if not sdk.exists():
        print(f"Fetching jellyfin-sdk-swift {sdk_revision()[:7]} into {sdk}")
        for command in (
            ["git", "init", "-q", str(sdk)],
            ["git", "-C", str(sdk), "fetch", "-q", "--depth", "1", SDK_REPOSITORY, sdk_revision()],
            ["git", "-C", str(sdk), "checkout", "-q", "FETCH_HEAD"],
        ):
            subprocess.run(command, check=True)
    if not (sdk / "Sources" / "Paths").is_dir():
        sys.exit(f"No SDK sources at {sdk}. Run: swift package --package-path Packages/SerafinKit resolve")
    if (sdk / ".git").exists():
        head = subprocess.run(["git", "-C", str(sdk), "rev-parse", "HEAD"], capture_output=True, text=True).stdout
        if head.strip() and head.strip() != sdk_revision():
            sys.exit(f"The SDK at {sdk} is at {head.strip()}, but Package.resolved pins {sdk_revision()}.")


def endpoints_serafin_calls():
    names = set()
    for path in SOURCES.rglob("*.swift"):
        names |= set(re.findall(r"\bPaths\.([a-z]\w*)\b", path.read_text()))
    return names


def sdk_endpoints(sdk):
    """Each SDK request's name, path, method and OpenAPI operation ID, from its generated Paths sources."""
    pattern = re.compile(
        r'static (?:func|var) (\w+)\b.*?Request(?:<[^\n]*?>)?\(\s*path: "((?:[^"\\]|\\.)*)",\s*method: "(\w+)"'
        r'.*?id: "(\w+)"\s*\)',
        re.S,
    )
    found = {}
    for path in (sdk / "Sources" / "Paths").glob("*.swift"):
        for match in pattern.finditer(path.read_text()):
            found[match.group(1)] = (match.group(2), match.group(3).lower(), match.group(4))
    return found


def sdk_enum_values(sdk, name):
    """The raw values the SDK's enum `name` decodes, or None when it isn't a plain String enum."""
    path = sdk / "Sources" / "Entities" / f"{name}.swift"
    if not path.exists():
        return None
    text = path.read_text()
    if not re.search(rf"\benum {name}: String\b", text) or "init(from decoder" in text:
        return None
    values = set()
    for match in re.finditer(r'^\s*case `?(\w+)`?(?: = "((?:[^"\\]|\\.)*)")?\s*$', text, re.M):
        values.add(match.group(2) if match.group(2) is not None else match.group(1))
    return values


def route(path):
    """A path with its parameters blanked, so the SDK's `/Items/\\(itemID)` matches the server's `/Items/{itemId}`."""
    return re.sub(r"\{[^}]*\}", "{}", re.sub(r"\\\([^)]*\)", "{}", path)).lower()


def api_check(server, sdk):
    status, spec = server.json("GET", "/api-docs/openapi.json")
    if status != 200 or not isinstance(spec, dict):
        return [f"no OpenAPI document (HTTP {status})"], []
    operations, routes = {}, {}
    for path, item in spec.get("paths", {}).items():
        for method, operation in item.items():
            if isinstance(operation, dict):
                operations[operation.get("operationId")] = (path, method, operation)
                routes[(route(path), method)] = (path, method, operation)

    problems, notes, used = [], [], []
    definitions = sdk_endpoints(sdk)
    for name in sorted(endpoints_serafin_calls()):
        if name not in definitions:
            problems.append(f"Paths.{name}: not found in the SDK's sources, so it can't be checked")
            continue
        sdk_path, method, operation_id = definitions[name]
        found = operations.get(operation_id)
        if found and (route(found[0]), found[1]) != (route(sdk_path), method):
            found = None
        found = found or routes.get((route(sdk_path), method))
        if not found:
            problems.append(f"Paths.{name}: the server has no {method.upper()} {sdk_path} ({operation_id})")
            continue
        if found[2].get("deprecated"):
            notes.append(f"Paths.{name}: {method.upper()} {found[0]} is deprecated on this server")
        used.append(found[2])

    schemas = spec.get("components", {}).get("schemas", {})
    reachable = set()

    def walk(node):
        if isinstance(node, dict):
            reference = node.get("$ref")
            if isinstance(reference, str) and reference.startswith("#/components/schemas/"):
                name = reference.rsplit("/", 1)[1]
                if name not in reachable:
                    reachable.add(name)
                    walk(schemas.get(name, {}))
            for key, value in node.items():
                if key != "$ref":
                    walk(value)
        elif isinstance(node, list):
            for value in node:
                walk(value)

    for operation in used:
        for code, response in (operation.get("responses") or {}).items():
            if str(code).startswith("2"):
                walk(response)

    compared = 0
    for name in sorted(reachable):
        values = schemas.get(name, {}).get("enum")
        if values is None:
            continue
        known = sdk_enum_values(sdk, name)
        if known is None:
            notes.append(f"enum {name}: not compared, the SDK has no plain String enum for it")
            continue
        compared += 1
        unknown = sorted(set(map(str, values)) - known)
        if unknown:
            problems.append(f"enum {name}: the SDK can't decode {', '.join(unknown)}")
    notes.append(
        f"{len(used)} endpoints Serafin calls, {len(reachable)} schemas their responses use, {compared} enums compared")
    return problems, notes


# MARK: - Live check


class Live:
    def __init__(self, server):
        self.server = server
        self.results = []

    def record(self, name, outcome, detail=""):
        self.results.append((name, outcome, str(detail)[:200]))

    def check(self, name, passed, detail=""):
        self.record(name, "pass" if passed else "FAIL", detail)

    def skip(self, name, reason):
        self.record(name, "skip", reason)

    def set_up(self):
        """Finishes the wizard, adds the library and the user, and turns legacy authorization off."""
        s = self.server
        status, info = s.json("GET", "/System/Info/Public")
        if status != 200:
            sys.exit(f"The server didn't answer /System/Info/Public (HTTP {status}).")
        admin_password, user_password = secrets.token_urlsafe(18), secrets.token_urlsafe(18)
        if (info or {}).get("StartupWizardCompleted"):
            sys.exit("--setup needs a fresh server, and this one is already set up.")
        s.request("POST", "/Startup/Configuration", body={
            "UICulture": "en-US", "MetadataCountryCode": "US", "PreferredMetadataLanguage": "en"})
        s.request("GET", "/Startup/User")
        for path, body in (
            ("/Startup/User", {"Name": "admin", "Password": admin_password}),
            ("/Startup/RemoteAccess", {"EnableRemoteAccess": True, "EnableAutomaticPortMapping": False}),
            ("/Startup/Complete", None),
        ):
            status, data, _ = s.request("POST", path, body=body)
            if status >= 300:
                sys.exit(f"Setup failed at {path}: HTTP {status} {data[:200]!r}")
        self.admin_token, _ = self.sign_in("admin", admin_password, "serafin-server-check-admin")
        self.admin = {"Authorization": sdk_authorization(self.admin_token, device_id="serafin-server-check-admin")}

        status, configuration = s.json("GET", "/System/Configuration", headers=self.admin)
        if isinstance(configuration, dict) and "EnableLegacyAuthorization" in configuration:
            configuration["EnableLegacyAuthorization"] = False
            s.request("POST", "/System/Configuration", headers=self.admin, body=configuration)
            status, configuration = s.json("GET", "/System/Configuration", headers=self.admin)
            self.legacy = "off" if configuration.get("EnableLegacyAuthorization") is False else "on"
        else:
            self.legacy = "no setting"

        s.request("POST", "/Users/New", headers=self.admin, body={"Name": "viewer", "Password": user_password})
        query = urllib.parse.urlencode(
            {"name": "Movies", "collectionType": "movies", "paths": "/media/Movies", "refreshLibrary": "false"})
        status, data, _ = s.request("POST", f"/Library/VirtualFolders?{query}", headers=self.admin, body={
            "LibraryOptions": {
                "EnableTrickplayImageExtraction": True,
                "ExtractTrickplayImagesDuringLibraryScan": True,
                "EnableRealtimeMonitor": False,
                "TypeOptions": [{"Type": "Movie", "MetadataFetchers": [], "MetadataFetcherOrder": [],
                                 "ImageFetchers": ["Screen Grabber"], "ImageFetcherOrder": ["Screen Grabber"]}],
            }})
        if status >= 300:
            sys.exit(f"Adding the library failed: HTTP {status} {data[:200]!r}")
        # Scans with /Library/Refresh rather than the add's refreshLibrary. From 12.2 the add drops its scan while
        # another one runs, such as the one a fresh server starts when its wizard finishes, and that scan began before
        # the library existed, so it never finds the film (LibraryManager.StartScanInBackground and
        # ConfigurationUpdated). /Library/Refresh stops a running scan and starts another, in every version.
        status, data, _ = s.request("POST", "/Library/Refresh", headers=self.admin)
        if status >= 300:
            sys.exit(f"Starting the library scan failed: HTTP {status} {data[:200]!r}")
        self.password = user_password

    def sign_in(self, username, password, device_id=DEVICE_ID):
        for _ in range(30):
            status, body = self.server.json(
                "POST", "/Users/AuthenticateByName", headers={"Authorization": sdk_authorization(device_id=device_id)},
                body={"Username": username, "Pw": password})
            if status == 200 and body:
                return body["AccessToken"], body["User"]["Id"]
            time.sleep(2)
        sys.exit(f"Signing in as {username} failed: HTTP {status}")

    def run(self):
        s = self.server
        token, user = self.sign_in("viewer", self.password)
        self.check("sign in with a password", bool(token))
        header = {"Authorization": sdk_authorization(token)}
        quoted = {"Authorization": authorization(token)}

        item = self.wait_for_item(user, header)
        item_id = item["Id"]
        status, detail = s.json("GET", f"/Items/{item_id}?userId={user}", headers=header)
        source = ((detail or {}).get("MediaSources") or [{}])[0]
        source_id = source.get("Id") or item_id

        # API calls, with the SDK's header.
        for name, path in (
            ("current user", "/Users/Me"),
            ("libraries", f"/UserViews?userId={user}"),
            ("latest", f"/Items/Latest?userId={user}"),
            ("continue watching", f"/UserItems/Resume?userId={user}"),
            ("item details", f"/Items/{item_id}?userId={user}"),
            ("a version's progress", f"/UserItems/{source_id}/UserData?userId={user}"),
        ):
            status, _, _ = s.request("GET", path, headers=header)
            self.check(f"browse: {name}", status == 200, f"HTTP {status}")

        # Images, with Artwork's header.
        tag = ((detail or {}).get("ImageTags") or {}).get("Primary")
        if tag:
            status, _, headers = s.request(
                "GET", f"/Items/{item_id}/Images/Primary?maxWidth=300&quality=90&tag={tag}", headers=quoted)
            self.check("images: poster", status == 200 and "image" in headers.get("Content-Type", ""), f"HTTP {status}")
        else:
            self.check("images: poster", False, "the server made no poster for the test video")

        self.check_trickplay(item_id, source_id, user, header, quoted)
        self.check_direct_play(item_id, source, source_id, token)
        self.check_converted(item_id, source, source_id, user, header)
        self.check_downloads(item_id, source, source_id, user, header, quoted)
        self.check_progress_and_played(item_id, source_id, user, header)
        self.check_quick_connect(user)
        self.record_legacy_forms(token)
        # What the server serves with no token at all, for the record.
        self.tokenless = {
            "original file": s.request(
                "GET", f"/Videos/{item_id}/stream?static=true&mediaSourceId={source_id}",
                headers={"Range": "bytes=0-1023"}, limit=1024)[0],
            "poster": s.request("GET", f"/Items/{item_id}/Images/Primary?maxWidth=300", limit=1024)[0],
        }

        status, _, _ = s.request("POST", "/Sessions/Logout", headers=header)
        self.check("sign out", status in (200, 204), f"HTTP {status}")
        status, _, _ = s.request("GET", "/Users/Me", headers=header)
        self.check("sign out: the token stops working", status == 401, f"HTTP {status}")

    def wait_for_item(self, user, header):
        """The first movie with subtitles, or after a minute any movie, once the library scan has found it."""
        for attempt in range(150):
            status, items = self.server.json(
                "GET", f"/Items?userId={user}&recursive=true&includeItemTypes=Movie&fields=MediaStreams",
                headers=header)
            movies = (items or {}).get("Items") or []
            with_subtitles = [movie for movie in movies if any(
                stream.get("Type") == "Subtitle" for stream in movie.get("MediaStreams") or [])]
            if with_subtitles or (movies and attempt >= 30):
                return (with_subtitles or movies)[0]
            time.sleep(2)
        sys.exit("The library scan found no movie in /media/Movies.")

    def check_trickplay(self, item_id, source_id, user, header, quoted):
        s = self.server
        trickplay = None
        for attempt in range(150):
            status, detail = s.json("GET", f"/Items/{item_id}?userId={user}&fields=Trickplay", headers=header)
            trickplay = (detail or {}).get("Trickplay")
            if trickplay:
                break
            if attempt == 20:
                status, tasks = s.json("GET", "/ScheduledTasks", headers=self.admin)
                for task in tasks or []:
                    if task.get("Key") == "RefreshTrickplayImages":
                        s.request("POST", f"/ScheduledTasks/Running/{task['Id']}", headers=self.admin)
            time.sleep(2)
        if not trickplay:
            self.check("trickplay: tiles made", False, "no trickplay after five minutes")
            return
        widths = trickplay.get(source_id) or next(iter(trickplay.values()))
        width = min(widths, key=int)
        tile = f"/Videos/{item_id}/Trickplay/{width}/0.jpg?mediaSourceId={source_id}"
        status, _, headers = s.request("GET", tile, headers=quoted)
        self.check("trickplay: tile, with the header", status == 200 and "image" in headers.get("Content-Type", ""),
                   f"HTTP {status}")
        status, _, _ = s.request("GET", tile)
        self.check("trickplay: tile without a token is refused", status == 401, f"HTTP {status}")

    def check_direct_play(self, item_id, source, source_id, token):
        query = urllib.parse.urlencode({"static": "true", "mediaSourceId": source_id, "deviceId": DEVICE_ID,
                                        "tag": source.get("ETag") or "", "ApiKey": token})
        status, data, _ = self.server.request(
            "GET", f"/Videos/{item_id}/stream?{query}", headers={"Range": "bytes=0-1023"}, limit=1024)
        self.check("direct play: original file, ApiKey query, no header", status in (200, 206), f"HTTP {status}")

    def playback_info(self, item_id, source_id, user, header, profile, subtitles):
        body = {"DeviceProfile": profile, "UserId": user, "MaxStreamingBitrate": 400_000, "EnableDirectPlay": False,
                "EnableDirectStream": False, "EnableTranscoding": True, "MediaSourceId": source_id,
                "AutoOpenLiveStream": False}
        if subtitles is not None:
            body["SubtitleStreamIndex"] = subtitles
        status, info = self.server.json(
            "POST", f"/Items/{item_id}/PlaybackInfo?userId={user}", headers=header, body=body)
        source = ((info or {}).get("MediaSources") or [{}])[0]
        return status, source.get("TranscodingUrl"), (info or {}).get("PlaySessionId")

    def check_converted(self, item_id, source, source_id, user, header):
        """Serafin's HLS stream: the server's address as it is, fetched with no header, as AVPlayer does."""
        s = self.server
        subtitles = next((x["Index"] for x in source.get("MediaStreams", []) if x.get("Type") == "Subtitle"), None)
        profile = {
            "MaxStreamingBitrate": 400_000,
            "DirectPlayProfiles": [],
            "TranscodingProfiles": [{"Container": "mp4", "Type": "Video", "VideoCodec": "h264", "AudioCodec": "aac",
                                     "Protocol": "hls", "Context": "Streaming", "MinSegments": 1,
                                     "BreakOnNonKeyFrames": True}],
            "SubtitleProfiles": [{"Format": "vtt", "Method": "Hls"}],
        }
        status, address, session = self.playback_info(item_id, source_id, user, header, profile, subtitles)
        self.check("converted play: the server gives an HLS address", status == 200 and bool(address), f"HTTP {status}")
        if not address:
            return
        master_url = s.base + address
        status, master, _ = s.request("GET", master_url)
        master = master.decode(errors="replace")
        self.check("converted play: master playlist", status == 200, f"HTTP {status}")
        variant = next((line for line in master.splitlines() if line and not line.startswith("#")), None)
        if variant:
            variant_url = urllib.parse.urljoin(master_url, variant)
            status, playlist, _ = s.request("GET", variant_url, timeout=180)
            playlist = playlist.decode(errors="replace")
            self.check("converted play: variant playlist", status == 200, f"HTTP {status}")
            init = re.search(r'#EXT-X-MAP:URI="([^"]+)"', playlist)
            segment = next((line for line in playlist.splitlines() if line and not line.startswith("#")), None)
            for name, uri in (("init segment", init and init.group(1)), ("first segment", segment)):
                if uri:
                    status, data, _ = s.request("GET", urllib.parse.urljoin(variant_url, uri), timeout=180)
                    self.check(f"converted play: {name}", status == 200 and len(data) > 0, f"HTTP {status}")
                else:
                    self.check(f"converted play: {name}", False, "not in the variant playlist")
        else:
            self.check("converted play: variant playlist", False, "no variant in the master playlist")
        rendition = re.search(r'#EXT-X-MEDIA:TYPE=SUBTITLES[^\n]*URI="([^"]+)"', master)
        if subtitles is None:
            self.skip("subtitles: in the HLS stream", "the test video has no subtitles")
        elif not rendition:
            self.check("subtitles: in the HLS stream", False, "no subtitle rendition in the master playlist")
        else:
            subtitles_url = urllib.parse.urljoin(master_url, rendition.group(1))
            status, playlist, _ = s.request("GET", subtitles_url)
            self.check("subtitles: playlist", status == 200, f"HTTP {status}")
            cue = next((line for line in playlist.decode(errors="replace").splitlines()
                        if line and not line.startswith("#")), None)
            if cue:
                status, data, _ = s.request("GET", urllib.parse.urljoin(subtitles_url, cue))
                self.check("subtitles: WebVTT", status == 200 and data.startswith(b"WEBVTT"), f"HTTP {status}")
        self.stop_encoding(session, header)

    def check_downloads(self, item_id, source, source_id, user, header, quoted):
        s = self.server
        status, _, _ = s.request("GET", f"/Items/{item_id}/Download", headers={**quoted, "Range": "bytes=0-1023"},
                                 limit=1024)
        self.check("downloads: original file, with the header", status in (200, 206), f"HTTP {status}")
        profile = {
            "MaxStreamingBitrate": 400_000,
            "DirectPlayProfiles": [],
            "TranscodingProfiles": [{"Container": "mp4", "Type": "Video", "VideoCodec": "h264", "AudioCodec": "aac",
                                     "Protocol": "http", "Context": "Streaming"}],
            "SubtitleProfiles": [{"Format": "vtt", "Method": "External"}],
        }
        status, address, session = self.playback_info(item_id, source_id, user, header, profile, None)
        if not address:
            self.check("downloads: converted file", False, f"no conversion address (HTTP {status})")
            return
        # DownloadPlanner.addressWithoutToken: the token goes in the header, never in a saved address.
        parts = urllib.parse.urlsplit(address)
        kept = [(k, v) for k, v in urllib.parse.parse_qsl(parts.query, keep_blank_values=True)
                if k.lower() not in ("api_key", "apikey")]
        address = urllib.parse.urlunsplit(parts._replace(query=urllib.parse.urlencode(kept)))
        status, data, _ = s.request("GET", address, headers=quoted, limit=1024, timeout=180)
        self.check("downloads: converted file, token in the header only", status in (200, 206) and data,
                   f"HTTP {status}")
        self.stop_encoding(session, header)

    def check_progress_and_played(self, item_id, source_id, user, header):
        s = self.server
        report = {"ItemId": item_id, "MediaSourceId": source_id, "PositionTicks": 100_000_000, "CanSeek": True,
                  "PlayMethod": "DirectPlay", "PlaySessionId": "server-check"}
        for name, path in (("start", "/Sessions/Playing"), ("progress", "/Sessions/Playing/Progress"),
                           ("stop", "/Sessions/Playing/Stopped")):
            status, _, _ = s.request("POST", path, headers=header, body=report)
            self.check(f"playback report: {name}", status in (200, 204), f"HTTP {status}")
        status, _, _ = s.request("POST", f"/UserPlayedItems/{item_id}?userId={user}", headers=header)
        self.check("mark played", status == 200, f"HTTP {status}")
        status, _, _ = s.request("DELETE", f"/UserPlayedItems/{item_id}?userId={user}", headers=header)
        self.check("mark unplayed", status == 200, f"HTTP {status}")

    def check_quick_connect(self, user):
        s = self.server
        device = {"Authorization": sdk_authorization(device_id="serafin-server-check-quick-connect")}
        status, enabled = s.json("GET", "/QuickConnect/Enabled", headers=device)
        self.check("quick connect: enabled", status == 200 and enabled is True, f"HTTP {status} {enabled}")
        status, started = s.json("POST", "/QuickConnect/Initiate", headers=device)
        self.check("quick connect: code, with the header and no token", status == 200 and bool(started),
                   f"HTTP {status}")
        if status != 200 or not started:
            return
        status, _, _ = s.request("POST", f"/QuickConnect/Authorize?code={started['Code']}&userId={user}",
                                 headers=self.admin)
        self.check("quick connect: approved from another session", status == 200, f"HTTP {status}")
        status, state = s.json("GET", f"/QuickConnect/Connect?secret={started['Secret']}", headers=device)
        self.check("quick connect: approval seen", status == 200 and (state or {}).get("Authenticated") is True,
                   f"HTTP {status}")
        status, signed_in = s.json("POST", "/Users/AuthenticateWithQuickConnect", headers=device,
                                   body={"Secret": started["Secret"]})
        self.check("quick connect: signed in", status == 200 and bool((signed_in or {}).get("AccessToken")),
                   f"HTTP {status}")

    def record_legacy_forms(self, token):
        """How the server answers the forms Serafin doesn't send, so the results show what the setting refused."""
        s = self.server
        forms = {
            "X-Emby-Token header": ("/Users/Me", {"X-Emby-Token": token}),
            "X-MediaBrowser-Token header": ("/Users/Me", {"X-MediaBrowser-Token": token}),
            "X-Emby-Authorization header": ("/Users/Me", {"X-Emby-Authorization": authorization(token)}),
            "Emby scheme in Authorization": ("/Users/Me", {"Authorization": authorization(token, scheme="Emby")}),
            "api_key query": (f"/Users/Me?api_key={token}", {}),
        }
        self.legacy_forms = {
            name: s.request("GET", path, headers=headers)[0] for name, (path, headers) in forms.items()}

    def stop_encoding(self, session, header):
        if session:
            self.server.request(
                "DELETE", f"/Videos/ActiveEncodings?deviceId={DEVICE_ID}&playSessionId={session}", headers=header)


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("url", help="the server's address, such as http://127.0.0.1:8096")
    parser.add_argument("--setup", action="store_true",
                        help="set up a fresh server and run the live check too; never use on a server anyone uses")
    parser.add_argument("--sdk", type=pathlib.Path, default=DEFAULT_SDK,
                        help="a checkout of jellyfin-sdk-swift at the revision Package.resolved pins, fetched there "
                             "when the folder doesn't exist")
    parser.add_argument("--strict", action="store_true", help="count a skipped live check as a failure")
    arguments = parser.parse_args()

    server = Server(arguments.url)
    check_sdk_checkout(arguments.sdk)
    status, info = server.json("GET", "/System/Info/Public")
    if status != 200 or not isinstance(info, dict):
        sys.exit(f"{arguments.url} didn't answer /System/Info/Public (HTTP {status}).")
    failed = False

    live = None
    if arguments.setup:
        live = Live(server)
        live.set_up()
    status, info = server.json("GET", "/System/Info/Public")
    print(f"Jellyfin {info.get('Version')} at {arguments.url}, SDK {sdk_revision()[:7]}")

    problems, notes = api_check(server, arguments.sdk)
    print("\nAPI check")
    for problem in problems:
        print(f"  FAIL {problem}")
    for note in notes:
        print(f"  note {note}")
    failed |= bool(problems)

    if live:
        live.run()
        print(f"\nLive check (legacy authorization: {live.legacy})")
        for name, outcome, detail in live.results:
            print(f"  {outcome:4} {name}" + (f" ({detail})" if outcome != "pass" and detail else ""))
        print("  The forms Serafin doesn't send: " + ", ".join(
            f"{name} {code}" for name, code in live.legacy_forms.items()))
        print("  With no token at all: " + ", ".join(f"{name} {code}" for name, code in live.tokenless.items()))
        failed |= any(outcome == "FAIL" or (arguments.strict and outcome == "skip") for _, outcome, _ in live.results)

    print("\nFailed." if failed else "\nPassed.")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
