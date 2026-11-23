import CoreGraphics
import Testing
@testable import BackdropStage

@Suite("Clamped insets")
struct InsetClampedTests {
    @Test func matchesInsetByWhenThereIsRoom() {
        let r = CGRect(x: 10, y: 20, width: 100, height: 50)
        #expect(r.insetClamped(dx: 1, dy: 2) == r.insetBy(dx: 1, dy: 2))
    }

    @Test func staysFiniteWhenTooSmall() {
        // insetBy gives CGRect.null here, which a view takes as infinity.
        #expect(CGRect.zero.insetBy(dx: 1, dy: 1).isNull)
        #expect(CGRect.zero.insetClamped(dx: 1, dy: 1) == .zero)
        #expect(CGRect(x: 0, y: 0, width: 1, height: 40).insetClamped(dx: 1, dy: 1) == CGRect(x: 0.5, y: 1, width: 0, height: 38))
    }
}
