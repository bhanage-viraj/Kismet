import Foundation

enum AppGroup {
	static let suiteName = "group.sanjivanand.kismet"
	static let suggestionSnapshotKey = "suggestionSnapshot"

	static var defaults: UserDefaults? {
		UserDefaults(suiteName: suiteName)
	}
}
