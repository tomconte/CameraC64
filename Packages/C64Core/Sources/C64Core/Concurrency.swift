import Foundation

/// Values that worker threads may share, each touching only its own part.
struct Shared<Value>: @unchecked Sendable {
    let value: Value

    init(_ value: Value) {
        self.value = value
    }
}

/// Runs `body` once for each index below `count`, spread over the
/// processor's cores.
func concurrently(_ count: Int, _ body: @Sendable (Int) -> Void) {
    DispatchQueue.concurrentPerform(iterations: count, execute: body)
}

/// Runs `body` for consecutive ranges of `0..<count`, spread over the
/// processor's cores.
func concurrently(_ count: Int, inChunksOf size: Int, _ body: @Sendable (Range<Int>) -> Void) {
    concurrently((count + size - 1) / size) { chunk in
        body(chunk * size..<min((chunk + 1) * size, count))
    }
}
