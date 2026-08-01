import MapKit
import SwiftUI

struct MapHomeView: View {
	@Environment(\.colorScheme) private var colorScheme
	@Environment(AuthSession.self) private var authSession
	@Environment(VisitLocationManager.self) private var locationManager
	@Environment(MapFriendsStore.self) private var friendsStore
	@Environment(FriendsStore.self) private var pairedFriends
	@Environment(LocationSharingService.self) private var locationSharing
	@Environment(RealtimeClient.self) private var realtimeClient
	@Environment(SuggestionEngine.self) private var suggestionEngine
	@Environment(MeetupMemoryStore.self) private var meetupMemoryStore
	@Environment(MapWeatherController.self) private var mapWeather

	@State private var cameraPosition: MapCameraPosition = .region(
		MKCoordinateRegion(
			center: MockFriendsProvider.fallbackCoordinate,
			latitudinalMeters: 350,
			longitudinalMeters: 350
		)
	)
	@State private var ctaToast: String?
	@State private var didCenterOnUser = false

	private var displayName: String {
		authSession.preferredDisplayName
	}

	private var locationSubtitle: String {
		locationManager.displayPlaceName
	}

	private var showsFloatingMapChrome: Bool {
		friendsStore.selectedFriend == nil
	}

	var body: some View {
		ZStack(alignment: .top) {
			SocialMapView(cameraPosition: $cameraPosition)
				.ignoresSafeArea()

			VStack(spacing: 10) {
				header
					.padding(.horizontal, 16)
					.trackWeatherObstacle("map.header", cornerRadius: KismetTheme.Chrome.headerCornerRadius)

				if locationManager.isDenied, friendsStore.selectedFriend == nil {
					locationDeniedBanner
						.padding(.horizontal, 16)
						.trackWeatherObstacle("map.locationBanner", cornerRadius: 16)
						.transition(.move(edge: .top).combined(with: .opacity))
				}
			}
			.padding(.top, 8)
			.opacity(showsFloatingMapChrome ? 1 : 0)
			.allowsHitTesting(showsFloatingMapChrome)
			.animation(.easeInOut(duration: 0.2), value: showsFloatingMapChrome)

			if let selected = friendsStore.selectedFriend {
				Color.black.opacity(colorScheme == .dark ? 0.35 : 0.18)
					.ignoresSafeArea()
					.onTapGesture {
						friendsStore.clearSelection()
					}

				PersonDetailView(
					person: selected,
					onClose: {
						friendsStore.clearSelection()
					},
					onSayHi: {
						showToast("Say Hi to \(selected.displayName) — coming soon")
					},
					onMessage: {
						showToast("Message \(selected.displayName) — coming soon")
					},
					onWeMet: {
						meetupMemoryStore.markCompleted(
							friendUserId: selected.id,
							friendDisplayName: selected.displayName
						)
						showToast("Noted — hung out with \(selected.displayName)")
						Task { await refreshSuggestions() }
					}
				)
				.padding(.horizontal, 18)
				.trackWeatherObstacle("map.personDetail", cornerRadius: 28)
				// Clear the floating tab pill; card layout/spacing stays unchanged.
				.padding(.bottom, 100)
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
				.transition(.move(edge: .bottom).combined(with: .opacity))
				.zIndex(2)
			}
		}
		.animation(.spring(response: 0.34, dampingFraction: 0.86), value: friendsStore.selectedFriendID)
		.task {
			await runMapSession()
		}
		.onChange(of: locationManager.hasFix) { _, hasFix in
			guard hasFix, !didCenterOnUser else { return }
			recenter(on: locationManager.displayCoordinate)
			Task { await friendsStore.refresh(around: locationManager.displayCoordinate) }
			Task { await mapWeather.refreshIfNeeded(at: locationManager.displayCoordinate) }
			publishLocation(force: true)
			didCenterOnUser = true
		}
		.onChange(of: locationManager.userLocation?.timestamp) { _, _ in
			publishLocation(force: false)
		}
		.onChange(of: pairedFriends.graphRevision) { _, _ in
			publishLocation(force: true)
			Task { await friendsStore.refresh(around: locationManager.displayCoordinate) }
		}
		.overlay(alignment: .top) {
			if let ctaToast {
				Text(ctaToast)
					.font(.footnote.weight(.semibold))
					.padding(.horizontal, 14)
					.padding(.vertical, 10)
					.background(.ultraThinMaterial, in: Capsule())
					.trackWeatherObstacle("map.toast", cornerRadius: .infinity)
					.padding(.top, 72)
					.transition(.move(edge: .top).combined(with: .opacity))
			}
		}
		.animation(.snappy, value: ctaToast)
	}

