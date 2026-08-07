import SwiftUI

enum AppTab: String, CaseIterable, Hashable, Identifiable {
	case map
	case more

	var id: String { rawValue }

	var title: String {
		switch self {
		case .map: "Map"
		case .more: "More"
		}
	}

	var icon: String {
		switch self {
		case .map: "map"
		case .more: "ellipsis"
		}
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
	@State private var ctaToast: String?
	@State private var recordedShownCardIDs: Set<String> = []
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

			Tab(AppTab.more.title, systemImage: AppTab.more.icon, value: AppTab.more) {
				MoreView(embedded: false)
			}
		}
		// Shared system liquid-glass tab bar (Find My style). Suggestions are a
		// Map-only sheet above this bar — never tabViewBottomAccessory.
		.tabBarMinimizeBehavior(.never)
		.overlay(alignment: .top) {
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
						Task { await sendPulse(for: card) }
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
		.sheet(item: $composeDraft) { draft in
			PulseComposeSheetHost(
				draft: draft,
				isSending: pulsePublisher.isSending,
				onSend: { edited in
					Task { await sendPulse(draft: edited) }
				}
			)
			.presentationDetents([.large])
			.presentationDragIndicator(.visible)
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
	private func sendPulse(draft: PulseComposeDraft) async {
		do {
			let pulse = try await pulsePublisher.send(
				draft: draft,
				senderUserId: authSession.user?.id ?? KeychainStore.get(.userId),
				friends: pairedFriends.friends
			)
			if let cardID = draft.suggestionCardID,
			   let card = suggestionEngine.store.cards.first(where: { $0.id == cardID }) {
				meetupMemoryStore.recordFeedback(
					friendUserId: card.friendID,
					action: .cta,
					reasonCodes: card.reasonCodes.map(\.rawValue)
				)
			}
			meetupMemoryStore.recordMeetup(
				friendUserId: draft.recipientUserId,
				friendDisplayName: draft.recipientDisplayName,
				venueName: draft.venueName.isEmpty ? nil : draft.venueName,
				source: .pulse,
				outcome: .pending
			)
			composeDraft = nil
			let venue = draft.venueName.isEmpty ? "" : " · \(draft.venueName)"
			showToast("Pulse sent to \(draft.recipientDisplayName)\(venue)")
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
