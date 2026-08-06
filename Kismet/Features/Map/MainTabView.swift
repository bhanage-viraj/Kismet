import SwiftUI

enum AppTab: String, CaseIterable, Hashable, Identifiable {
	case map
	case radar
	case timeline
	case more

	var id: String { rawValue }

	var title: String {
		switch self {
		case .map: "Map"
		case .radar: "Radar"
		case .timeline: "Timeline"
		case .more: "More"
		}
	}

	var icon: String {
		switch self {
		case .map: "map"
		case .radar: "scope"
		case .timeline: "calendar"
		case .more: "ellipsis"
		}
	}
}

/// Sheet heights for the AI insights bottom accessory.
private enum InsightsDetent: Int, CaseIterable, Comparable {
	case collapsed
	case medium
	case expanded

	static func < (lhs: InsightsDetent, rhs: InsightsDetent) -> Bool {
		lhs.rawValue < rhs.rawValue
	}

	var contentHeight: CGFloat? {
		switch self {
		case .collapsed: nil
		// Tall enough to show one full card + a peek of the next, so scrolling is obvious.
		case .medium: 280
		case .expanded: 420
		}
	}

	func advancing(by translation: CGFloat) -> InsightsDetent {
		// Negative translation = drag up = expand.
		if translation < -48 { return next }
		if translation > 48 { return previous }
		return self
	}

	var next: InsightsDetent {
		InsightsDetent(rawValue: rawValue + 1) ?? self
	}

	var previous: InsightsDetent {
		InsightsDetent(rawValue: rawValue - 1) ?? self
	}
}

struct MainTabView: View {
	@Environment(MapFriendsStore.self) private var friendsStore
	@Environment(FriendsStore.self) private var pairedFriends
	@Environment(AuthSession.self) private var authSession
	@Environment(SuggestionEngine.self) private var suggestionEngine
	@Environment(PulsePublisher.self) private var pulsePublisher
	@Environment(MeetupMemoryStore.self) private var meetupMemoryStore
	@Environment(InterestSuggestionStore.self) private var interestSuggestionStore

	@State private var selectedTab: AppTab = .map
	@State private var insightsDetent: InsightsDetent = .collapsed
	@State private var dragOffset: CGFloat = 0
	@State private var ctaToast: String?
	@State private var recordedShownCardIDs: Set<String> = []
	@State private var pulseComposeCard: SuggestionCard?
	@Namespace private var glassNamespace

	/// Insights card floats above the native tab bar (Map only, no person detail).
	private var showsInsights: Bool {
		selectedTab == .map && friendsStore.selectedFriend == nil
	}

	private var suggestionCards: [SuggestionCard] {
		suggestionEngine.store.cards
	}

	private var expandedContentHeight: CGFloat {
		let base = insightsDetent.contentHeight ?? 0
		// Drag down shrinks; drag up peeks taller until snap.
		return max(120, base - dragOffset)
	}

	var body: some View {
		ZStack {
			TabView(selection: $selectedTab) {
				Tab(AppTab.map.title, systemImage: AppTab.map.icon, value: AppTab.map) {
					mapTabRoot
				}

				Tab(AppTab.radar.title, systemImage: AppTab.radar.icon, value: AppTab.radar) {
					RadarView(embedded: false)
				}

				Tab(AppTab.timeline.title, systemImage: AppTab.timeline.icon, value: AppTab.timeline) {
					TimelineView(embedded: false)
				}

				Tab(AppTab.more.title, systemImage: AppTab.more.icon, value: AppTab.more) {
					MoreView(embedded: false)
				}
			}
			.tabBarMinimizeBehavior(.onScrollDown)

			if let ctaToast {
				Text(ctaToast)
					.font(.footnote.weight(.semibold))
					.padding(.horizontal, 14)
					.padding(.vertical, 10)
					.background(.ultraThinMaterial, in: Capsule())
					.padding(.top, 72)
					.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
					.zIndex(9)
			}
		}
		.onChange(of: selectedTab) { _, _ in
			insightsDetent = .collapsed
			dragOffset = 0
		}
		.onChange(of: friendsStore.selectedFriendID) { _, _ in
			insightsDetent = .collapsed
			dragOffset = 0
		}
		.animation(.snappy, value: showsInsights)
		.animation(.snappy, value: insightsDetent)
		.ignoresSafeArea(.keyboard)
		.sheet(item: $pulseComposeCard) { card in
			PulseComposeSheet(
				card: card,
				onSend: { outgoing in
					Task { await sendPulse(for: outgoing) }
				},
				onCancel: {
					pulseComposeCard = nil
				}
			)
		}
	}

