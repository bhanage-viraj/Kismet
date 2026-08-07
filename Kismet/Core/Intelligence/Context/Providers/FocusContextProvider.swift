import Foundation

/// Reads the Focus filter App Group flag set by `KismetFocusFilterIntent`.
struct FocusContextProvider: ContextProviding {
	func current() async -> FocusSlice {
		let blocks = FocusSocialGate.blocksSocial
		return FocusSlice(blocksSocial: blocks, label: blocks ? FocusSocialGate.label : nil)
	}
}