	private var header: some View {
		HStack(spacing: 12) {
			HStack(spacing: 10) {
				ZStack(alignment: .bottomTrailing) {
					Image(systemName: "person.crop.circle.fill")
						.resizable()
						.scaledToFit()
						.foregroundStyle(.secondary)
						.frame(
							width: KismetTheme.Chrome.avatarSize,
							height: KismetTheme.Chrome.avatarSize
						)

					Circle()
						.fill(KismetTheme.Status.free)
						.frame(width: 11, height: 11)
						.overlay {
							Circle().stroke(.background, lineWidth: 2)
						}
				}

				VStack(alignment: .leading, spacing: 2) {
					Text(displayName)
						.font(.headline)
						.foregroundStyle(KismetTheme.Map.headerForeground)
						.lineLimit(1)

					HStack(spacing: 4) {
						Text(locationSubtitle)
							.font(.caption)
							.foregroundStyle(KismetTheme.Map.secondaryLabel)
							.lineLimit(1)
						Image(systemName: "chevron.down")
							.font(.caption2.weight(.semibold))
							.foregroundStyle(KismetTheme.Map.secondaryLabel)
					}
				}
			}

			Spacer(minLength: 8)

			Button {
				// Filters arrive with live friends; keep chrome interactive for now.
			} label: {
				Image(systemName: "slider.horizontal.3")
					.font(.body.weight(.semibold))
					.foregroundStyle(.primary)
					.frame(width: 40, height: 40)
			}
			.buttonStyle(.plain)
			.background(.ultraThinMaterial, in: Circle())
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 10)
		.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: KismetTheme.Chrome.headerCornerRadius, style: .continuous))
		.shadow(color: .black.opacity(0.08), radius: 12, y: 4)
	}

	private var locationDeniedBanner: some View {
		HStack(spacing: 12) {
			Image(systemName: "location.slash.fill")
				.foregroundStyle(KismetTheme.Status.busy)

			VStack(alignment: .leading, spacing: 2) {
				Text("Location is off")
					.font(.subheadline.weight(.semibold))
				Text("Enable location to share your pin and see friends nearby.")
					.font(.caption)
					.foregroundStyle(.secondary)
			}

			Spacer(minLength: 0)

			Button("Enable") {
				locationManager.openSystemSettings()
			}
			.font(.caption.weight(.bold))
			.buttonStyle(.borderedProminent)
			.tint(KismetTheme.Status.free)
			.controlSize(.small)
		}
		.padding(12)
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}

	@MainActor
	private func runMapSession() async {
		locationSharing.start()

		let mapStore = friendsStore
		let socialStore = pairedFriends
		let locations = locationManager
		let sharing = locationSharing
		let realtime = realtimeClient

		realtime.onMapEvent = { event in
			Task { @MainActor in
				switch event.type {
				case "blob.available":
					await mapStore.refresh(around: locations.displayCoordinate)
					await refreshSuggestions()
				case "friend.pair.created":
					await socialStore.refresh()
					await mapStore.refresh(around: locations.displayCoordinate)
					sharing.shareIfNeeded(
						location: locations.userLocation,
						senderUserId: KeychainStore.get(.userId),
						friends: socialStore.friends,
						force: true
					)
					await refreshSuggestions()
				case "friend.pair.revoked":
					await socialStore.refresh()
					await mapStore.refresh(around: locations.displayCoordinate)
					await refreshSuggestions()
				default:
					await socialStore.refresh()
					await mapStore.refresh(around: locations.displayCoordinate)
					await refreshSuggestions()
				}
			}
		}
		realtime.connect()

		defer {
			realtime.onMapEvent = nil
			realtime.disconnect()
			sharing.stop()
		}

		await bootstrapMap()
		guard !Task.isCancelled else { return }

		while !Task.isCancelled {
			do {
				try await Task.sleep(for: .seconds(30))
			} catch {
				break
			}
			guard !Task.isCancelled else { break }
			await refreshMapData()
		}
	}

	@MainActor
	private func bootstrapMap() async {
		locationManager.prepareForMapAppearance()
		await pairedFriends.refresh()
		await friendsStore.refresh(around: locationManager.displayCoordinate)

		try? await Task.sleep(for: .milliseconds(50))
		guard !Task.isCancelled else { return }
		recenter(on: locationManager.displayCoordinate)
		await friendsStore.refresh(around: locationManager.displayCoordinate)
		await mapWeather.refreshIfNeeded(at: locationManager.displayCoordinate)
		publishLocation(force: true)
		await refreshSuggestions()
	}

	private func refreshMapData() async {
		await pairedFriends.refresh()
		await friendsStore.refresh(around: locationManager.displayCoordinate)
		await refreshSuggestions()
	}

	@MainActor
	private func refreshSuggestions() async {
		let learned = meetupMemoryStore.buildLearnedSlice()
		await suggestionEngine.refresh(
			userId: authSession.user?.id ?? KeychainStore.get(.userId),
			displayName: authSession.preferredDisplayName,
			interests: authSession.user?.interests ?? [],
			coordinate: locationManager.displayCoordinate,
			placeName: locationManager.displayPlaceName,
			people: friendsStore.friends,
			learned: learned
		)
	}

	private func publishLocation(force: Bool) {
		locationSharing.shareIfNeeded(
			location: locationManager.userLocation,
			senderUserId: authSession.user?.id ?? KeychainStore.get(.userId),
			friends: pairedFriends.friends,
			force: force
		)
	}

	private func recenter(on coordinate: CLLocationCoordinate2D) {
		cameraPosition = .region(
			MKCoordinateRegion(
				center: coordinate,
				latitudinalMeters: 350,
				longitudinalMeters: 350
			)
		)
	}

	private func showToast(_ message: String) {
		ctaToast = message
		Task {
			try? await Task.sleep(for: .seconds(2))
			if ctaToast == message {
				ctaToast = nil
			}
		}
	}
}

