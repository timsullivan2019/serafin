import Foundation
import JellyfinAPI
import Testing

@testable import SerafinCore

/// A store in a folder of its own.
private func makeStore() -> (store: HomeSnapshotStore, directory: URL) {
    let directory = URL.temporaryDirectory.appending(
        path: "serafin-home-\(UUID().uuidString)", directoryHint: .isDirectory)
    return (HomeSnapshotStore(directory: directory), directory)
}

/// A Home with one library whose newest items, and Continue Watching, are `titles`.
private func home(_ titles: String..., date: Date = Date(timeIntervalSince1970: 1_790_000_000)) -> HomeSnapshot {
    let items = titles.enumerated().map { BaseItemDto(id: "movie-\($0.offset)", name: $0.element, type: .movie) }
    return HomeSnapshot(
        date: date,
        libraries: [BaseItemDto(collectionType: .movies, id: "movies", name: "Movies")],
        resume: items,
        nextUp: [],
        latest: ["movies": items]
    )
}

private let alice = SessionKey(serverID: "server-1", userID: "alice")
private let bob = SessionKey(serverID: "server-1", userID: "bob")

@Suite struct HomeSnapshotStoreTests {
    @Test func eachAccountGetsBackItsOwnHome() async {
        let (store, _) = makeStore()
        await store.save(home("Metropolis"), for: alice)
        await store.save(home("Nosferatu"), for: bob)
        #expect(await store.snapshot(for: alice) == home("Metropolis"))
        #expect(await store.snapshot(for: bob)?.resume.map(\.name) == ["Nosferatu"])
        #expect(await store.snapshot(for: SessionKey(serverID: "server-2", userID: "alice")) == nil)
    }

    @Test func aNewerHomeTakesTheOldOnesPlace() async {
        let (store, _) = makeStore()
        await store.save(home("Metropolis"), for: alice)
        await store.save(home("Sherlock Jr.", date: Date(timeIntervalSince1970: 1_790_003_600)), for: alice)
        let saved = await store.snapshot(for: alice)
        #expect(saved?.resume.map(\.name) == ["Sherlock Jr."])
        #expect(saved?.date == Date(timeIntervalSince1970: 1_790_003_600))
    }

    @Test func removingOneAccountsHomeKeepsTheOthers() async {
        let (store, _) = makeStore()
        await store.save(home("Metropolis"), for: alice)
        await store.save(home("Nosferatu"), for: bob)
        await store.remove(for: alice)
        #expect(await store.snapshot(for: alice) == nil)
        #expect(await store.snapshot(for: bob) != nil)
    }

    @Test func clearingRemovesEveryAccountsHome() async {
        let (store, directory) = makeStore()
        await store.save(home("Metropolis"), for: alice)
        await store.save(home("Nosferatu"), for: bob)
        await store.removeAll()
        #expect(await store.snapshot(for: alice) == nil)
        #expect(await store.snapshot(for: bob) == nil)
        #expect(!FileManager.default.fileExists(atPath: directory.path(percentEncoded: false)))
        // Saving afterwards starts the folder again.
        await store.save(home("Metropolis"), for: alice)
        #expect(await store.snapshot(for: alice) != nil)
    }

    @Test func aDamagedFileIsDeletedAndIgnored() async throws {
        let (store, directory) = makeStore()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = await store.fileURL(for: alice)
        try Data("{\"version\":1,\"home\":".utf8).write(to: url)
        #expect(await store.snapshot(for: alice) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func aFileFromAnotherVersionIsDeletedAndIgnored() async throws {
        let (store, _) = makeStore()
        await store.save(home("Metropolis"), for: alice)
        let url = await store.fileURL(for: alice)
        var file = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        file["version"] = HomeSnapshotStore.currentVersion + 1
        try JSONSerialization.data(withJSONObject: file).write(to: url)
        #expect(await store.snapshot(for: alice) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func anOversizedFileIsNeverRead() async throws {
        let (store, directory) = makeStore()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = await store.fileURL(for: alice)
        try Data(count: HomeSnapshotStore.maximumFileSize + 1).write(to: url)
        #expect(await store.snapshot(for: alice) == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
    }

