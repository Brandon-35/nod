import Testing
@testable import NodCore

@Suite struct NodInfoTests {
    @Test func bundleIDMatchesDecision() {
        #expect(NodInfo.bundleID == "com.brandonta.nod")
    }

    @Test func v1HasFourGestures() {
        #expect(NodInfo.gestureCount == 4)
    }
}
