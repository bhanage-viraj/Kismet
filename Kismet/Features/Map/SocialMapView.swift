import MapKit
import SwiftUI

struct SocialMapView: View {
	@Environment(VisitLocationManager.self) private var locationManager
	@Environment(MapFriendsStore.self) private var friendsStore
	@Environment(PresenceModeStore.self) private var presenceMode

	@Binding var cameraPosition: MapCameraPosition

	private var center: CLLocationCoordinate2D {
		locationManager.displayCoordinate
	}

	private var selectionBinding: Binding<String?> {
		Binding(
			get: { friendsStore.selectedFriendID },
			set: { newValue in
				friendsStore.select(newValue)
			}
		)
	}

	var body: some View {
		Map(position: $cameraPosition, selection: selectionBinding) {
			selfAnnotationContent

			ForEach(friendsStore.friends) { friend in
				Annotation(
					"",
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
			MapUserLocationButton()
		}
	}

	@MapContentBuilder
	private var selfAnnotationContent: some MapContent {
		if locationManager.isAuthorized, locationManager.hasFix {
			UserAnnotation()
			Annotation("", coordinate: center, anchor: .top) {
				YouPresenceMarker(presence: presenceMode.state, showsDot: false)
			}
		} else {
			Annotation("", coordinate: center, anchor: .bottom) {
				YouPresenceMarker(presence: presenceMode.state, showsDot: true)
			}
		}
	}
}

// MARK: - Friend annotation

private struct FriendMapAnnotationView: View {
	let person: MapPerson
	let isSelected: Bool

	private var ringColor: Color {
		person.presenceState.statusColor
	}

	var body: some View {
		VStack(spacing: 6) {
			ZStack {
				Circle()
					.fill(ringColor.opacity(0.22))
					.frame(
						width: KismetTheme.Chrome.annotationAvatarSize + 14,
						height: KismetTheme.Chrome.annotationAvatarSize + 14
					)

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
					.fill(person.presenceState.statusColor)
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
		.accessibilityLabel("\(person.displayName), \(person.formattedDistance), \(person.presenceState.title)")
	}
}

/// You-pin: presence-tinted label + a short ripple when the mode changes.
private struct YouPresenceMarker: View {
	let presence: PresenceState
	/// When there's no system `UserAnnotation`, draw our own location dot.
	var showsDot: Bool = false

	@Environment(\.accessibilityReduceMotion) private var reduceMotion

	@State private var ripple = false
	@State private var pop = false
	@State private var showTitle = false

	private var labelText: String {
		showTitle ? presence.title : "You"
	}

	var body: some View {
		VStack(spacing: 5) {
			if showsDot {
				ZStack {
					presenceRipple

					Circle()
						.fill(presence.statusColor.opacity(0.22))
						.frame(width: 40, height: 40)

					Circle()
						.fill(presence.statusColor)
						.frame(width: 14, height: 14)
						.overlay {
							Circle().stroke(.white, lineWidth: 2)
						}
						.scaleEffect(pop ? 1.28 : 1)
				}
			}

			labelCapsule
				.overlay(alignment: .top) {
					if !showsDot {
						presenceRipple
							.offset(y: -14)
							.allowsHitTesting(false)
					}
				}
		}
		.fixedSize()
		.accessibilityLabel("You, \(presence.title)")
		.onChange(of: presence) { _, _ in
			playPresenceChange()
		}
	}

	private var labelCapsule: some View {
		HStack(spacing: 4) {
			Image(systemName: presence.systemImage)
				.font(.caption2.weight(.bold))
				.foregroundStyle(presence.statusColor)
				.symbolEffect(.bounce, value: presence)

			Text(labelText)
				.font(.caption2.weight(.bold))
				.foregroundStyle(.primary)
				.lineLimit(1)
				.id(labelText)
		}
		.padding(.horizontal, 8)
		.padding(.vertical, 4)
		.background(KismetTheme.Map.annotationLabelFill, in: Capsule())
		.overlay {
			Capsule()
				.stroke(presence.statusColor.opacity(showTitle || pop ? 0.55 : 0.2), lineWidth: 1)
		}
		.shadow(color: presence.statusColor.opacity(pop ? 0.35 : 0.12), radius: pop ? 8 : 4, y: 1)
		.scaleEffect(pop ? 1.08 : 1)
		.fixedSize()
	}

	private var presenceRipple: some View {
		Circle()
			.stroke(presence.statusColor.opacity(0.55), lineWidth: 2)
			.frame(width: 22, height: 22)
			.scaleEffect(ripple ? 3.2 : 0.4)
			.opacity(ripple ? 0 : 0.85)
	}

	private func playPresenceChange() {
		if reduceMotion {
			withAnimation(.easeInOut(duration: 0.2)) {
				showTitle = true
			}
			Task {
				try? await Task.sleep(for: .seconds(1.2))
				withAnimation(.easeInOut(duration: 0.2)) {
					showTitle = false
				}
			}
			return
		}

		ripple = false
		pop = false

		withAnimation(.spring(response: 0.34, dampingFraction: 0.78)) {
			showTitle = true
			pop = true
		}
		withAnimation(.easeOut(duration: 0.65)) {
			ripple = true
		}

		Task {
			try? await Task.sleep(for: .milliseconds(380))
			withAnimation(.spring(response: 0.32, dampingFraction: 0.78)) {
				pop = false
			}
			try? await Task.sleep(for: .milliseconds(900))
			withAnimation(.spring(response: 0.34, dampingFraction: 0.84)) {
				showTitle = false
			}
			ripple = false
		}
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
	@State private var presenceMode = PresenceModeStore(state: .available)
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
			.environment(presenceMode)
			.onAppear {
				friendsStore.loadPreviewMocks(around: MockFriendsProvider.fallbackCoordinate)
			}
			.ignoresSafeArea()
	}
}
#endif