    @Test func aFileThatCantBeReadNowIsKeptForLater() async throws {
        let (store, _) = makeStore()
        await store.save(home("Metropolis"), for: alice)
        let path = await store.fileURL(for: alice).path(percentEncoded: false)
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: path)
        #expect(await store.snapshot(for: alice) == nil)
        #expect(FileManager.default.fileExists(atPath: path))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path)
        #expect(await store.snapshot(for: alice) == home("Metropolis"))
    }

    @Test func fileNamesSayNothingAboutTheAccountAndStayInTheFolder() async {
        let (store, directory) = makeStore()
        let url = await store.fileURL(for: SessionKey(serverID: "../../Escape", userID: "alice"))
        #expect(url.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL)
        #expect(url.lastPathComponent.wholeMatch(of: /[0-9a-f]{64}\.json/) != nil)
    }

    @Test func noTwoAccountsShareAFile() async {
        let (store, _) = makeStore()
        let first = await store.fileURL(for: SessionKey(serverID: "ab", userID: "c"))
        let second = await store.fileURL(for: SessionKey(serverID: "a", userID: "bc"))
        #expect(first != second)
    }
}

@Suite struct LibraryHomeSnapshotTests {
    private let showsView = "a656b907eb3a73532e40e44b968d0225"
    private let everythingView = "0c41907140d802bb58430fed7e2cd79e"

    /// Stubs everything Home asks `host` for. The Shows library's newest items fail to load.
    private func stubHome(on host: String) throws {
        StubURLProtocol.stub("\(host):443", path: "/UserViews", .json(200, try Fixture.json("UserViews")))
        StubURLProtocol.stub("\(host):443", path: "/UserItems/Resume", .json(200, try Fixture.json("Resume")))
        StubURLProtocol.stub("\(host):443", path: "/Shows/NextUp", .json(200, try Fixture.json("NextUp")))
        StubURLProtocol.stub(
            "\(host):443", path: "/Items/Latest", query: ["parentId": moviesView],
            .json(200, try Fixture.json("Latest")))
        StubURLProtocol.stub(
            "\(host):443", path: "/Items/Latest", query: ["parentId": showsView], .failure(.timedOut))
        StubURLProtocol.stub(
            "\(host):443", path: "/Items/Latest", query: ["parentId": everythingView], .json(200, "[]"))
    }

    @Test func homeIsKeptOnTheDeviceForWhenTheServerCantBeReached() async throws {
        let host = "home-kept.example.com"
        try stubHome(on: host)
        let (store, _) = makeStore()
        let library = try library(on: host, homeSnapshots: HomeSnapshotStore.Slot(store: store, account: alice))
        #expect(await library.savedHome() == nil)

        let fresh = try await library.home()
        #expect(fresh.libraries.map(\.name) == ["Movies", "Shows", "Everything"])
        #expect(fresh.resume.map(\.name) == ["Night of the Living Dead", "The Red-Headed League"])
        #expect(fresh.nextUp.map(\.name) == ["A Scandal in Bohemia"])
        #expect(fresh.latest[moviesView]?.map(\.name) == ["Nosferatu", "Sherlock Holmes"])
        #expect(await library.savedHome() == fresh)

        StubURLProtocol.stub("\(host):443", path: "/UserItems/Resume", .failure(.notConnectedToInternet))
        await library.clearCache()
        await #expect(throws: SerafinError.offline) { try await library.home() }
        #expect(await library.savedHome() == fresh)
    }

    @Test func oneLibraryFailingLeavesTheOtherRows() async throws {
        let host = "home-one-row-fails.example.com"
        try stubHome(on: host)
        let home = try await library(on: host).home()
        #expect(home.latest[moviesView]?.count == 2)
        #expect(home.latest[showsView] == [])
        #expect(home.latest[everythingView] == [])
    }

    @Test func aLibraryWithoutAPlaceToKeepHomeStillLoadsIt() async throws {
        let host = "home-not-kept.example.com"
        try stubHome(on: host)
        let library = try library(on: host)
        _ = try await library.home()
        #expect(await library.savedHome() == nil)
    }
}

@Suite struct NetworkFailureTests {
    @Test func noConnectionAtAllIsOffline() {
        for code in [URLError.Code.notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff] {
            #expect(SerafinError.translating(URLError(code)) as? SerafinError == .offline)
        }
    }

    @Test func aServerThatDoesntAnswerIsUnreachable() {
        for code in [URLError.Code.timedOut, .cannotConnectToHost, .cannotFindHost, .networkConnectionLost] {
            #expect(SerafinError.translating(URLError(code)) as? SerafinError == .serverUnreachable)
        }
        let blocked = SerafinError.translating(URLError(.appTransportSecurityRequiresSecureConnection))
        #expect(blocked as? SerafinError == .plainHTTPBlocked)
    }
}
