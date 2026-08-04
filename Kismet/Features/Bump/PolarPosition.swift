import CoreGraphics
import simd

/// Polar → cartesian placement shared by bump and nearby radar UIs.
enum PolarPosition {
	/// Default angle when direction is unknown: straight up on screen.
	static let defaultAngle: CGFloat = -.pi / 2

	/// Clamped radial fraction used so near peers stay slightly off-center.
	static func clampedFraction(distance: CGFloat, maxRange: CGFloat) -> CGFloat {
		min(max(distance / maxRange, 0.08), 1.0)
	}

	/// Point on a radar given distance (meters), max range, center, outer radius, and bearing.
	static func point(
		distance: CGFloat,
		maxRange: CGFloat,
		center: CGPoint,
		outerRadius: CGFloat,
		angle: CGFloat = defaultAngle
	) -> CGPoint {
		let ring = outerRadius * clampedFraction(distance: distance, maxRange: maxRange)
		return CGPoint(
			x: center.x + cos(angle) * ring,
			y: center.y + sin(angle) * ring
		)
	}

	/// Ring distance from center for a given range sample (useful for wedges).
	static func ringRadius(
		distance: CGFloat,
		maxRange: CGFloat,
		outerRadius: CGFloat
	) -> CGFloat {
		outerRadius * clampedFraction(distance: distance, maxRange: maxRange)
	}

	/// Horizontal azimuth from Nearby Interaction direction (−Z out of screen, +X right).
	static func azimuth(from direction: SIMD3<Float>?) -> CGFloat? {
		guard let direction else { return nil }
		return CGFloat(atan2(direction.x, -direction.z))
	}

	/// Rotation for a vertical capsule wedge aligned to `angle`.
	static func wedgeRotation(for angle: CGFloat) -> CGFloat {
		angle + .pi / 2
	}
}
