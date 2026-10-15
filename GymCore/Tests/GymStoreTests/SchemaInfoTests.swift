import Testing
@testable import GymStore

@Test func schemaVersionIsPositive() {
    #expect(GymSchema.currentVersion >= 1)
}
