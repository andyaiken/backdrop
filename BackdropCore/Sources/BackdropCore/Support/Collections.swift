import Foundation

extension ClosedRange where Bound == Int {
    /// The nearest value in the range.
    func clamp(_ v: Int) -> Int { Swift.min(Swift.max(v, lowerBound), upperBound) }
}

extension Array {
    /// The element at `index`, or nil past either end.
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
