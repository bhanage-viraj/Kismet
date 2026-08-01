import Foundation

protocol ContextProviding<Snapshot>: Sendable {
	associatedtype Snapshot: Sendable
	func current() async -> Snapshot
}
