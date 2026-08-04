import SwiftUI

/// Multi-select which friends receive precise location while in Friends Only mode.
struct FriendsOnlyPickerSheet: View {
	@Environment(FriendsStore.self) private var friendsStore
	@Environment(FriendsOnlyVisibilityStore.self) private var visibility
	@Environment(\.dismiss) private var dismiss

	@State private var selectedIds: Set<String> = []
	var onSaved: (() -> Void)?

	var body: some View {
		NavigationStack {
			List {
				Section {
					Text("Only selected friends see your precise pin. Everyone else is hidden — same as Eclipse for them.")
						.font(.footnote)
						.foregroundStyle(.secondary)
						.listRowBackground(Color.clear)
				}

				Section {
					if friendsStore.friends.isEmpty {
						ContentUnavailableView(
							"No friends yet",
							systemImage: "person.2",
							description: Text("Connect friends first, then choose who can see you.")
						)
						.listRowBackground(Color.clear)
					} else {
						ForEach(friendsStore.friends) { friend in
							Button {
								toggle(friend.userId)
							} label: {
								HStack(spacing: 12) {
									Image(systemName: selectedIds.contains(friend.userId)
										? "checkmark.circle.fill"
										: "circle")
										.foregroundStyle(
											selectedIds.contains(friend.userId)
												? KismetTheme.Bump.friendsOnly
												: .secondary
										)
										.font(.title3)

									VStack(alignment: .leading, spacing: 2) {
										Text(friend.displayName ?? "Friend")
											.font(.body.weight(.semibold))
											.foregroundStyle(.primary)
										Text(friend.publicKey == nil ? "No key yet" : "Can receive location")
											.font(.caption)
											.foregroundStyle(.secondary)
									}

									Spacer(minLength: 0)
								}
							}
							.buttonStyle(.plain)
							.disabled(friend.publicKey == nil)
						}
					}
				} header: {
					Text("Visible to")
				} footer: {
					if selectedIds.isEmpty, !friendsStore.friends.isEmpty {
						Text("Nobody selected — you’ll be hidden from the whole friend graph.")
					}
				}
			}
			.navigationTitle("Friends Only")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Cancel") { dismiss() }
				}
				ToolbarItem(placement: .confirmationAction) {
					Button("Save") {
						visibility.replace(with: selectedIds)
						onSaved?()
						dismiss()
					}
					.fontWeight(.semibold)
				}
				ToolbarItem(placement: .bottomBar) {
					HStack {
						Button("Select all") {
							selectedIds = Set(
								friendsStore.friends
									.filter { $0.publicKey != nil }
									.map(\.userId)
							)
						}
						Spacer()
						Button("Clear") { selectedIds = [] }
					}
				}
			}
			.task {
				await friendsStore.refresh()
				seedSelection()
			}
		}
	}

	private func seedSelection() {
		if let existing = visibility.visibleFriendIds {
			selectedIds = existing
		} else {
			selectedIds = Set(
				friendsStore.friends
					.filter { $0.publicKey != nil }
					.map(\.userId)
			)
		}
	}

	private func toggle(_ id: String) {
		if selectedIds.contains(id) {
			selectedIds.remove(id)
		} else {
			selectedIds.insert(id)
		}
	}
}
