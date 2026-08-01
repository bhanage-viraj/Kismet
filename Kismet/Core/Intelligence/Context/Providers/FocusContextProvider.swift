import Foundation

/// Focus filters (SetFocusFilterIntent) can later flip `blocksSocial`.
/// Default is permissive so the demo loop isn't blocked without a Focus filter installed.
struct FocusContextProvider: ContextProviding {
	private let blocksSocial: Bool

	init(blocksSocial: Bool = false) {
		self.blocksSocial = blocksSocial
	}

	func current() async -> FocusSlice {
		FocusSlice(blocksSocial: blocksSocial, label: blocksSocial ? "Focus" : nil)
	}
}