	private var mapTabRoot: some View {
		MapHomeView()
			// Sits just above the native tab bar with a small gap.
			.safeAreaInset(edge: .bottom, spacing: 8) {
				if showsInsights {
					insightsAccessory
						.glassEffect(
							.regular,
							in: .rect(cornerRadius: insightsDetent == .collapsed ? 22 : 28)
						)
						.glassEffectID("insights", in: glassNamespace)
						.padding(.horizontal, 16)
						.padding(.bottom, 8)
						.transition(.move(edge: .bottom).combined(with: .opacity))
				}
			}
	}

	@ViewBuilder
	private var insightsAccessory: some View {
		VStack(spacing: 0) {
			if insightsDetent != .collapsed {
				detentGrabber
					.gesture(insightsDragGesture)
			}

			if insightsDetent == .collapsed {
				collapsedAccessory
					.gesture(insightsDragGesture)
			} else {
				AIContextInsightsView(
					cards: suggestionCards,
					statusMessage: suggestionEngine.store.statusMessage,
					interestSuggestions: interestSuggestionStore.pending,
					showsHeader: true,
					onSelectFriend: { card in
						friendsStore.select(card.friendID)
					},
					onCTA: { card in
						presentPulseCompose(for: card)
					},
					onDismiss: { card in
						recordFeedback(card, action: .dismissed)
						suggestionEngine.store.replace(
							cards: suggestionCards.filter { $0.id != card.id },
							usedModel: suggestionEngine.store.usedFoundationModels,
							status: suggestionEngine.store.statusMessage
						)
						showToast("Dismissed \(card.displayName)")
					},
					onFeedback: { card, action in
						recordFeedback(card, action: action)
						showToast(action == .up ? "Thanks — noted" : "Got it — will tune suggestions")
					},
					onAppearCard: { card in
						guard !recordedShownCardIDs.contains(card.id) else { return }
						recordedShownCardIDs.insert(card.id)
						recordFeedback(card, action: .shown)
					},
					onAcceptInterest: { interestID in
						Task { await acceptInterestSuggestion(interestID) }
					},
					onDismissInterest: { interestID in
						interestSuggestionStore.dismiss(interestID)
					}
				)
				.frame(height: expandedContentHeight)
				.clipped()
				.padding(.bottom, 10)
			}
		}
	}

	private var detentGrabber: some View {
		Capsule()
			.fill(.secondary.opacity(0.45))
			.frame(width: 36, height: 5)
			.padding(.top, 10)
			.padding(.bottom, 8)
			.frame(maxWidth: .infinity)
			.contentShape(Rectangle())
			.onTapGesture {
				withAnimation(.snappy) {
					insightsDetent = insightsDetent.next == insightsDetent ? .collapsed : insightsDetent.next
				}
			}
	}

	private var collapsedAccessory: some View {
		Button {
			withAnimation(.snappy) { insightsDetent = .medium }
		} label: {
			HStack(spacing: 10) {
				Image(systemName: "sparkles")
					.font(.subheadline.weight(.semibold))
					.foregroundStyle(KismetTheme.Status.free)

				VStack(alignment: .leading, spacing: 2) {
					Text("Suggestions")
						.font(.subheadline.weight(.semibold))
						.foregroundStyle(.primary)

					Text(accessorySubtitle)
						.font(.caption2)
						.foregroundStyle(.secondary)
						.lineLimit(1)
				}

				Spacer(minLength: 0)

				Image(systemName: "chevron.up")
					.font(.caption.weight(.bold))
					.foregroundStyle(.secondary)
			}
			.padding(.horizontal, 16)
			.padding(.vertical, 14)
			.contentShape(Rectangle())
		}
		.buttonStyle(.plain)
		.accessibilityLabel("Expand Suggestions")
	}

	private var accessorySubtitle: String {
		let count = suggestionCards.count
		if count == 0 {
			return suggestionEngine.store.statusMessage ?? "Nothing nearby right now"
		}
		if count == 1 {
			let name = suggestionCards[0].displayName
			return "\(name) — tap to reconnect"
		}
		return "\(count) suggestions"
	}

