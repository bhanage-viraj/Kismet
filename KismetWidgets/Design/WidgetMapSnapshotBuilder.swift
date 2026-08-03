import MapKit
import UIKit
import WidgetKit

/// In-extension MapKit snapshot fallback (main app writes the preferred cache).
enum WidgetMapSnapshotBuilder {
	static let fallbackCoordinate = CLLocationCoordinate2D(latitude: 12.9352, longitude: 77.6245)

	static func render(
		data: WidgetAppGroup.SuggestionSnapshot?,
		size: CGSize,
		traitCollection: UITraitCollection = .current,
		completion: @escaping (UIImage?) -> Void
	) {
		guard size.width > 1, size.height > 1 else {
			DispatchQueue.main.async { completion(WidgetAppGroup.loadCachedMapImage()) }
			return
		}

		let options = MKMapSnapshotter.Options()
		options.region = region(for: data)
		options.size = size
		options.mapType = .standard
		options.showsBuildings = true
		options.pointOfInterestFilter = .includingAll
		options.traitCollection = UITraitCollection(traitsFrom: [
			options.traitCollection,
			UITraitCollection(displayScale: max(traitCollection.displayScale, 2)),
			UITraitCollection(userInterfaceStyle: traitCollection.userInterfaceStyle),
		])
		if #available(iOS 17.0, *) {
			let config = MKStandardMapConfiguration(elevationStyle: .flat)
			config.pointOfInterestFilter = .includingAll
			options.preferredConfiguration = config
		}

		MKMapSnapshotter(options: options).start(with: .global(qos: .userInitiated)) { mapSnapshot, error in
			guard let mapSnapshot, error == nil else {
				DispatchQueue.main.async { completion(WidgetAppGroup.loadCachedMapImage()) }
				return
			}
			let composed = compose(mapSnapshot: mapSnapshot, data: data)
			DispatchQueue.main.async { completion(composed) }
		}
	}

	private static func region(for data: WidgetAppGroup.SuggestionSnapshot?) -> MKCoordinateRegion {
		let user = userCoordinate(from: data)
		var coords: [CLLocationCoordinate2D] = [user]
		for card in (data?.cards ?? []).prefix(4) {
			if let c = card.coordinate { coords.append(c) }
		}
		guard coords.count > 1 else {
			return MKCoordinateRegion(center: user, latitudinalMeters: 1_800, longitudinalMeters: 1_800)
		}
		var minLat = coords[0].latitude, maxLat = coords[0].latitude
		var minLon = coords[0].longitude, maxLon = coords[0].longitude
		for c in coords.dropFirst() {
			minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
			minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
		}
		let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
		let latMeters = max(CLLocation(latitude: minLat, longitude: center.longitude)
			.distance(from: CLLocation(latitude: maxLat, longitude: center.longitude)), 400)
		let lonMeters = max(CLLocation(latitude: center.latitude, longitude: minLon)
			.distance(from: CLLocation(latitude: center.latitude, longitude: maxLon)), 400)
		return MKCoordinateRegion(
			center: center,
			latitudinalMeters: latMeters * 1.7 + 600,
			longitudinalMeters: lonMeters * 1.7 + 600
		)
	}

	private static func userCoordinate(from data: WidgetAppGroup.SuggestionSnapshot?) -> CLLocationCoordinate2D {
		if let lat = data?.userLatitude, let lon = data?.userLongitude {
			return CLLocationCoordinate2D(latitude: lat, longitude: lon)
		}
		return fallbackCoordinate
	}

	private static func compose(
		mapSnapshot: MKMapSnapshotter.Snapshot,
		data: WidgetAppGroup.SuggestionSnapshot?
	) -> UIImage {
		let base = mapSnapshot.image
		let format = UIGraphicsImageRendererFormat()
		format.scale = base.scale
		format.opaque = true
		let bounds = CGRect(origin: .zero, size: base.size)
		return UIGraphicsImageRenderer(size: base.size, format: format).image { _ in
			base.draw(at: .zero)
			let userPoint = mapSnapshot.point(for: userCoordinate(from: data))
			if bounds.insetBy(dx: -20, dy: -20).contains(userPoint) {
				drawYou(at: userPoint)
			}
			for card in (data?.cards ?? []).prefix(4) {
				guard let coordinate = card.coordinate else { continue }
				let point = mapSnapshot.point(for: coordinate)
				guard bounds.insetBy(dx: -36, dy: -48).contains(point) else { continue }
				drawPin(card: card, at: point)
			}
		}
	}

	private static func drawYou(at point: CGPoint) {
		let blue = UIColor.systemBlue
		blue.withAlphaComponent(0.18).setFill()
		UIBezierPath(ovalIn: CGRect(x: point.x - 22, y: point.y - 22, width: 44, height: 44)).fill()
		blue.setFill()
		UIBezierPath(ovalIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12)).fill()
		UIColor.white.setStroke()
		let core = UIBezierPath(ovalIn: CGRect(x: point.x - 6, y: point.y - 6, width: 12, height: 12))
		core.lineWidth = 2
		core.stroke()
	}

	private static func drawPin(card: WidgetAppGroup.Card, at point: CGPoint) {
		let tint: UIColor = {
			switch card.status {
			case .free: .systemGreen
			case .busy: .systemOrange
			case .nearby: .systemGray
			}
		}()
		let size: CGFloat = 32
		let tip: CGFloat = 9
		let rect = CGRect(x: point.x - size / 2, y: point.y - size - tip, width: size, height: size)
		let path = UIBezierPath()
		path.move(to: point)
		path.addLine(to: CGPoint(x: point.x - 7, y: point.y - tip))
		path.addLine(to: CGPoint(x: point.x + 7, y: point.y - tip))
		path.close()
		tint.setFill()
		path.fill()
		tint.setFill()
		UIBezierPath(ovalIn: rect.insetBy(dx: -3, dy: -3)).fill()
		UIColor.systemBackground.setFill()
		UIBezierPath(ovalIn: rect.insetBy(dx: -1, dy: -1)).fill()
		if let photo = WidgetAppGroup.loadAvatarImage(fileName: card.avatarFileName) {
			let ctx = UIGraphicsGetCurrentContext()
			ctx?.saveGState()
			UIBezierPath(ovalIn: rect).addClip()
			photo.draw(in: rect)
			ctx?.restoreGState()
		} else {
			UIColor.systemGray3.setFill()
			UIBezierPath(ovalIn: rect).fill()
			let attrs: [NSAttributedString.Key: Any] = [
				.font: UIFont.systemFont(ofSize: 12, weight: .semibold),
				.foregroundColor: UIColor.white,
			]
			let textSize = (card.initials as NSString).size(withAttributes: attrs)
			(card.initials as NSString).draw(
				at: CGPoint(x: rect.midX - textSize.width / 2, y: rect.midY - textSize.height / 2),
				withAttributes: attrs
			)
		}
	}
}
