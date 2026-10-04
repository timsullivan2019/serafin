import Testing
import os

@testable import SerafinCore

@Suite struct LoggingTests {
    @Test func subsystemIsTheBundleIdentifier() {
        #expect(Logger.serafinSubsystem == "app.getserafin.serafin")
    }
}
