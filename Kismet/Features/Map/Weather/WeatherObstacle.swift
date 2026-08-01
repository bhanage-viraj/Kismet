import Observation
import SwiftUI

/// Global-screen rect that rain/snow can collide with (converted to overlay-local at draw time).
struct WeatherObstacle: Equatable, Identifiable, Sendable {
	let id: String
	/// Frame in global coordinates (`frame(in: .global)`).
	let rect: CGRect
	/// Visual corner radius. Use `.infinity` for a capsule (resolved to height/2 at hit-test).
	let cornerRadius: CGFloat

	var topY: CGFloat { rect.minY }

	/// Horizontal inset of the flat top edge (outside this, you're in empty corner / side margin).
	var topEdgeInsetX: CGFloat {
		let maxR = min(rect.width, rect.height) / 2
		let resolved = cornerRadius.isInfinite ? maxR : min(max(cornerRadius, 0), maxR)
		return resolved
	}

	func convertedToOverlayLocal(overlayFrameInGlobal: CGRect) -> WeatherObstacle {
		WeatherObstacle(
			id: id,
			rect: rect.offsetBy(dx: -overlayFrameInGlobal.minX, dy: -overlayFrameInGlobal.minY),
			cornerRadius: cornerRadius
		)
	}

	func containsTopEdge(atX x: CGFloat) -> Bool {
		let inset = topEdgeInsetX
		return x >= rect.minX + inset && x <= rect.maxX - inset
	}
}

/// Shared chrome frames for weather collisions (map header, tab bar, insights, etc.).
@MainActor
@Observable
final class WeatherObstacleStore {
	private struct Entry: Equatable {
		var frame: CGRect
		var cornerRadius: CGFloat
	}

	private var entries: [String: Entry] = [:]

	var obstacles: [WeatherObstacle] {
		entries.compactMap { id, entry in
			guard entry.frame.width > 1, entry.frame.height > 1, entry.frame.height < 900 else { return nil }
			return WeatherObstacle(id: id, rect: entry.frame, cornerRadius: entry.cornerRadius)
		}
	}

	func update(_ id: String, frame: CGRect, cornerRadius: CGFloat) {
		guard frame.width > 1, frame.height > 1 else { return }
		let entry = Entry(frame: frame, cornerRadius: cornerRadius)
		if entries[id] != entry {
			entries[id] = entry
		}
	}

	func remove(_ id: String) {
		entries[id] = nil
	}
}

extension View {
	/// Tracks this view's global frame for weather particle collisions.
	/// Apply on the visual chrome itself — never after an expanding `.frame(maxWidth/maxHeight: .infinity)`.
	/// - Parameter cornerRadius: Match the glass shape (capsule → `.infinity`).
	func trackWeatherObstacle(_ id: String, cornerRadius: CGFloat = 16) -> some View {
		modifier(WeatherObstacleTrackingModifier(id: id, cornerRadius: cornerRadius))
	}
}

private struct WeatherObstacleTrackingModifier: ViewModifier {
	let id: String
	let cornerRadius: CGFloat
	@Environment(WeatherObstacleStore.self) private var store

	func body(content: Content) -> some View {
		content
			.onGeometryChange(for: CGRect.self) { proxy in
				proxy.frame(in: .global)
			} action: { frame in
				store.update(id, frame: frame, cornerRadius: cornerRadius)
			}
			.onDisappear {
				store.remove(id)
			}
	}
}
