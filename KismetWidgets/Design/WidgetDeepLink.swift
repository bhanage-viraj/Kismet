import Foundation

enum WidgetDeepLink {
	static let scheme = "kismet"

	static func friend(_ friendID: String) -> URL {
		URL(string: "\(scheme)://friend/\(friendID)")!
	}

	static var meetup: URL {
		URL(string: "\(scheme)://meetup")!
	}

	static var home: URL {
		URL(string: "\(scheme)://home")!
	}
}
