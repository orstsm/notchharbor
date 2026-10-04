import Foundation

/// Invalidates delayed permission/configuration work when a surface goes away.
final class PreviewActivation: @unchecked Sendable {
    private let lock = NSLock()
    private var generation = 0
    func invalidate() -> Int {
        lock.lock(); defer { lock.unlock() }
        generation += 1
        return generation
    }
    func isCurrent(_ token: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return token == generation
    }
}
