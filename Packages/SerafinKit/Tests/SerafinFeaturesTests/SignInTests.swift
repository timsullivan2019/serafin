import Foundation
import SerafinCore
import Testing

@testable import SerafinFeatures

private func throwawayDefaults() throws -> UserDefaults {
    try #require(UserDefaults(suiteName: "serafin-tests-\(UUID().uuidString)"))
}

private func server(_ id: String) throws -> Server {
    Server(id: id, name: "Living Room", url: try #require(URL(string: "https://\(id).example.com")))
}

@Suite struct LastUsernameTests {
    @Test func eachServerRemembersItsOwnName() throws {
        let defaults = try throwawayDefaults()
        LastUsername.save(" Alice ", forServer: "a", in: defaults)
        LastUsername.save("Bram", forServer: "b", in: defaults)
        LastUsername.save("   ", forServer: "b", in: defaults)
        #expect(LastUsername.name(forServer: "a", in: defaults) == "Alice")
        #expect(LastUsername.name(forServer: "b", in: defaults) == "Bram")
        #expect(LastUsername.name(forServer: "c", in: defaults) == nil)
        LastUsername.forget(server: "a", in: defaults)
        #expect(LastUsername.name(forServer: "a", in: defaults) == nil)
    }
}

@MainActor @Suite struct SignInModelTests {
    @Test func passwordComesFirstWithTheLastNameFilledIn() throws {
        let defaults = try throwawayDefaults()
        LastUsername.save("Alice", forServer: "a", in: defaults)
        let remembered = SignInModel(server: try server("a"), defaults: defaults)
        #expect(remembered.method == .password)
        #expect(remembered.username == "Alice")
        #expect(remembered.canSignIn)
        let fresh = SignInModel(server: try server("b"), defaults: defaults)
        #expect(fresh.username.isEmpty)
        #expect(!fresh.canSignIn)
    }

    @Test func choosingAUserWithAPasswordFillsInTheirNameOnly() async throws {
        let model = SignInModel(server: try server("a"), defaults: try throwawayDefaults())
        model.password = "typed before"
        let user = PublicUser(id: "u1", name: "Alice", imageTag: nil, hasPassword: true)
        let needsPassword = await model.choose(user, with: AppSession.preview())
        #expect(needsPassword)
        #expect(model.username == "Alice")
        #expect(model.password.isEmpty)
        #expect(!model.didSignIn)
    }
}
