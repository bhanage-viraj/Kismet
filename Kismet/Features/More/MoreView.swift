import SwiftUI

struct MoreView: View {
	@Environment(AuthSession.self) private var authSession
	@Environment(FriendsStore.self) private var friendsStore
	@Environment(MapFriendsStore.self) private var mapFriendsStore
	@Environment(LocationSharingService.self) private var locationSharing
	@Environment(BackgroundProximityController.self) private var backgroundProximity
	@Environment(RealtimeClient.self) private var realtimeClient
	@State private var showAboutDevelopers = false
	var embedded: Bool = false

	var body: some View {
		Group {
			if embedded {
				listContent
			} else {
				NavigationStack {
					listContent
						.navigationTitle("More")
				}
			}
		}
		.sheet(isPresented: $showAboutDevelopers) {
			AboutDeveloperView()
				.presentationDetents([.height(480)])
				.presentationDragIndicator(.visible)
		}
	}

	private var listContent: some View {
		List {
			Section("Friends") {
				NavigationLink {
					FriendsView()
				} label: {
					HStack {
						Label("Manage friends", systemImage: "person.2.fill")
						Spacer()
						if !friendsStore.friends.isEmpty {
							Text("\(friendsStore.friends.count)")
								.foregroundStyle(.secondary)
						}
					}
				}

				NavigationLink {
					BumpFlowView()
						.navigationTitle("Add nearby")
						.navigationBarTitleDisplayMode(.inline)
				} label: {
					Label("Add nearby friend", systemImage: "wave.3.right")
				}
			}

			Section("Account") {
				NavigationLink {
					ProfileView()
				} label: {
					Label("Profile & interests", systemImage: "person.crop.circle")
				}
				LabeledContent("Name", value: authSession.preferredDisplayName)
				LabeledContent("Email", value: authSession.user?.email ?? "—")
				Button("Sign Out", role: .destructive) {
					Task {
						realtimeClient.disconnect()
						await PushTokenRegistrar.unregisterCurrentToken()
						backgroundProximity.stop()
						locationSharing.stop()
						friendsStore.reset()
						mapFriendsStore.reset()
						await authSession.signOut()
					}
				}
			}

			Section("About") {
				Button {
					showAboutDevelopers = true
				} label: {
					Label("About the developers", systemImage: "chevron.left.forwardslash.chevron.right")
				}
				.foregroundStyle(.primary)
			}
		}
		.scrollContentBackground(embedded ? .hidden : .automatic)
		.listStyle(.insetGrouped)
		.task {
			await friendsStore.refresh()
		}
	}
}

#Preview {
	let locationManager = VisitLocationManager()
	let friendsStore = FriendsStore()
	let mapFriendsStore = MapFriendsStore()
	let locationSharing = LocationSharingService()
	let presenceMode = PresenceModeStore(state: .available)
	let friendsOnlyVisibility = FriendsOnlyVisibilityStore()
	return MoreView()
		.environment(AuthSession())
		.environment(friendsStore)
		.environment(mapFriendsStore)
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
		.environment(RealtimeClient())
		.environment(presenceMode)
		.environment(friendsOnlyVisibility)
}