	private var insightsDragGesture: some Gesture {
		DragGesture(minimumDistance: 12, coordinateSpace: .local)
			.onChanged { value in
				guard showsInsights else { return }
				if insightsDetent == .collapsed {
					// Pull up from accessory to peek into medium.
					dragOffset = min(0, value.translation.height)
				} else {
					dragOffset = value.translation.height
				}
			}
			.onEnded { value in
				guard showsInsights else {
					dragOffset = 0
					return
				}

				let next: InsightsDetent
				if insightsDetent == .collapsed, value.translation.height < -40 {
					next = .medium
				} else {
					next = insightsDetent.advancing(by: value.translation.height)
				}

				withAnimation(.snappy) {
					insightsDetent = next
					dragOffset = 0
				}
			}
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

	@MainActor
	private func presentPulseCompose(for card: SuggestionCard) {
		// Optional picker: only when MapKit candidates exist. Otherwise send with defaults.
		if card.venueCandidates != nil {
			pulseComposeCard = card
		} else {
			Task { await sendPulse(for: card) }
		}
	}

	@MainActor
	private func sendPulse(for card: SuggestionCard) async {
		do {
			let pulse = try await pulsePublisher.send(
				from: card,
				senderUserId: authSession.user?.id ?? KeychainStore.get(.userId),
				friends: pairedFriends.friends
			)
			recordFeedback(card, action: .cta)
			meetupMemoryStore.recordMeetup(
				friendUserId: card.friendID,
				friendDisplayName: card.displayName,
				venueName: card.venueName,
				source: .pulse,
				outcome: .pending
			)
			let venue = card.venueName.map { " · \($0)" } ?? ""
			showToast("Pulse sent to \(card.displayName)\(venue)")
			pulseComposeCard = nil
			_ = pulse
		} catch {
			showToast((error as? LocalizedError)?.errorDescription ?? "Couldn't send Pulse")
		}
	}

	private func recordFeedback(_ card: SuggestionCard, action: SuggestionFeedbackAction) {
		meetupMemoryStore.recordFeedback(
			friendUserId: card.friendID,
			action: action,
			reasonCodes: card.reasonCodes.map(\.rawValue)
		)
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
}

#if DEBUG
#Preview("Light") {
	MainTabPreviewHost()
		.preferredColorScheme(.light)
}

#Preview("Dark") {
	MainTabPreviewHost()
		.preferredColorScheme(.dark)
}

private struct MainTabPreviewHost: View {
	@State private var authSession: AuthSession
	@State private var locationManager: VisitLocationManager
	@State private var mapFriendsStore: MapFriendsStore
	@State private var friendsStore: FriendsStore
	@State private var locationSharing: LocationSharingService
	@State private var realtimeClient: RealtimeClient
	@State private var suggestionEngine: SuggestionEngine
	@State private var pulsePublisher: PulsePublisher
	@State private var meetupMemoryStore: MeetupMemoryStore
	@State private var interestSuggestionStore: InterestSuggestionStore
	@State private var presenceMode: PresenceModeStore
	@State private var friendsOnlyVisibility: FriendsOnlyVisibilityStore
	@State private var pulseInbox: PulseInboxStore
	@State private var backgroundProximity: BackgroundProximityController

	init() {
		let authSession = AuthSession.previewSignedIn()
		let locationManager = VisitLocationManager()
		let mapFriendsStore = MapFriendsStore()
		mapFriendsStore.loadPreviewMocks(around: MockFriendsProvider.fallbackCoordinate)
		let friendsStore = FriendsStore.preview()
		let locationSharing = LocationSharingService()
		let presenceMode = PresenceModeStore(state: .available)
		let friendsOnlyVisibility = FriendsOnlyVisibilityStore()

		_authSession = State(initialValue: authSession)
		_locationManager = State(initialValue: locationManager)
		_mapFriendsStore = State(initialValue: mapFriendsStore)
		_friendsStore = State(initialValue: friendsStore)
		_locationSharing = State(initialValue: locationSharing)
		_realtimeClient = State(initialValue: RealtimeClient())
		_suggestionEngine = State(initialValue: SuggestionEngine())
		_pulsePublisher = State(initialValue: PulsePublisher())
		_meetupMemoryStore = State(initialValue: MeetupMemoryStore(
			container: try! MeetupModelContainer.makeInMemory()
		))
		_interestSuggestionStore = State(initialValue: InterestSuggestionStore())
		_presenceMode = State(initialValue: presenceMode)
		_friendsOnlyVisibility = State(initialValue: friendsOnlyVisibility)
		_pulseInbox = State(initialValue: PulseInboxStore())
		_backgroundProximity = State(initialValue: BackgroundProximityController(
			locationManager: locationManager,
			locationSharing: locationSharing,
			friendsStore: friendsStore,
			mapFriendsStore: mapFriendsStore,
			presenceMode: presenceMode,
			friendsOnlyVisibility: friendsOnlyVisibility
		))
	}

	var body: some View {
		MainTabView()
			.environment(authSession)
			.environment(locationManager)
			.environment(mapFriendsStore)
			.environment(friendsStore)
			.environment(locationSharing)
			.environment(backgroundProximity)
			.environment(realtimeClient)
			.environment(suggestionEngine)
			.environment(pulsePublisher)
			.environment(meetupMemoryStore)
			.environment(interestSuggestionStore)
			.environment(presenceMode)
			.environment(friendsOnlyVisibility)
			.environment(pulseInbox)
	}
}
#endif
