import SwiftUI

enum AppTab: String, CaseIterable, Hashable, Identifiable {
	case map
	case radar
	case more

	var id: String { rawValue }

	var title: String {
		switch self {
		case .map: "Map"
		case .radar: "Radar"
		case .more: "More"
		}
	}

	var icon: String {
		switch self {
		case .map: "map"
		case .radar: "scope"
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

	@State private var selectedTab: AppTab = .map
	@State private var ctaToast: String?
	@State private var composeDraft: PulseComposeDraft?

	var body: some View {
		TabView(selection: $selectedTab) {
			Tab(AppTab.map.title, systemImage: AppTab.map.icon, value: AppTab.map) {
				MapHomeView(composeDraft: $composeDraft)
			}

			Tab(AppTab.radar.title, systemImage: AppTab.radar.icon, value: AppTab.radar) {
				RadarView(embedded: false)
			}

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
					.transition(.opacity)
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
		.onChange(of: selectedTab) { _, newTab in
			if newTab != .map {
				friendsStore.clearSelection()
			}
		}
		.ignoresSafeArea(.keyboard)
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
