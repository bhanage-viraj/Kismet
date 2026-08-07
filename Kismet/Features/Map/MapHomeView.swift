import MapKit
import SwiftUI

/// Find My–style persistent sheet heights over the map.
private enum SuggestionsSheetDetent: Int, CaseIterable, Comparable {
	case peek
	case medium
	case expanded

	static func < (lhs: SuggestionsSheetDetent, rhs: SuggestionsSheetDetent) -> Bool {
		lhs.rawValue < rhs.rawValue
	}

	func height(in container: CGFloat) -> CGFloat {
		switch self {
		case .peek: 78
		case .medium: min(340, container * 0.42)
		case .expanded: min(560, container * 0.72)
		}
	}

	func advancing(by translation: CGFloat) -> SuggestionsSheetDetent {
		// Negative translation = drag up = expand.
		if translation < -48 { return next }
		if translation > 48 { return previous }
		return self
	}

	var next: SuggestionsSheetDetent {
		SuggestionsSheetDetent(rawValue: rawValue + 1) ?? self
	}

	var previous: SuggestionsSheetDetent {
		SuggestionsSheetDetent(rawValue: rawValue - 1) ?? self
	}
}

struct MapHomeView: View {
	@Environment(\.colorScheme) private var colorScheme
	@Environment(AuthSession.self) private var authSession
	@Environment(VisitLocationManager.self) private var locationManager
	@Environment(MapFriendsStore.self) private var friendsStore
	@Environment(FriendsStore.self) private var pairedFriends
	@Environment(LocationSharingService.self) private var locationSharing
	@Environment(BackgroundProximityController.self) private var backgroundProximity
	@Environment(RealtimeClient.self) private var realtimeClient
	@Environment(SuggestionEngine.self) private var suggestionEngine
	@Environment(MeetupMemoryStore.self) private var meetupMemoryStore
	@Environment(InterestSuggestionStore.self) private var interestSuggestionStore
	@Environment(PresenceModeStore.self) private var presenceMode
	@Environment(FriendsOnlyVisibilityStore.self) private var friendsOnlyVisibility
	@Environment(PulseInboxStore.self) private var pulseInbox

	@Binding var composeDraft: PulseComposeDraft?

	@State private var cameraPosition: MapCameraPosition = .region(
		MKCoordinateRegion(
			center: MockFriendsProvider.fallbackCoordinate,
			latitudinalMeters: 350,
			longitudinalMeters: 350
		)
	)
	@State private var ctaToast: String?
	@State private var didCenterOnAccurateFix = false
	@State private var isPresencePickerExpanded = false
	@State private var showFriendsOnlyPicker = false
	@State private var presentedPulse: IncomingPulse?
	@State private var suggestionsDetent: SuggestionsSheetDetent = .peek
	@State private var suggestionsDragOffset: CGFloat = 0
	@State private var recordedShownCardIDs: Set<String> = []

	private var displayName: String {
		authSession.preferredDisplayName
	}

	private var locationSubtitle: String {
		locationManager.displayPlaceName
	}

	private var showsFloatingMapChrome: Bool {
		friendsStore.selectedFriend == nil
	}

	private var suggestionCards: [SuggestionCard] {
		suggestionEngine.store.cards
	}

	private var featuredSuggestion: SuggestionCard? {
		suggestionCards.first
	}

