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

	@State private var selectedTab: AppTab = .map
	@State private var insightsDetent: InsightsDetent = .collapsed
	@State private var dragOffset: CGFloat = 0
	@State private var ctaToast: String?
	@Namespace private var glassNamespace

	/// Insights accessory sits above the tab pill (Map only, no person detail).
	private var showsInsights: Bool {
		selectedTab == .map && friendsStore.selectedFriend == nil
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
							.glassEffect(
								.regular,
								in: .rect(cornerRadius: insightsDetent == .collapsed ? 22 : 28)
							)
							.glassEffectID("insights", in: glassNamespace)
					}

					GlassTabBar(selected: $selectedTab)
						.padding(.horizontal, 10)
						.padding(.vertical, 10)
						.glassEffect(.regular, in: .capsule)
						.glassEffectID("tabbar", in: glassNamespace)
				}
				.padding(.horizontal, 16)
			}
			.animation(.snappy, value: showsInsights)
			.animation(.snappy, value: insightsDetent)
		}
		.onChange(of: selectedTab) { _, _ in
			insightsDetent = .collapsed
			dragOffset = 0
		}
		.onChange(of: friendsStore.selectedFriendID) { _, _ in
			insightsDetent = .collapsed
			dragOffset = 0
		}
		.ignoresSafeArea(.keyboard)
		.overlay(alignment: .top) {
			if let ctaToast {
				Text(ctaToast)
					.font(.footnote.weight(.semibold))
					.padding(.horizontal, 14)
					.padding(.vertical, 10)
					.background(.ultraThinMaterial, in: Capsule())
					.padding(.top, 72)
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
					friends: friendsStore.friends,
					showsHeader: true,
					onSelectFriend: { friend in
						friendsStore.select(friend.id)
					},
					onCTA: { friend in
						showToast("\(friend.ctaTitle) — coming soon")
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
		let count = friendsStore.friends.count
		if count == 0 { return "Nothing nearby right now" }
		if count == 1 { return "1 nearby" }
		return "\(count) nearby"
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
		switch selectedTab {
		case .map:
			MapHomeView()
		case .radar:
			RadarView(embedded: false)
				.safeAreaPadding(.bottom, 88)
		case .timeline:
			TimelineView(embedded: false)
				.safeAreaPadding(.bottom, 88)
		case .more:
			MoreView(embedded: false)
				.safeAreaPadding(.bottom, 88)
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
	@State private var friendsStore = MapFriendsStore()

	var body: some View {
		MainTabView()
			.environment(authSession)
			.environment(locationManager)
			.environment(friendsStore)
			.task {
				friendsStore.refresh(around: MockFriendsProvider.fallbackCoordinate)
			}
	}
}
