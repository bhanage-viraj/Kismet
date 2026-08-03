import MapKit
import SwiftUI

struct SocialMapView: View {
	@Environment(VisitLocationManager.self) private var locationManager
	@Environment(MapFriendsStore.self) private var friendsStore

	@Binding var cameraPosition: MapCameraPosition
	var showsRadarRings: Bool = true

	private var center: CLLocationCoordinate2D {
		locationManager.displayCoordinate
	}

	private var selectionBinding: Binding<String?> {
		Binding(
			get: { friendsStore.selectedFriendID },
			set: { newValue in
				// Defer store writes so MapKit isn't mid-update when Observation fires.
				Task { @MainActor in
					friendsStore.select(newValue)
				}
			}
		)
	}

	var body: some View {
		Map(position: $cameraPosition, selection: selectionBinding) {
			if showsRadarRings {
				radarRings
			}

			selfAnnotationContent

			ForEach(friendsStore.friends) { friend in
				Annotation(
					friend.displayName,
					coordinate: friend.coordinate,
					anchor: .bottom
				) {
					FriendMapAnnotationView(
						person: friend,
						isSelected: friendsStore.selectedFriendID == friend.id
					)
				}
				.tag(friend.id)
			}
		}
		.mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
		.mapControls {
			MapCompass()
		}
	}

	@MapContentBuilder
	private var radarRings: some MapContent {
		MapCircle(center: center, radius: 40)
			.foregroundStyle(KismetTheme.Map.userPulse.opacity(0.10))
			.stroke(KismetTheme.Map.userPulse.opacity(0.25), lineWidth: 1)

		MapCircle(center: center, radius: 80)
			.foregroundStyle(KismetTheme.Map.userPulse.opacity(0.06))
			.stroke(KismetTheme.Map.ringStroke, lineWidth: 1)

		MapCircle(center: center, radius: 130)
			.foregroundStyle(KismetTheme.Map.userPulse.opacity(0.03))
			.stroke(KismetTheme.Map.ringStroke, lineWidth: 1)
	}

	@MapContentBuilder
	private var selfAnnotationContent: some MapContent {
		if locationManager.isAuthorized, locationManager.hasFix {
			UserAnnotation()
			Annotation("You", coordinate: center, anchor: .top) {
				YouPinLabel()
			}
		} else {
			Annotation("You", coordinate: center, anchor: .bottom) {
				VStack(spacing: 4) {
					ZStack {
						Circle()
							.fill(KismetTheme.Map.userPulse.opacity(0.18))
							.frame(width: 44, height: 44)
						Circle()
							.fill(KismetTheme.Map.userPulse)
							.frame(width: 14, height: 14)
							.overlay {
								Circle()
									.stroke(.white, lineWidth: 2)
							}
					}
					YouPinLabel()
				}
			}
		}
	}
}

// MARK: - Friend annotation

private struct FriendMapAnnotationView: View {
	let person: MapPerson
	let isSelected: Bool

	private var ringColor: Color {
		KismetTheme.Map.ring(for: person.availability)
	}

	var body: some View {
		VStack(spacing: 6) {
			ZStack {
				Circle()
					.fill(KismetTheme.Map.glow(for: person.availability))
					.frame(width: 78, height: 78)
					.blur(radius: 8)

				Circle()
					.stroke(ringColor, lineWidth: isSelected ? 3.5 : 2.5)
					.frame(
						width: KismetTheme.Chrome.annotationAvatarSize + 6,
						height: KismetTheme.Chrome.annotationAvatarSize + 6
					)

				Image(systemName: person.accentSystemImage)
					.resizable()
					.scaledToFill()
					.foregroundStyle(.white)
					.background(ringColor.gradient, in: Circle())
					.frame(
						width: KismetTheme.Chrome.annotationAvatarSize,
						height: KismetTheme.Chrome.annotationAvatarSize
					)
					.clipShape(Circle())

				Circle()
					.fill(person.availability.statusColor)
					.frame(
						width: KismetTheme.Chrome.statusDotSize,
						height: KismetTheme.Chrome.statusDotSize
					)
					.overlay {
						Circle().stroke(.white, lineWidth: 1.5)
					}
					.offset(x: 20, y: 20)
			}
			.scaleEffect(isSelected ? 1.08 : 1.0)
			.animation(.spring(response: 0.28, dampingFraction: 0.8), value: isSelected)

			Text("\(person.displayName), \(person.formattedDistance)")
				.font(.caption2.weight(.semibold))
				.foregroundStyle(.primary)
				.padding(.horizontal, 10)
				.padding(.vertical, 5)
				.background(KismetTheme.Map.annotationLabelFill, in: Capsule())
				.shadow(color: .black.opacity(0.12), radius: 6, y: 2)
		}
		.accessibilityElement(children: .combine)
		.accessibilityLabel("\(person.displayName), \(person.formattedDistance), \(person.availability.rawValue)")
	}
}

private struct YouPinLabel: View {
	var body: some View {
		HStack(spacing: 4) {
			Image(systemName: "mappin.circle.fill")
				.foregroundStyle(KismetTheme.Map.youPin)
			Text("You")
				.font(.caption2.weight(.bold))
		}
		.padding(.horizontal, 8)
		.padding(.vertical, 4)
		.background(KismetTheme.Map.annotationLabelFill, in: Capsule())
		.shadow(color: .black.opacity(0.12), radius: 4, y: 1)
	}
}

// loadPreviewMocks is DEBUG-only, so the preview must be too — otherwise a
// Release build fails on a symbol that was compiled out.
#if DEBUG
#Preview("Light") {
	SocialMapPreviewHost()
		.preferredColorScheme(.light)
}

#Preview("Dark") {
	SocialMapPreviewHost()
		.preferredColorScheme(.dark)
}

private struct SocialMapPreviewHost: View {
	@State private var locationManager = VisitLocationManager()
	@State private var friendsStore = MapFriendsStore()
	@State private var cameraPosition: MapCameraPosition = .region(
		MKCoordinateRegion(
			center: MockFriendsProvider.fallbackCoordinate,
			latitudinalMeters: 350,
			longitudinalMeters: 350
		)
	)

	var body: some View {
		SocialMapView(cameraPosition: $cameraPosition)
			.environment(locationManager)
			.environment(friendsStore)
			.onAppear {
				friendsStore.loadPreviewMocks(around: MockFriendsProvider.fallbackCoordinate)
			}
			.ignoresSafeArea()
	}
}
#endif
