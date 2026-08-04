import SwiftUI

#if DEBUG
enum BumpDemoSupport {
	static func fakeSample(
		distance: Float = 1.25,
		withDirection: Bool = true
	) -> NearbyRangeSample {
		NearbyRangeSample(
			distance: distance,
			direction: withDirection ? SIMD3<Float>(0.2, 0.05, -0.95) : nil,
			timestamp: .now
		)
	}
}
#endif
