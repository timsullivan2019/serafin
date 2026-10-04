import Foundation
import Testing

@testable import SerafinCore

@Suite struct InMemorySecretStoreTests {
    @Test func savesReadsAndDeletesValues() {
        let store = InMemorySecretStore()
        #expect(store.get("token") == nil)
        store.set("abc", for: "token")
        #expect(store.get("token") == "abc")
        store.set("def", for: "token")
        #expect(store.get("token") == "def")
        store.delete("token")
        #expect(store.get("token") == nil)
        store.delete("token")
    }
}
