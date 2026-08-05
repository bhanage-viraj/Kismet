import Foundation
import UIKit

enum AppGroup {
	static let suiteName = "group.bhanageviraj.indeKismet"
	static let suggestionSnapshotKey = "suggestionSnapshot"
	static let openPulseKey = "openPulseSnapshot"
	static let pendingAcceptPulseBlobIdKey = "pendingAcceptPulseBlobId"
	static let widgetKind = "FriendAvailabilityWidget"
	static let meetupWidgetKind = "SuggestedMeetupWidget"
	static let mapWidgetKind = "FriendsMapLargeWidget"
	static let schemaVersion = 1
	/// Widgets treat snapshots older than this as empty.
	static let staleInterval: TimeInterval = 2 * 60 * 60
	static let avatarsDirectoryName = "avatars"

	static var defaults: UserDefaults? {
		UserDefaults(suiteName: suiteName)
	}

	static var containerURL: URL? {
		FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: suiteName)
	}

	static var avatarsDirectoryURL: URL? {
		guard let containerURL else { return nil }
		return containerURL.appendingPathComponent(avatarsDirectoryName, isDirectory: true)
	}

	enum WidgetStatus: String, Codable, Sendable {
		case free
		case busy
		case nearby
	}

	struct FeaturedMeetup: Codable, Sendable, Equatable {
		var title: String
		var venueName: String?
		var etaText: String?
		var distanceText: String?
		var whenText: String?
		var systemImage: String
	}

	/// Newest active incoming Pulse for interactive widgets.
	struct OpenPulse: Codable, Sendable, Equatable {
		var blobId: String
		var senderUserId: String
		var senderDisplayName: String
		var emoji: String
		var label: String
		var venueName: String?
		var expiresAt: Date
		var pulseId: String
	}

	struct Card: Codable, Identifiable, Sendable, Equatable {
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

	struct SuggestionSnapshot: Codable, Sendable, Equatable {
		var schemaVersion: Int
		var updatedAt: Date
		var headline: String
		var friendCountNearby: Int
		var cards: [Card]
		var featuredMeetup: FeaturedMeetup?
		/// Approximate user location for the map widget (optional for older snapshots).
		var userLatitude: Double? = nil
		var userLongitude: Double? = nil

		var isStale: Bool {
			Date().timeIntervalSince(updatedAt) > AppGroup.staleInterval
		}

		var containsMockData: Bool {
			cards.contains { AppGroup.isMockFriendID($0.id) || AppGroup.isMockFriendID($0.friendID) }
		}
	}

	static func saveSnapshot(_ snapshot: SuggestionSnapshot) {
		guard let defaults else { return }
		guard let data = try? JSONEncoder().encode(snapshot) else { return }
		defaults.set(data, forKey: suggestionSnapshotKey)
	}

	static func clearSnapshot() {
		defaults?.removeObject(forKey: suggestionSnapshotKey)
		clearAvatars()
	}

	static func loadSnapshot() -> SuggestionSnapshot? {
		guard let data = defaults?.data(forKey: suggestionSnapshotKey) else { return nil }
		guard let snapshot = try? JSONDecoder().decode(SuggestionSnapshot.self, from: data) else {
			return nil
		}
		if snapshot.containsMockData {
			clearSnapshot()
			clearCachedMapImage()
			return nil
		}
		return snapshot
	}

	static func saveOpenPulse(_ pulse: OpenPulse?) {
		guard let defaults else { return }
		guard let pulse else {
			defaults.removeObject(forKey: openPulseKey)
			return
		}
		guard let data = try? JSONEncoder().encode(pulse) else { return }
		defaults.set(data, forKey: openPulseKey)
	}

	static func loadOpenPulse() -> OpenPulse? {
		guard let data = defaults?.data(forKey: openPulseKey) else { return nil }
		guard let pulse = try? JSONDecoder().decode(OpenPulse.self, from: data) else { return nil }
		guard pulse.expiresAt > Date() else {
			saveOpenPulse(nil)
			return nil
		}
		return pulse
	}

	static var pendingAcceptPulseBlobId: String? {
		get { defaults?.string(forKey: pendingAcceptPulseBlobIdKey) }
		set {
			if let newValue {
				defaults?.set(newValue, forKey: pendingAcceptPulseBlobIdKey)
			} else {
				defaults?.removeObject(forKey: pendingAcceptPulseBlobIdKey)
			}
		}
	}

	/// Preview hosts and MockFriendsProvider use `preview-` / `mock-` IDs.
	static func isMockFriendID(_ id: String) -> Bool {
		id.hasPrefix("preview-") || id.hasPrefix("mock-")
	}

	// MARK: - Avatar files

	static func avatarFileURL(fileName: String) -> URL? {
		avatarsDirectoryURL?.appendingPathComponent(fileName, isDirectory: false)
	}

	@discardableResult
	static func writeAvatar(friendID: String, imageData: Data) -> String? {
		guard let directory = avatarsDirectoryURL else { return nil }
		do {
			try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
			let fileName = sanitizedAvatarFileName(for: friendID)
			let url = directory.appendingPathComponent(fileName, isDirectory: false)
			try imageData.write(to: url, options: .atomic)
			return fileName
		} catch {
			return nil
		}
	}

	static func loadAvatarImage(fileName: String?) -> UIImage? {
		guard let fileName, !fileName.isEmpty,
		      let url = avatarFileURL(fileName: fileName)
		else { return nil }
		return UIImage(contentsOfFile: url.path)
	}

	/// Loads a cached avatar written for a friend / user id (same naming as snapshot writer).
	static func loadAvatarImage(friendID: String) -> UIImage? {
		loadAvatarImage(fileName: sanitizedAvatarFileName(for: friendID))
	}

	static func clearAvatars() {
		guard let directory = avatarsDirectoryURL else { return }
		try? FileManager.default.removeItem(at: directory)
	}

	static func pruneAvatars(keeping fileNames: Set<String>) {
		guard let directory = avatarsDirectoryURL else { return }
		guard let contents = try? FileManager.default.contentsOfDirectory(
			at: directory,
			includingPropertiesForKeys: nil
		) else { return }

		for url in contents {
			if !fileNames.contains(url.lastPathComponent) {
				try? FileManager.default.removeItem(at: url)
			}
		}
	}

	private static func sanitizedAvatarFileName(for friendID: String) -> String {
		let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
		let cleaned = friendID.unicodeScalars.map { allowed.contains($0) ? Character($0) : "_" }
		let base = String(cleaned)
		return "\(base.isEmpty ? "friend" : base).jpg"
	}

	// MARK: - Friends Map snapshot cache

	private static let mapSnapshotLargeFileName = "friendsMapSnapshotLarge.jpg"
	private static let mapSnapshotMediumFileName = "friendsMapSnapshotMedium.jpg"
	private static let mapSnapshotLegacyFileName = "friendsMapSnapshot.jpg"

	enum MapSnapshotSize {
		case large
		case medium

		var fileName: String {
			switch self {
			case .large: mapSnapshotLargeFileName
			case .medium: mapSnapshotMediumFileName
			}
		}

		var pointSize: CGSize {
			switch self {
			case .large: CGSize(width: 338, height: 354)
			case .medium: CGSize(width: 338, height: 169)
			}
		}
	}

	static func mapSnapshotFileURL(for size: MapSnapshotSize) -> URL? {
		containerURL?.appendingPathComponent(size.fileName, isDirectory: false)
	}

	static func saveCachedMapImage(_ image: UIImage, size: MapSnapshotSize = .large) {
		guard let url = mapSnapshotFileURL(for: size),
		      let data = image.jpegData(compressionQuality: 0.9)
		else { return }
		try? data.write(to: url, options: .atomic)
	}

	static func loadCachedMapImage(size: MapSnapshotSize = .large) -> UIImage? {
		if let url = mapSnapshotFileURL(for: size),
		   FileManager.default.fileExists(atPath: url.path),
		   let image = UIImage(contentsOfFile: url.path) {
			return image
		}
		guard let legacy = containerURL?.appendingPathComponent(mapSnapshotLegacyFileName, isDirectory: false),
		      FileManager.default.fileExists(atPath: legacy.path)
		else { return nil }
		return UIImage(contentsOfFile: legacy.path)
	}

	static func loadCachedMapImage() -> UIImage? {
		loadCachedMapImage(size: .large)
	}

	static func clearCachedMapImage() {
		for size in [MapSnapshotSize.large, .medium] {
			if let url = mapSnapshotFileURL(for: size) {
				try? FileManager.default.removeItem(at: url)
			}
		}
		if let legacy = containerURL?.appendingPathComponent(mapSnapshotLegacyFileName, isDirectory: false) {
			try? FileManager.default.removeItem(at: legacy)
		}
	}
}
