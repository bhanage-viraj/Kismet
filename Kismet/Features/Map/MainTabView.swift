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
	@Environment(MapWeatherController.self) private var mapWeather
	@Environment(WeatherObstacleStore.self) private var weatherObstacleStore

	@State private var selectedTab: AppTab = .map
	@State private var insightsDetent: InsightsDetent = .collapsed
	@State private var dragOffset: CGFloat = 0
	@State private var ctaToast: String?
	@State private var recordedShownCardIDs: Set<String> = []
	@Namespace private var glassNamespace

	/// Insights accessory sits above the tab pill (Map only, no person detail).
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
		ZStack(alignment: .bottom) {
			tabContent
				.frame(maxWidth: .infinity, maxHeight: .infinity)

			GlassEffectContainer(spacing: 12) {
				VStack(spacing: 12) {
					if showsInsights {
						insightsAccessory
							// Track layout bounds before glassEffect (glass can swallow geometry probes).
							.trackWeatherObstacle(
								"chrome.insights",
								cornerRadius: insightsDetent == .collapsed ? 22 : 28
							)
							.glassEffect(
								.regular,
								in: .rect(cornerRadius: insightsDetent == .collapsed ? 22 : 28)
							)
							.glassEffectID("insights", in: glassNamespace)
					}

					GlassTabBar(selected: $selectedTab)
						.padding(.horizontal, 10)
						.padding(.vertical, 10)
						.trackWeatherObstacle("chrome.tabBar", cornerRadius: .infinity)
						.glassEffect(.regular, in: .capsule)
						.glassEffectID("tabbar", in: glassNamespace)
				}
				.padding(.horizontal, 16)
			}
			.animation(.snappy, value: showsInsights)
			.animation(.snappy, value: insightsDetent)

			if let ctaToast {
				Text(ctaToast)
					.font(.footnote.weight(.semibold))
					.padding(.horizontal, 14)
					.padding(.vertical, 10)
					.background(.ultraThinMaterial, in: Capsule())
					.trackWeatherObstacle("chrome.toast", cornerRadius: .infinity)
					.padding(.top, 72)
					.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
					.zIndex(9)
			}

			MapWeatherOverlay(
				condition: mapWeather.condition,
				intensity: mapWeather.intensity,
				obstacles: weatherObstacleStore.obstacles
			)
			.ignoresSafeArea()
			.zIndex(10)
		}
		.onAppear {
			weatherObstacleStore.remove("chrome.bottomStack")
		}
		.onChange(of: selectedTab) { _, _ in
			insightsDetent = .collapsed
			dragOffset = 0
		}
		.onChange(of: friendsStore.selectedFriendID) { _, _ in
			insightsDetent = .collapsed
			dragOffset = 0
		}
		.onChange(of: showsInsights) { _, show in
			if !show {
				weatherObstacleStore.remove("chrome.insights")
			}
			// Drop the old full-width stack probe if it was ever registered.
			weatherObstacleStore.remove("chrome.bottomStack")
		}
		.ignoresSafeArea(.keyboard)
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

	@ViewBuilder
	private var tabContent: some View {
		// Keep MapKit mounted across tabs. Destroying `Map` mid-frame races Metal
		// command buffers and trips MTLDebugDevice asserts in Debug.
		ZStack {
			MapHomeView()
				.opacity(selectedTab == .map ? 1 : 0)
				.allowsHitTesting(selectedTab == .map)
				.accessibilityHidden(selectedTab != .map)

			if selectedTab != .map {
				Group {
					switch selectedTab {
					case .map:
						EmptyView()
					case .radar:
						RadarView(embedded: false)
					case .timeline:
						TimelineView(embedded: false)
					case .more:
						MoreView(embedded: false)
					}
				}
				.safeAreaPadding(.bottom, 88)
				.transition(.opacity)
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

// MARK: - Tab bar content (glass capsule is applied by parent)

private struct GlassTabBar: View {
	@Binding var selected: AppTab

	var body: some View {
		HStack(spacing: 0) {
			ForEach(AppTab.allCases) { tab in
				Button {
					withAnimation(.snappy) { selected = tab }
				} label: {
					VStack(spacing: 4) {
						Image(systemName: tab.icon)
							.font(.system(size: 20))
						Text(tab.title)
							.font(.caption2)
							.lineLimit(1)
							.minimumScaleFactor(0.85)
					}
					.foregroundStyle(selected == tab ? Color.accentColor : .primary)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 2)
				}
				.buttonStyle(.plain)
			}
		}
		.padding(.horizontal, 6)
	}
}

// The preview helpers below are DEBUG-only, so the preview must be too —
// otherwise a Release build fails on symbols that were compiled out.
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
	@State private var authSession = AuthSession.previewSignedIn()
	@State private var locationManager = VisitLocationManager()
	@State private var mapFriendsStore = MapFriendsStore()
	@State private var friendsStore = FriendsStore.preview()
	@State private var locationSharing = LocationSharingService()
	@State private var realtimeClient = RealtimeClient()
	@State private var suggestionEngine = SuggestionEngine()
	@State private var pulsePublisher = PulsePublisher()
	@State private var mapWeather = MapWeatherController()
	@State private var weatherObstacles = WeatherObstacleStore()
	@State private var meetupMemoryStore = MeetupMemoryStore(
		container: try! MeetupModelContainer.makeInMemory()
	)
	@State private var interestSuggestionStore = InterestSuggestionStore()
	@State private var presenceMode = PresenceModeStore(state: .available)
	@State private var friendsOnlyVisibility = FriendsOnlyVisibilityStore()

	var body: some View {
		MainTabView()
			.environment(authSession)
			.environment(locationManager)
			.environment(mapFriendsStore)
			.environment(friendsStore)
			.environment(locationSharing)
			.environment(
				BackgroundProximityController(
					locationManager: locationManager,
					locationSharing: locationSharing,
					friendsStore: friendsStore,
					mapFriendsStore: mapFriendsStore,
					presenceMode: presenceMode,
					friendsOnlyVisibility: friendsOnlyVisibility
				)
			)
			.environment(realtimeClient)
			.environment(suggestionEngine)
			.environment(pulsePublisher)
			.environment(mapWeather)
			.environment(weatherObstacles)
			.environment(meetupMemoryStore)
			.environment(interestSuggestionStore)
			.environment(presenceMode)
			.environment(friendsOnlyVisibility)
			.task {
				mapFriendsStore.loadPreviewMocks(around: MockFriendsProvider.fallbackCoordinate)
				await suggestionEngine.refresh(
					userId: "preview",
					displayName: "You",
					interests: ["coffee"],
					coordinate: MockFriendsProvider.fallbackCoordinate,
					placeName: "Koramangala",
					people: mapFriendsStore.friends,
					learned: .empty
				)
			}
	}
}
#endif
