import Foundation
import UIKit
import WidgetKit

enum WidgetAppGroup {
	static let suiteName = "group.sanjivanand.kismet"
	static let suggestionSnapshotKey = "suggestionSnapshot"
	static let openPulseKey = "openPulseSnapshot"
	static let pendingAcceptPulseBlobIdKey = "pendingAcceptPulseBlobId"
	static let widgetKind = "FriendAvailabilityWidget"
	static let meetupWidgetKind = "SuggestedMeetupWidget"
	static let mapWidgetKind = "FriendsMapLargeWidget"
	static let schemaVersion = 1
	static let staleInterval: TimeInterval = 2 * 60 * 60
	static let avatarsDirectoryName = "avatars"

	enum WidgetStatus: String, Codable {
		case free
		case busy
		case nearby
	}

	struct FeaturedMeetup: Codable, Equatable {
		var title: String
		var venueName: String?
		var etaText: String?
		var distanceText: String?
		var whenText: String?
		var systemImage: String
	}

	struct OpenPulse: Codable, Equatable {
		var blobId: String
		var senderUserId: String
		var senderDisplayName: String
		var emoji: String
		var label: String
		var venueName: String?
		var expiresAt: Date
		var pulseId: String
	}

	struct Card: Codable, Identifiable, Equatable {
		var id: String
		var friendID: String
		var displayName: String
		var initials: String
		var status: WidgetStatus
		var statusLabel: String
		var distanceText: String
		var reason: String
		var ctaTitle: String
		var venueName: String?
		var freeUntilText: String?
		/// Relative file name under the App Group `avatars/` directory, when a photo exists.
		var avatarFileName: String? = nil
		var latitude: Double? = nil
		var longitude: Double? = nil
	}

	struct SuggestionSnapshot: Codable, Equatable {
		var schemaVersion: Int
		var updatedAt: Date
		var headline: String
		var friendCountNearby: Int
		var cards: [Card]
		var featuredMeetup: FeaturedMeetup?
		var userLatitude: Double? = nil
		var userLongitude: Double? = nil

		var isStale: Bool {
			Date().timeIntervalSince(updatedAt) > WidgetAppGroup.staleInterval
		}

		var containsMockData: Bool {
			cards.contains { WidgetAppGroup.isMockFriendID($0.id) || WidgetAppGroup.isMockFriendID($0.friendID) }
		}
	}

	static var containerURL: URL? {
		FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
	}

	static var avatarsDirectoryURL: URL? {
		guard let containerURL else { return nil }
		return containerURL.appendingPathComponent(avatarsDirectoryName, isDirectory: true)
	}

	static func loadSnapshot() -> SuggestionSnapshot? {
		guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: suggestionSnapshotKey) else {
			return nil
		}
		guard let snapshot = try? JSONDecoder().decode(SuggestionSnapshot.self, from: data) else {
			return nil
		}
		if snapshot.isStale { return nil }
		// Drop leftover Xcode-preview / demo seeds so the Home Screen never shows fake friends.
		if snapshot.containsMockData {
			clearSnapshot()
			clearCachedMapImage()
			return nil
		}
		return snapshot
	}

	/// Preview hosts and MockFriendsProvider use `preview-` / `mock-` IDs.
	static func isMockFriendID(_ id: String) -> Bool {
		id.hasPrefix("preview-") || id.hasPrefix("mock-")
	}

	static func clearSnapshot() {
		UserDefaults(suiteName: suiteName)?.removeObject(forKey: suggestionSnapshotKey)
	}

	static func loadOpenPulse() -> OpenPulse? {
		guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: openPulseKey) else {
			return nil
		}
		guard let pulse = try? JSONDecoder().decode(OpenPulse.self, from: data) else {
			return nil
		}
		guard pulse.expiresAt > Date() else { return nil }
		return pulse
	}

	static var pendingAcceptPulseBlobId: String? {
		get { UserDefaults(suiteName: suiteName)?.string(forKey: pendingAcceptPulseBlobIdKey) }
		set {
			let defaults = UserDefaults(suiteName: suiteName)
			if let newValue {
				defaults?.set(newValue, forKey: pendingAcceptPulseBlobIdKey)
			} else {
				defaults?.removeObject(forKey: pendingAcceptPulseBlobIdKey)
			}
		}
	}

	static func clearCachedMapImage() {
		for name in [
			mapSnapshotLargeFileName,
			mapSnapshotMediumFileName,
			mapSnapshotLegacyFileName,
		] {
			if let url = containerURL?.appendingPathComponent(name, isDirectory: false) {
				try? FileManager.default.removeItem(at: url)
			}
		}
	}

	static func avatarFileURL(fileName: String) -> URL? {
		avatarsDirectoryURL?.appendingPathComponent(fileName, isDirectory: false)
	}

	static func loadAvatarImage(fileName: String?) -> UIImage? {
		guard let fileName, !fileName.isEmpty,
		      let url = avatarFileURL(fileName: fileName)
		else { return nil }
		return UIImage(contentsOfFile: url.path)
	}

	// MARK: - Map snapshot cache (Friends Map widget)

	private static let mapSnapshotLargeFileName = "friendsMapSnapshotLarge.jpg"
	private static let mapSnapshotMediumFileName = "friendsMapSnapshotMedium.jpg"
	/// Legacy single-file cache (pre medium/large split).
	private static let mapSnapshotLegacyFileName = "friendsMapSnapshot.jpg"

	static func mapSnapshotFileURL(for family: WidgetFamily) -> URL? {
		let name: String = {
			switch family {
			case .systemMedium: mapSnapshotMediumFileName
			default: mapSnapshotLargeFileName
			}
		}()
		return containerURL?.appendingPathComponent(name, isDirectory: false)
	}

	static func saveCachedMapImage(_ image: UIImage, for family: WidgetFamily = .systemLarge) {
		guard let url = mapSnapshotFileURL(for: family),
		      let data = image.jpegData(compressionQuality: 0.88)
		else { return }
		try? data.write(to: url, options: .atomic)
	}

	static func loadCachedMapImage(for family: WidgetFamily = .systemLarge) -> UIImage? {
		if let url = mapSnapshotFileURL(for: family),
		   FileManager.default.fileExists(atPath: url.path),
		   let image = UIImage(contentsOfFile: url.path) {
			return image
		}
		// Fall back to legacy filename.
		guard let legacy = containerURL?.appendingPathComponent(mapSnapshotLegacyFileName, isDirectory: false),
		      FileManager.default.fileExists(atPath: legacy.path)
		else { return nil }
		return UIImage(contentsOfFile: legacy.path)
	}

	static func loadCachedMapImage() -> UIImage? {
		loadCachedMapImage(for: .systemLarge)
	}
}
