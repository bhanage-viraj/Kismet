import CoreLocation
import Foundation
import WidgetKit

enum SuggestionSnapshotWriter {
	private static let mapSnapshotMinInterval: TimeInterval = 45
	private static var lastMapSnapshotAt: Date?

	static func persist(
		cards: [SuggestionCard],
		updatedAt: Date = Date(),
		userCoordinate: CLLocationCoordinate2D? = nil
	) {
		// Never write Xcode-preview / MockFriendsProvider seeds into the App Group.
		let realCards = cards.filter {
			!AppGroup.isMockFriendID($0.id) && !AppGroup.isMockFriendID($0.friendID)
		}

		let snapshot = makeSnapshot(
			from: realCards,
			updatedAt: updatedAt,
			userCoordinate: userCoordinate
		)
		AppGroup.saveSnapshot(snapshot)
		// Availability / meetup can update immediately; map waits until MapKit finishes.
		reloadListWidgets()
		let shouldRenderMap: Bool = {
			guard let lastMapSnapshotAt else { return true }
			return Date().timeIntervalSince(lastMapSnapshotAt) >= mapSnapshotMinInterval
		}()
		if shouldRenderMap {
			lastMapSnapshotAt = Date()
			Task {
				await WidgetMapSnapshotRenderer.refresh(from: snapshot)
			}
		}
	}

	static func clear() {
		AppGroup.clearSnapshot()
		AppGroup.clearCachedMapImage()
		reloadListWidgets()
		WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.mapWidgetKind)
	}

	/// Warm an empty / location-only map for the Friends Map widget.
	static func persistEmptyMap(userCoordinate: CLLocationCoordinate2D?) async {
		let snapshot = makeSnapshot(from: [], userCoordinate: userCoordinate)
		AppGroup.saveSnapshot(snapshot)
		reloadListWidgets()
		await WidgetMapSnapshotRenderer.refresh(from: snapshot)
	}

	static func makeSnapshot(
		from cards: [SuggestionCard],
		updatedAt: Date = Date(),
		userCoordinate: CLLocationCoordinate2D? = nil
	) -> AppGroup.SuggestionSnapshot {
		let widgetCards = cards.map(mapCard)
		let keptAvatars = Set(widgetCards.compactMap(\.avatarFileName))
		AppGroup.pruneAvatars(keeping: keptAvatars)

		let freeCount = widgetCards.filter { $0.status == .free }.count
		let headline: String = {
			if widgetCards.isEmpty { return "No friends nearby" }
			if freeCount > 0 {
				return freeCount == 1 ? "1 friend free nearby" : "\(freeCount) friends free nearby"
			}
			return widgetCards.count == 1
				? "1 friend nearby"
				: "\(widgetCards.count) friends nearby"
		}()

		let origin = resolvedUserCoordinate(from: cards, override: userCoordinate)

		return AppGroup.SuggestionSnapshot(
			schemaVersion: AppGroup.schemaVersion,
			updatedAt: updatedAt,
			headline: headline,
			friendCountNearby: widgetCards.count,
			cards: widgetCards,
			featuredMeetup: featuredMeetup(from: cards.first),
			userLatitude: origin?.latitude,
			userLongitude: origin?.longitude
		)
	}

	private static func mapCard(_ card: SuggestionCard) -> AppGroup.Card {
		let status = widgetStatus(for: card.presence)
		let freeUntilText = extractFreeUntilText(from: card)
		let statusLabel = makeStatusLabel(status: status, freeUntilText: freeUntilText, reason: card.reason)
		let avatarFileName: String? = {
			guard let data = card.avatarImageData, !data.isEmpty else { return nil }
			return AppGroup.writeAvatar(friendID: card.friendID, imageData: data)
		}()

		return AppGroup.Card(
			id: card.id,
			friendID: card.friendID,
			displayName: card.displayName,
			initials: initials(for: card.displayName),
			status: status,
			statusLabel: statusLabel,
			distanceText: card.formattedDistance,
			reason: card.reason,
			ctaTitle: card.ctaTitle,
			venueName: card.venueName,
			freeUntilText: freeUntilText,
			avatarFileName: avatarFileName,
			latitude: card.coordinate.latitude,
			longitude: card.coordinate.longitude
		)
	}

	/// Prefer an explicit user fix; else friend centroid; else nil (renderer uses its own fallback).
	private static func resolvedUserCoordinate(
		from cards: [SuggestionCard],
		override: CLLocationCoordinate2D?
	) -> CLLocationCoordinate2D? {
		if let override { return override }
		guard !cards.isEmpty else { return nil }
		let lat = cards.map(\.coordinate.latitude).reduce(0, +) / Double(cards.count)
		let lon = cards.map(\.coordinate.longitude).reduce(0, +) / Double(cards.count)
		return CLLocationCoordinate2D(latitude: lat, longitude: lon)
	}

	private static func widgetStatus(for presence: PresenceState) -> AppGroup.WidgetStatus {
		switch presence {
		case .available: .free
		case .friendsOnly: .busy
		case .approximate: .nearby
		case .eclipse: .nearby
		}
	}

	private static func extractFreeUntilText(from card: SuggestionCard) -> String? {
		if let chip = card.factChips.first(where: { $0.localizedCaseInsensitiveContains("Free until") }) {
			return chip
		}
		if card.reason.localizedCaseInsensitiveContains("Free until") {
			return card.reason
		}
		if card.factChips.contains(where: { $0.localizedCaseInsensitiveContains("Free right now") }) {
			return "Free right now"
		}
		return nil
	}

	private static func makeStatusLabel(
		status: AppGroup.WidgetStatus,
		freeUntilText: String?,
		reason: String
	) -> String {
		if let freeUntilText, !freeUntilText.isEmpty {
			return freeUntilText
		}
		switch status {
		case .free:
			return reason.isEmpty ? "Free nearby" : reason
		case .busy:
			return reason.isEmpty ? "Working nearby" : reason
		case .nearby:
			return reason.isEmpty ? "Nearby" : reason
		}
	}

	private static func featuredMeetup(from top: SuggestionCard?) -> AppGroup.FeaturedMeetup? {
		guard let top else { return nil }
		let hasVenue = !(top.venueName?.isEmpty ?? true)
		let hasCTA = !top.ctaTitle.isEmpty
		guard hasVenue || hasCTA else { return nil }

		let title: String = {
			if hasVenue, let venue = top.venueName {
				return top.ctaTitle.isEmpty ? "Meet at \(venue)" : top.ctaTitle
			}
			return top.ctaTitle
		}()

		let etaText: String? = {
			guard let minutes = top.venueETAMinutes, minutes > 0 else { return nil }
			return "\(minutes) min"
		}()

		return AppGroup.FeaturedMeetup(
			title: title,
			venueName: top.venueName,
			etaText: etaText,
			distanceText: top.formattedDistance,
			whenText: nil,
			systemImage: hasVenue ? "cup.and.saucer.fill" : "wave.3.right"
		)
	}

	private static func initials(for name: String) -> String {
		let parts = name.split(whereSeparator: \.isWhitespace).prefix(2)
		let letters = parts.compactMap { $0.first.map(String.init) }
		let value = letters.joined().uppercased()
		return value.isEmpty ? "?" : value
	}

	private static func reloadListWidgets() {
		WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.widgetKind)
		WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.meetupWidgetKind)
	}
}