	var body: some View {
		@Bindable var presenceMode = presenceMode

		ZStack(alignment: .top) {
			SocialMapView(cameraPosition: $cameraPosition)
				.ignoresSafeArea()

			VStack(spacing: 10) {
				header
					.padding(.horizontal, 16)

				if locationManager.isDenied, friendsStore.selectedFriend == nil {
					locationDeniedBanner
						.padding(.horizontal, 16)
						.transition(.move(edge: .top).combined(with: .opacity))
				}

				if let pulse = pulseInbox.activePulses.first, friendsStore.selectedFriend == nil {
					PulseInboxBanner(
						pulse: pulse,
						onAccept: { presentedPulse = pulse },
						onDismiss: { Task { await pulseInbox.acknowledge(pulse) } }
					)
					.padding(.horizontal, 16)
					.transition(.move(edge: .top).combined(with: .opacity))
					.onTapGesture { presentedPulse = pulse }
				}
			}
			.padding(.top, 8)
			.opacity(showsFloatingMapChrome ? 1 : 0)
			.allowsHitTesting(showsFloatingMapChrome)
			.animation(.easeInOut(duration: 0.2), value: showsFloatingMapChrome)
			.zIndex(1)

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
						composeDraft = .from(person: selected)
						friendsStore.clearSelection()
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
				// Clear the floating tab pill; card layout/spacing stays unchanged.
				.padding(.bottom, 100)
				.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
				.transition(.move(edge: .bottom).combined(with: .opacity))
				.zIndex(2)
			}
		}
		// Find My pattern: persistent suggestions sheet floats above the shared
		// system tab bar. Peek on launch → drag up for the full sheet.
		.overlay(alignment: .bottom) {
			if showsFloatingMapChrome {
				suggestionsFindMySheet
					.frame(height: suggestionsPanelHeight, alignment: .top)
					.padding(.horizontal, 10)
					.padding(.bottom, 8)
					.transition(.move(edge: .bottom).combined(with: .opacity))
			}
		}
		.animation(.spring(response: 0.34, dampingFraction: 0.86), value: friendsStore.selectedFriendID)
		.animation(.snappy, value: showsFloatingMapChrome)
		.animation(.snappy, value: suggestionsDetent)
		.sheet(item: $presentedPulse) { pulse in
			PulseInviteDetailView(
				pulse: pulse,
				attendees: [
					.init(id: pulse.senderUserId, displayName: pulse.senderDisplayName),
				],
				goingCount: 1,
				maybeCount: 0,
				onGoing: {
					presentedPulse = nil
					Task { await acceptIncomingPulse(pulse) }
				},
				onMaybe: {
					presentedPulse = nil
					Task {
						await pulseInbox.acknowledge(pulse)
						meetupMemoryStore.recordMeetup(
							friendUserId: pulse.senderUserId,
							friendDisplayName: pulse.senderDisplayName,
							venueName: pulse.payload.venueName,
							source: .pulse,
							outcome: .pending
						)
						showToast("Maybe on \(pulse.senderDisplayName)'s Pulse")
					}
				}
			)
			.presentationDetents([.large])
			.presentationDragIndicator(.hidden)
		}
		.task {
			await runMapSession()
		}
		.onChange(of: locationManager.hasFix) { _, hasFix in
			guard hasFix else { return }
			centerOnUserIfNeeded(force: !didCenterOnAccurateFix)
			Task { await friendsStore.refresh(around: locationManager.displayCoordinate) }
			publishLocation(force: true)
		}
		.onChange(of: locationManager.userLocation?.timestamp) { _, _ in
			publishLocation(force: false)
			if locationManager.hasAccurateFix, !didCenterOnAccurateFix {
				centerOnUserIfNeeded(force: true)
			}
		}
		.onChange(of: pairedFriends.graphRevision) { _, _ in
			publishLocation(force: true)
			Task {
				await friendsStore.refresh(
					around: locationManager.displayCoordinate,
					friendSummaries: pairedFriends.friends
				)
				await refreshSuggestions()
			}
		}
		.onChange(of: friendsStore.selectedFriendID) { _, selectedID in
			if selectedID != nil {
				withAnimation(.snappy) {
					isPresencePickerExpanded = false
					suggestionsDetent = .peek
					suggestionsDragOffset = 0
				}
			}
		}
		.onChange(of: presenceMode.state) { _, _ in
			withAnimation(.snappy) { isPresencePickerExpanded = false }
			publishLocation(force: true)
		}
		.sheet(isPresented: $showFriendsOnlyPicker) {
			FriendsOnlyPickerSheet {
				publishLocation(force: true)
			}
		}
		.overlay(alignment: .top) {
			if let ctaToast {
				Text(ctaToast)
					.font(.footnote.weight(.semibold))
					.padding(.horizontal, 14)
					.padding(.vertical, 10)
					.background(.ultraThinMaterial, in: Capsule())
					.padding(.top, 72)
					.transition(.move(edge: .top).combined(with: .opacity))
			}
		}
		.animation(.snappy, value: ctaToast)
	}

	private var suggestionsPanelHeight: CGFloat {
		let screen = UIScreen.main.bounds.height
		let base = suggestionsDetent.height(in: screen)
		return max(72, base - suggestionsDragOffset)
	}

	// MARK: - Find My suggestions sheet

	private var suggestionsFindMySheet: some View {
		VStack(spacing: 0) {
			suggestionsGrabber
				.gesture(suggestionsDragGesture)

			if suggestionsDetent == .peek {
				peekSuggestionsContent
					.gesture(suggestionsDragGesture)
			} else {
				expandedSuggestionsContent
			}
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
		.glassEffect(.regular, in: .rect(cornerRadius: suggestionsDetent == .peek ? 28 : 34))
	}

	private var suggestionsGrabber: some View {
		Capsule()
			.fill(.secondary.opacity(0.45))
			.frame(width: 36, height: 5)
			.padding(.top, 10)
			.padding(.bottom, suggestionsDetent == .peek ? 4 : 8)
			.frame(maxWidth: .infinity)
			.contentShape(Rectangle())
			.onTapGesture {
				let next: SuggestionsSheetDetent =
					suggestionsDetent == .expanded ? .peek : suggestionsDetent.next
				withAnimation(.snappy) {
					suggestionsDetent = next
					suggestionsDragOffset = 0
				}
				if next != .peek {
					Task { await refreshSuggestionsIfStale() }
				}
			}
	}

	private var suggestionsDragGesture: some Gesture {
		DragGesture(minimumDistance: 8, coordinateSpace: .local)
			.onChanged { value in
				// Only follow vertical drag; clamp so the panel never collapses past peek.
				let minHeight = SuggestionsSheetDetent.peek.height(in: UIScreen.main.bounds.height)
				let maxHeight = SuggestionsSheetDetent.expanded.height(in: UIScreen.main.bounds.height)
				let current = suggestionsDetent.height(in: UIScreen.main.bounds.height)
				let proposed = current - value.translation.height
				let clamped = min(maxHeight, max(minHeight, proposed))
				suggestionsDragOffset = current - clamped
			}
			.onEnded { value in
				let next = suggestionsDetent.advancing(by: value.translation.height)
				withAnimation(.snappy) {
					suggestionsDetent = next
					suggestionsDragOffset = 0
				}
				if next != .peek {
					Task { await refreshSuggestionsIfStale() }
				}
			}
	}

	@ViewBuilder
	private var peekSuggestionsContent: some View {
		if let card = featuredSuggestion {
			featuredSuggestionBar(card)
		} else {
			emptySuggestionsBar
		}
	}

	private var expandedSuggestionsContent: some View {
		VStack(spacing: 0) {
			HStack {
				Text("Suggestions")
					.font(.title2.weight(.bold))
				Spacer(minLength: 0)
			}
			.padding(.horizontal, 20)
			.padding(.bottom, 8)

			AIContextInsightsView(
				cards: suggestionCards,
				statusMessage: suggestionEngine.store.statusMessage,
				interestSuggestions: interestSuggestionStore.pending,
				showsHeader: false,
				onSelectFriend: { card in
					withAnimation(.snappy) { suggestionsDetent = .peek }
					friendsStore.select(card.friendID)
				},
				onCTA: { card in
					withAnimation(.snappy) { suggestionsDetent = .peek }
					composeDraft = .from(card: card)
				},
				onDismiss: { card in
					recordSuggestionFeedback(card, action: .dismissed)
					suggestionEngine.store.replace(
						cards: suggestionCards.filter { $0.id != card.id },
						usedModel: suggestionEngine.store.usedFoundationModels,
						status: suggestionEngine.store.statusMessage,
						userCoordinate: locationManager.userCoordinate
					)
					showToast("Dismissed \(card.displayName)")
				},
				onFeedback: { card, action in
					recordSuggestionFeedback(card, action: action)
					showToast(action == .up ? "Thanks — noted" : "Got it — will tune suggestions")
				},
				onAppearCard: { card in
					guard !recordedShownCardIDs.contains(card.id) else { return }
					recordedShownCardIDs.insert(card.id)
					recordSuggestionFeedback(card, action: .shown)
				},
				onAcceptInterest: { interestID in
					Task { await acceptInterestSuggestion(interestID) }
				},
				onDismissInterest: { interestID in
					interestSuggestionStore.dismiss(interestID)
				}
			)
		}
	}

	private func featuredSuggestionBar(_ card: SuggestionCard) -> some View {
		HStack(spacing: 12) {
			Button {
				withAnimation(.snappy) { suggestionsDetent = .medium }
				Task { await refreshSuggestionsIfStale() }
			} label: {
				HStack(spacing: 10) {
					Image(systemName: "person.crop.circle.fill")
						.resizable()
						.scaledToFit()
						.foregroundStyle(.white)
						.padding(6)
						.frame(width: 36, height: 36)
						.background(
							KismetTheme.Map.ring(for: card.availability).gradient,
							in: Circle()
						)

					VStack(alignment: .leading, spacing: 2) {
						Text("\(card.displayName), \(card.formattedDistance)")
							.font(.subheadline.weight(.semibold))
							.foregroundStyle(.primary)
							.lineLimit(1)

						Text(featuredSubtitle(for: card))
							.font(.caption2)
							.foregroundStyle(.secondary)
							.lineLimit(1)
					}

					Spacer(minLength: 0)
				}
				.contentShape(Rectangle())
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Expand suggestions for \(card.displayName)")

			Button {
				composeDraft = .from(card: card)
			} label: {
				HStack(spacing: 5) {
					Image(systemName: card.ctaSystemImage)
						.font(.caption.weight(.semibold))
					Text(card.ctaTitle)
						.font(.caption.weight(.semibold))
						.lineLimit(1)
				}
				.padding(.horizontal, 12)
				.padding(.vertical, 10)
				.foregroundStyle(KismetTheme.Insight.ctaForeground(for: card.availability))
				.background(
					KismetTheme.Insight.ctaBackground(for: card.availability),
					in: Capsule()
				)
			}
			.buttonStyle(.plain)
			.fixedSize(horizontal: true, vertical: false)
			.accessibilityLabel(card.ctaTitle)
		}
		.padding(.horizontal, 16)
		.padding(.bottom, 12)
		.frame(maxWidth: .infinity, minHeight: 52)
	}

	private var emptySuggestionsBar: some View {
		Button {
			withAnimation(.snappy) { suggestionsDetent = .medium }
			Task { await refreshSuggestionsIfStale() }
		} label: {
			HStack(spacing: 10) {
				ZStack {
					Image(systemName: "sparkles")
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(KismetTheme.Status.free)
						.opacity(suggestionEngine.store.isRefreshing ? 0 : 1)
					if suggestionEngine.store.isRefreshing {
						ProgressView()
							.controlSize(.small)
					}
				}
				.frame(width: 18, height: 18)

				VStack(alignment: .leading, spacing: 2) {
					Text("Suggestions")
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(.primary)

					Text(emptySuggestionsSubtitle)
						.font(.caption2)
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}

				Spacer(minLength: 0)

				Image(systemName: "chevron.up")
					.font(.caption.weight(.bold))
					.foregroundStyle(.tertiary)
			}
			.padding(.horizontal, 16)
			.padding(.bottom, 12)
			.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel("Expand Suggestions")
		.accessibilityHint(emptySuggestionsSubtitle)
	}

	private var emptySuggestionsSubtitle: String {
		if suggestionEngine.store.isRefreshing {
			return "Looking nearby…"
		}
		return suggestionEngine.store.statusMessage ?? "Nothing nearby right now"
	}

	private func featuredSubtitle(for card: SuggestionCard) -> String {
		let chips = card.factChips.prefix(3)
		if chips.isEmpty {
			return card.reason
		}
		return chips.joined(separator: " · ")
	}

	private func recordSuggestionFeedback(_ card: SuggestionCard, action: SuggestionFeedbackAction) {
		meetupMemoryStore.recordFeedback(
			friendUserId: card.friendID,
			action: action,
			reasonCodes: card.reasonCodes.map(\.rawValue)
		)
	}

	@MainActor
	private func refreshSuggestionsIfStale() async {
		let last = suggestionEngine.store.lastUpdatedAt
		let isStale = last.map { Date().timeIntervalSince($0) > 120 } ?? true
		guard isStale || suggestionCards.isEmpty else { return }
		await refreshSuggestions()
	}

	@MainActor
	private func acceptInterestSuggestion(_ interestID: String) async {
		var next = Set(authSession.user?.interests ?? [])
		next.insert(interestID)
		let ok = await authSession.saveInterests(Array(next).sorted())
		if ok {
			interestSuggestionStore.removeAccepted(interestID)
			showToast("Added \(InterestCatalog.displayName(for: interestID))")
			interestSuggestionStore.refresh(
				meetups: meetupMemoryStore.meetupSnapshots(),
				currentInterests: authSession.user?.interests ?? Array(next)
			)
		} else {
			showToast("Couldn't save interest")
		}
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
						.fill(presenceMode.state.statusColor)
						.frame(width: 11, height: 11)
						.overlay {
							Circle().stroke(.background, lineWidth: 2)
						}
						.accessibilityLabel(presenceMode.state.title)
				}

				VStack(alignment: .leading, spacing: 2) {
					Text(displayName)
						.font(.headline)
						.foregroundStyle(KismetTheme.Map.headerForeground)
						.lineLimit(1)

					Text(locationSubtitle)
						.font(.caption)
						.foregroundStyle(KismetTheme.Map.secondaryLabel)
						.lineLimit(1)
				}
			}

			Spacer(minLength: 8)

			// Keeps bar height stable; menu expands downward via overlay.
			Color.clear
				.frame(width: KismetTheme.Chrome.avatarSize, height: KismetTheme.Chrome.avatarSize)
		}
		.padding(.horizontal, 14)
		.padding(.vertical, 10)
		.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: KismetTheme.Chrome.headerCornerRadius, style: .continuous))
		.shadow(color: .black.opacity(0.08), radius: 12, y: 4)
		.overlay(alignment: .topTrailing) {
			VStack(alignment: .trailing, spacing: 10) {
				PresenceModePicker(
					selection: Bindable(presenceMode).state,
					isExpanded: $isPresencePickerExpanded,
					onSelectFriendsOnly: { showFriendsOnlyPicker = true }
				)
				recenterOnUserButton
			}
			.padding(.top, 10)
			.padding(.trailing, 14)
		}
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

	private var recenterOnUserButton: some View {
		Button {
			recenter(on: locationManager.displayCoordinate)
		} label: {
			Image(systemName: "location.fill")
				.font(.system(size: 15, weight: .semibold))
				.foregroundStyle(.primary)
				.frame(width: 40, height: 40)
				.background(.ultraThinMaterial, in: Circle())
				.shadow(color: .black.opacity(0.12), radius: 8, y: 2)
		}
		.buttonStyle(.plain)
		.accessibilityLabel("Center on my location")
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
					await mapStore.refresh(
						around: locations.displayCoordinate,
						friendSummaries: socialStore.friends
					)
					await pulseInbox.refresh(friends: socialStore.friends)
					await consumeSharedMeetups()
					await refreshSuggestions()
				case "friend.pair.created":
					await socialStore.refresh(force: true)
					await mapStore.refresh(
						around: locations.displayCoordinate,
						friendSummaries: socialStore.friends
					)
					sharing.shareIfNeeded(
						location: locations.userLocation,
						senderUserId: KeychainStore.get(.userId),
						friends: socialStore.friends,
						presence: presenceMode.state,
						friendsOnlyVisibleIds: friendsOnlyVisibility.visibleFriendIds,
						force: true
					)
					await pulseInbox.refresh(friends: socialStore.friends)
					await refreshSuggestions()
				case "friend.pair.revoked":
					await socialStore.refresh(force: true)
					await mapStore.refresh(
						around: locations.displayCoordinate,
						friendSummaries: socialStore.friends
					)
					pulseInbox.reset()
					await refreshSuggestions()
				default:
					await socialStore.refresh()
					await mapStore.refresh(
						around: locations.displayCoordinate,
						friendSummaries: socialStore.friends
					)
					await pulseInbox.refresh(friends: socialStore.friends)
				}
			}
		}
		realtime.connect()

		defer {
			realtime.onMapEvent = nil
			realtime.disconnect()
			// Background proximity owns sharing while signed in; don't kill uploads on tab leave.
			if !backgroundProximity.isEnabled {
				sharing.stop()
			}
		}

		await bootstrapMap()
		guard !Task.isCancelled else { return }

		// Light poll: friends + pulses only. Suggestions refresh on events / sheet expand.
		while !Task.isCancelled {
			do {
				try await Task.sleep(for: .seconds(45))
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
		guard !Task.isCancelled else { return }

		// One map refresh using the friend list we just loaded — avoids a second
		// `/friends` round-trip and the old duplicate refresh after a 50ms sleep.
		await friendsStore.refresh(
			around: locationManager.displayCoordinate,
			friendSummaries: pairedFriends.friends
		)
		await pulseInbox.refresh(friends: pairedFriends.friends)
		await processPendingWidgetPulseAccept()

		guard !Task.isCancelled else { return }
		recenter(on: locationManager.displayCoordinate)
		await friendsStore.refresh(around: locationManager.displayCoordinate)
		publishLocation(force: true)
		await refreshSuggestions()
	}

	@MainActor
	private func processPendingWidgetPulseAccept() async {
		guard let blobId = AppGroup.pendingAcceptPulseBlobId else { return }
		AppGroup.pendingAcceptPulseBlobId = nil
		guard let pulse = pulseInbox.activePulses.first(where: { $0.blobId == blobId })
			?? pulseInbox.pulses.first(where: { $0.blobId == blobId })
		else { return }
		await acceptIncomingPulse(pulse)
	}

	private func refreshMapData() async {
		await pairedFriends.refresh()
		await friendsStore.refresh(
			around: locationManager.displayCoordinate,
			friendSummaries: pairedFriends.friends
		)
		await pulseInbox.refresh(friends: pairedFriends.friends)
		await consumeSharedMeetups()
		await refreshSuggestions()
	}

	@MainActor
	private func acceptIncomingPulse(_ pulse: IncomingPulse) async {
		await pulseInbox.acknowledge(pulse)
		meetupMemoryStore.recordMeetup(
			friendUserId: pulse.senderUserId,
			friendDisplayName: pulse.senderDisplayName,
			venueName: pulse.payload.venueName,
			source: .pulse,
			outcome: .pending
		)
		await startLiveActivity(for: pulse)
		await notifySenderOfMeetupAccept(pulse)
		let venue = pulse.payload.venueName.map { " · \($0)" } ?? ""
		showToast("Accepted \(pulse.senderDisplayName)'s Pulse\(venue)")
	}

	@MainActor
	private func notifySenderOfMeetupAccept(_ pulse: IncomingPulse) async {
		guard let myId = authSession.user?.id ?? KeychainStore.get(.userId) else { return }
		let payload = MeetupPayloadDTO(
			meetupId: pulse.payload.pulseId,
			title: pulse.payload.label,
			venueName: pulse.payload.venueName,
			venueLatitude: pulse.payload.venueLatitude,
			venueLongitude: pulse.payload.venueLongitude,
			meetAt: pulse.payload.plannedAt,
			peerDisplayName: authSession.preferredDisplayName,
			systemImage: "figure.walk",
			createdAt: Date()
		)
		await MeetupSharingService().notifyPeerOfAccept(
			payload: payload,
			senderUserId: myId,
			peerUserId: pulse.senderUserId,
			friends: pairedFriends.friends
		)
	}

	@MainActor
	private func startLiveActivity(for pulse: IncomingPulse) async {
		let venueName = pulse.payload.venueName ?? pulse.payload.label
		let youName = authSession.preferredDisplayName
		let participants: [MeetupActivityAttributes.Participant] = [
			.init(
				id: KeychainStore.get(.userId) ?? "you",
				displayName: youName,
				initials: String(youName.prefix(1)).uppercased(),
				status: .nearby,
				isYou: true
			),
			.init(
				id: pulse.senderUserId,
				displayName: pulse.senderDisplayName,
				initials: String(pulse.senderDisplayName.prefix(1)).uppercased(),
				status: .free,
				isYou: false
			)
		]
		do {
			_ = try await MeetupLiveActivityController.start(
				meetupID: pulse.payload.pulseId,
				title: pulse.payload.label,
				venueName: venueName,
				systemImage: "figure.walk",
				participants: participants,
				venueCoordinate: pulse.payload.venueCoordinate,
				meetAt: pulse.payload.plannedAt,
				currentLocation: locationManager.userLocation
			)
		} catch {
			// Live Activities may be disabled — Pulse accept still succeeds.
		}
	}

	@MainActor
	private func startLiveActivityFromMeetup(
		senderUserId: String,
		payload: MeetupPayloadDTO
	) async {
		let peerName = pairedFriends.friends.first(where: { $0.userId == senderUserId })?.displayName
			?? payload.peerDisplayName
		let youName = authSession.preferredDisplayName
		let venueName = payload.venueName ?? payload.title
		let participants: [MeetupActivityAttributes.Participant] = [
			.init(
				id: KeychainStore.get(.userId) ?? "you",
				displayName: youName,
				initials: String(youName.prefix(1)).uppercased(),
				status: .nearby,
				isYou: true
			),
			.init(
				id: senderUserId,
				displayName: peerName,
				initials: String(peerName.prefix(1)).uppercased(),
				status: .free,
				isYou: false
			)
		]
		do {
			_ = try await MeetupLiveActivityController.start(
				meetupID: payload.meetupId,
				title: payload.title,
				venueName: venueName,
				systemImage: payload.systemImage,
				participants: participants,
				venueCoordinate: payload.venueCoordinate,
				meetAt: payload.meetAt,
				currentLocation: locationManager.userLocation
			)
			showToast("\(peerName) accepted — meetup Live Activity started")
		} catch {
			// Disabled or already active — ignore.
		}
	}

	@MainActor
	private func consumeSharedMeetups() async {
		let meetups = await MeetupSharingService().consumePendingMeetups(friends: pairedFriends.friends)
		for item in meetups {
			await startLiveActivityFromMeetup(senderUserId: item.senderUserId, payload: item.payload)
		}
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
		interestSuggestionStore.refresh(
			meetups: meetupMemoryStore.meetupSnapshots(),
			currentInterests: authSession.user?.interests ?? []
		)
	}

	private func publishLocation(force: Bool) {
		locationSharing.shareIfNeeded(
			location: locationManager.userLocation,
			senderUserId: authSession.user?.id ?? KeychainStore.get(.userId),
			friends: pairedFriends.friends,
			presence: presenceMode.state,
			friendsOnlyVisibleIds: friendsOnlyVisibility.visibleFriendIds,
			force: force
		)
	}

	private func centerOnUserIfNeeded(force: Bool) {
		guard locationManager.hasAccurateFix else { return }
		guard force || !didCenterOnAccurateFix else { return }
		recenter(on: locationManager.displayCoordinate)
		didCenterOnAccurateFix = true
		Task {
			await friendsStore.refresh(
				around: locationManager.displayCoordinate,
				friendSummaries: pairedFriends.friends
			)
		}
		publishLocation(force: true)
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
	@State private var meetupMemoryStore = MeetupMemoryStore(
		container: try! MeetupModelContainer.makeInMemory()
	)
	@State private var interestSuggestionStore = InterestSuggestionStore()
	@State private var presenceMode = PresenceModeStore(state: .available)
	@State private var friendsOnlyVisibility = FriendsOnlyVisibilityStore()
	@State private var pulseInbox = PulseInboxStore()
	@State private var composeDraft: PulseComposeDraft?

	var body: some View {
		MapHomeView(composeDraft: $composeDraft)
			.environment(authSession)
			.environment(locationManager)
			.environment(friendsStore)
			.environment(pairedFriends)
			.environment(locationSharing)
			.environment(
				BackgroundProximityController(
					locationManager: locationManager,
					locationSharing: locationSharing,
					friendsStore: pairedFriends,
					mapFriendsStore: friendsStore,
					presenceMode: presenceMode,
					friendsOnlyVisibility: friendsOnlyVisibility
				)
			)
			.environment(realtimeClient)
			.environment(suggestionEngine)
			.environment(meetupMemoryStore)
			.environment(interestSuggestionStore)
			.environment(presenceMode)
			.environment(friendsOnlyVisibility)
			.environment(pulseInbox)
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
