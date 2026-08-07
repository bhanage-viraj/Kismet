import CoreLocation
import MapKit
import UIKit
import WidgetKit

/// Renders a real MapKit snapshot into the App Group for the Friends Map widget.
/// Must run from the main app (foreground) — WidgetKit extensions often fail to fetch tiles.
enum WidgetMapSnapshotRenderer {
	static let fallbackCoordinate = CLLocationCoordinate2D(latitude: 12.9352, longitude: 77.6245)

	/// Renders medium + large, then reloads the map widget once both writes finish.
	@discardableResult
	static func refresh(from snapshot: AppGroup.SuggestionSnapshot) async -> Bool {
		async let largeOK = render(snapshot: snapshot, size: .large)
		async let mediumOK = render(snapshot: snapshot, size: .medium)
		let (large, medium) = await (largeOK, mediumOK)
		let any = large || medium
		if any {
			await MainActor.run {
				WidgetCenter.shared.reloadTimelines(ofKind: AppGroup.mapWidgetKind)
			}
		}
		return any
	}

	@discardableResult
	private static func render(
		snapshot: AppGroup.SuggestionSnapshot,
		size: AppGroup.MapSnapshotSize
	) async -> Bool {
		await withCheckedContinuation { continuation in
			let options = MKMapSnapshotter.Options()
			options.region = region(for: snapshot)
			options.size = size.pointSize
			options.mapType = .standard
			options.showsBuildings = true
			options.pointOfInterestFilter = .includingAll
			options.traitCollection = UITraitCollection(traitsFrom: [
				UITraitCollection(displayScale: UIScreen.main.scale),
				UITraitCollection(userInterfaceStyle: UITraitCollection.current.userInterfaceStyle),
			])

			if #available(iOS 17.0, *) {
				let config = MKStandardMapConfiguration(elevationStyle: .flat)
				config.pointOfInterestFilter = .includingAll
				options.preferredConfiguration = config
			}

			let snapshotter = MKMapSnapshotter(options: options)
			snapshotter.start(with: .global(qos: .userInitiated)) { mapSnapshot, error in
				guard let mapSnapshot, error == nil else {
					continuation.resume(returning: false)
					return
				}
				let image = compose(mapSnapshot: mapSnapshot, data: snapshot)
				AppGroup.saveCachedMapImage(image, size: size)
				continuation.resume(returning: true)
			}
		}
	}

	// MARK: - Region

	private static func region(for data: AppGroup.SuggestionSnapshot) -> MKCoordinateRegion {
		let user = userCoordinate(from: data)
		var coords: [CLLocationCoordinate2D] = [user]
		for card in data.cards.prefix(4) {
			if let lat = card.latitude, let lon = card.longitude {
				coords.append(CLLocationCoordinate2D(latitude: lat, longitude: lon))
			}
		}

		guard coords.count > 1 else {
			return MKCoordinateRegion(center: user, latitudinalMeters: 1_800, longitudinalMeters: 1_800)
		}

		var minLat = coords[0].latitude
		var maxLat = coords[0].latitude
		var minLon = coords[0].longitude
		var maxLon = coords[0].longitude
		for c in coords.dropFirst() {
			minLat = min(minLat, c.latitude)
			maxLat = max(maxLat, c.latitude)
			minLon = min(minLon, c.longitude)
			maxLon = max(maxLon, c.longitude)
		}

		let center = CLLocationCoordinate2D(
			latitude: (minLat + maxLat) / 2,
			longitude: (minLon + maxLon) / 2
		)

		let latMeters = max(CLLocation(latitude: minLat, longitude: center.longitude)
			.distance(from: CLLocation(latitude: maxLat, longitude: center.longitude)), 400)
		let lonMeters = max(CLLocation(latitude: center.latitude, longitude: minLon)
			.distance(from: CLLocation(latitude: center.latitude, longitude: maxLon)), 400)
		let pad = 1.7
		return MKCoordinateRegion(
			center: center,
			latitudinalMeters: latMeters * pad + 600,
			longitudinalMeters: lonMeters * pad + 600
		)
	}

	private static func userCoordinate(from data: AppGroup.SuggestionSnapshot) -> CLLocationCoordinate2D {
		if let lat = data.userLatitude, let lon = data.userLongitude {
			return CLLocationCoordinate2D(latitude: lat, longitude: lon)
		}
		return fallbackCoordinate
	}

	// MARK: - Compose

	private static func compose(
		mapSnapshot: MKMapSnapshotter.Snapshot,
		data: AppGroup.SuggestionSnapshot
	) -> UIImage {
		let base = mapSnapshot.image
		let format = UIGraphicsImageRendererFormat()
		format.scale = base.scale
		format.opaque = true
		let bounds = CGRect(origin: .zero, size: base.size)
		let renderer = UIGraphicsImageRenderer(size: base.size, format: format)

		return renderer.image { _ in
			base.draw(at: .zero)

			let userPoint = mapSnapshot.point(for: userCoordinate(from: data))
			if bounds.insetBy(dx: -20, dy: -20).contains(userPoint) {
				drawYouMarker(at: userPoint)
			}

			for card in data.cards.prefix(4) {
				guard let lat = card.latitude, let lon = card.longitude else { continue }
				let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lon)
				let point = mapSnapshot.point(for: coordinate)
				guard bounds.insetBy(dx: -36, dy: -48).contains(point) else { continue }
				drawFriendPin(card: card, at: point)
			}
		}
	}

	private static func drawYouMarker(at point: CGPoint) {
		let blue = UIColor.systemBlue
		blue.withAlphaComponent(0.18).setFill()
		UIBezierPath(ovalIn: CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)).fill()
		blue.withAlphaComponent(0.4).setStroke()
		let ring = UIBezierPath(ovalIn: CGRect(x: point.x - 14, y: point.y - 14, width: 28, height: 28))
		ring.lineWidth = 2
		ring.stroke()
		blue.setFill()
		UIBezierPath(ovalIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)).fill()
		UIColor.white.setStroke()
		let core = UIBezierPath(ovalIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12))
		core.lineWidth = 2
		core.stroke()
	}

	private static func drawFriendPin(card: AppGroup.Card, at point: CGPoint) {
		let tint: UIColor = {
			switch card.status {
			case .free: .systemGreen
			case .busy: .systemOrange
			case .nearby: .systemGray
			}
		}()
		let avatarSize: CGFloat = 32
		let tipHeight: CGFloat = 9
		let avatarRect = CGRect(
			x: point.x - avatarSize / 2,
			y: point.y - avatarSize - tipHeight,
			width: avatarSize,
			height: avatarSize
		)

		UIColor.black.withAlphaComponent(0.2).setFill()
		UIBezierPath(ovalIn: CGRect(x: point.x - 5, y: point.y - 2, width: 10, height: 4)).fill()

		let tip = UIBezierPath()
		tip.move(to: CGPoint(x: point.x, y: point.y))
		tip.addLine(to: CGPoint(x: point.x - 7, y: point.y - tipHeight))
		tip.addLine(to: CGPoint(x: point.x + 7, y: point.y - tipHeight))
		tip.close()
		tint.setFill()
		tip.fill()

		tint.setFill()
		UIBezierPath(ovalIn: avatarRect.insetBy(dx: -3, dy: -3)).fill()
		UIColor.systemBackground.setFill()
		UIBezierPath(ovalIn: avatarRect.insetBy(dx: -1, dy: -1)).fill()

		if let photo = AppGroup.loadAvatarImage(fileName: card.avatarFileName) {
			let ctx = UIGraphicsGetCurrentContext()
			ctx?.saveGState()
			UIBezierPath(ovalIn: avatarRect).addClip()
			photo.draw(in: avatarRect)
			ctx?.restoreGState()
		} else {
			UIColor.systemGray3.setFill()
			UIBezierPath(ovalIn: avatarRect).fill()
			let paragraph = NSMutableParagraphStyle()
			paragraph.alignment = .center
			let attrs: [NSAttributedString.Key: Any] = [
				.font: UIFont.systemFont(ofSize: 12, weight: .semibold),
				.foregroundColor: UIColor.white,
				.paragraphStyle: paragraph,
			]
			let size = (card.initials as NSString).size(withAttributes: attrs)
			(card.initials as NSString).draw(
				at: CGPoint(x: avatarRect.midX - size.width / 2, y: avatarRect.midY - size.height / 2),
				withAttributes: attrs
			)
		}
	}
}