// The preview helpers below are DEBUG-only, so the preview must be too —
// otherwise a Release build fails on symbols that were compiled out.
#if DEBUG
#Preview("Light") {
	MapHomePreviewHost()
		.preferredColorScheme(.light)
}

#Preview("Dark") {
	MapHomePreviewHost()
		.preferredColorScheme(.dark)
}

private struct MapHomePreviewHost: View {
	@State private var authSession = AuthSession.previewSignedIn()
	@State private var locationManager = VisitLocationManager()
	@State private var friendsStore = MapFriendsStore()
	@State private var pairedFriends = FriendsStore.preview()
	@State private var locationSharing = LocationSharingService()
	@State private var realtimeClient = RealtimeClient()
	@State private var suggestionEngine = SuggestionEngine()
	@State private var mapWeather = MapWeatherController()
	@State private var weatherObstacles = WeatherObstacleStore()
	@State private var meetupMemoryStore = MeetupMemoryStore(
		container: try! MeetupModelContainer.makeInMemory()
	)

	var body: some View {
		MapHomeView()
			.environment(authSession)
			.environment(locationManager)
			.environment(friendsStore)
			.environment(pairedFriends)
			.environment(locationSharing)
			.environment(realtimeClient)
			.environment(suggestionEngine)
			.environment(mapWeather)
			.environment(weatherObstacles)
			.environment(meetupMemoryStore)
			.task {
				friendsStore.loadPreviewMocks(around: MockFriendsProvider.fallbackCoordinate)
				await suggestionEngine.refresh(
					userId: "preview",
					displayName: "You",
					interests: ["coffee"],
					coordinate: MockFriendsProvider.fallbackCoordinate,
					placeName: "Koramangala",
					people: friendsStore.friends,
					learned: meetupMemoryStore.buildLearnedSlice()
				)
			}
	}
}
#endif
