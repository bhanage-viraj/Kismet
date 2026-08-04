import CoreLocation
import Testing
@testable import Kismet

struct PresenceLocationPolicyTests {
	@Test func availableKeepsPreciseCoordinate() {
		let location = CLLocation(latitude: 12.93521, longitude: 77.62455)
		let share = PresenceLocationPolicy.shareCoordinate(from: location, presence: .available)
		#expect(share.latitude == location.coordinate.latitude)
		#expect(share.longitude == location.coordinate.longitude)
	}

	@Test func approximateQuantizesToNeighborhoodGrid() {
		let location = CLLocation(latitude: 12.93521, longitude: 77.62455)
		let share = PresenceLocationPolicy.shareCoordinate(from: location, presence: .approximate)
		#expect(share.latitude != location.coordinate.latitude || share.longitude != location.coordinate.longitude)
		#expect(share.accuracy == PresenceLocationPolicy.approximateGridMeters)

		let snapped = CLLocation(latitude: share.latitude, longitude: share.longitude)
		let drift = location.distance(from: snapped)
		#expect(drift < PresenceLocationPolicy.approximateGridMeters * 0.75)
	}

	@Test func eclipseAlsoQuantizes() {
		let location = CLLocation(latitude: 12.93521, longitude: 77.62455)
		let share = PresenceLocationPolicy.shareCoordinate(from: location, presence: .eclipse)
		#expect(share.accuracy == PresenceLocationPolicy.approximateGridMeters)
	}

	@Test func payloadSealsMode() {
		let location = CLLocation(latitude: 12.93521, longitude: 77.62455)
		let payload = PresenceLocationPolicy.payload(from: location, presence: .friendsOnly)
		#expect(payload.mode == PresenceState.friendsOnly.rawValue)
		#expect(payload.presenceState == .friendsOnly)
	}

	@Test func presencePrefersSealedModeOverSchedule() {
		let payload = LocationPayloadDTO(
			lat: 1,
			lon: 2,
			at: Date(),
			mode: PresenceState.eclipse.rawValue
		)
		let presence = PresenceState.from(payload: payload, availabilityStatus: .free)
		#expect(presence == .eclipse)
		#expect(!presence.isSurfaceVisible)
	}

	@Test func legacyPayloadFallsBackToSchedule() {
		let payload = LocationPayloadDTO(lat: 1, lon: 2, at: Date(), mode: nil)
		let presence = PresenceState.from(payload: payload, availabilityStatus: .busy)
		#expect(presence == .friendsOnly)
	}
}
