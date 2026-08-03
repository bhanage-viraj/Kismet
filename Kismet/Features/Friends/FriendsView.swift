import SwiftUI
import UIKit

struct FriendsView: View {
	@Environment(FriendsStore.self) private var friendsStore
	@State private var redeemCode = ""
	@State private var friendPendingRevoke: FriendSummaryDTO?
	@State private var didCopyInvite = false

	var body: some View {
		List {
			if let message = friendsStore.lastErrorMessage {
				Section {
					Text(message)
						.font(.footnote)
						.foregroundStyle(.red)
				}
			} else if let message = friendsStore.lastSuccessMessage {
				Section {
					Text(message)
						.font(.footnote)
						.foregroundStyle(.secondary)
				}
			}

			Section {
				Button {
					Task { await friendsStore.createInvite() }
				} label: {
					Label(
						friendsStore.activeInvite == nil ? "Create invite code" : "Refresh invite code",
						systemImage: "qrcode"
					)
				}
				.disabled(friendsStore.isMutating)

				if let invite = friendsStore.activeInvite {
					VStack(alignment: .leading, spacing: 10) {
						Text(invite.code)
							.font(.system(.title2, design: .monospaced).weight(.bold))
							.textSelection(.enabled)

						Text("Expires \(invite.expiresAt.formatted(.relative(presentation: .named)))")
							.font(.caption)
							.foregroundStyle(.secondary)

						HStack(spacing: 12) {
							Button {
								UIPasteboard.general.string = invite.code
								didCopyInvite = true
								Task {
									try? await Task.sleep(for: .seconds(1.5))
									didCopyInvite = false
								}
							} label: {
								Label(didCopyInvite ? "Copied" : "Copy", systemImage: "doc.on.doc")
							}
							.buttonStyle(.bordered)

							ShareLink(item: invite.qrPayload) {
								Label("Share", systemImage: "square.and.arrow.up")
							}
							.buttonStyle(.borderedProminent)
						}
					}
					.padding(.vertical, 4)
				}
			} header: {
				Text("Invite")
			} footer: {
				Text("Anyone with the code can connect instantly. Creating a new code invalidates the previous one.")
			}

			Section {
				HStack {
					TextField("Enter invite code", text: $redeemCode)
						.textInputAutocapitalization(.characters)
						.autocorrectionDisabled()
						.font(.body.monospaced())
						.onChange(of: redeemCode) { _, _ in
							friendsStore.clearMessages()
						}

					Button("Redeem") {
						Task {
							let ok = await friendsStore.redeem(code: redeemCode)
							if ok { redeemCode = "" }
						}
					}
					.disabled(friendsStore.isMutating || redeemCode.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
				}
			} header: {
				Text("Redeem")
			}

			Section {
				Button {
					Task { await friendsStore.seedTestFriend() }
				} label: {
					Label("Add Alex (Test) from backend", systemImage: "person.badge.plus")
				}
				.disabled(friendsStore.isMutating)
			} header: {
				Text("Demo")
			} footer: {
				Text("Creates a synthetic friend on the server so you can test Siri and the map without a second device.")
			}

			Section {
				if friendsStore.isLoading && friendsStore.friends.isEmpty {
					HStack {
						ProgressView()
						Text("Loading friends…")
							.foregroundStyle(.secondary)
					}
				} else if friendsStore.friends.isEmpty {
					ContentUnavailableView(
						"No friends yet",
						systemImage: "person.2",
						description: Text("Share an invite code or redeem one from a friend to show up on each other’s maps.")
					)
					.listRowBackground(Color.clear)
				} else {
					ForEach(friendsStore.friends) { friend in
						FriendRowView(friend: friend)
							.swipeActions(edge: .trailing, allowsFullSwipe: true) {
								Button("Remove", role: .destructive) {
									friendPendingRevoke = friend
								}
							}
					}
				}
			} header: {
				Text("Connected")
			}
		}
		.navigationTitle("Friends")
		.navigationBarTitleDisplayMode(.inline)
		.refreshable {
			await friendsStore.refresh()
		}
		.task {
			await friendsStore.refresh()
		}
		.confirmationDialog(
			"Remove \(friendPendingRevoke?.displayName ?? "this friend")?",
			isPresented: Binding(
				get: { friendPendingRevoke != nil },
				set: { if !$0 { friendPendingRevoke = nil } }
			),
			titleVisibility: .visible
		) {
			Button("Remove", role: .destructive) {
				guard let friend = friendPendingRevoke else { return }
				friendPendingRevoke = nil
				Task { await friendsStore.revoke(friendUserId: friend.userId) }
			}
			Button("Cancel", role: .cancel) {
				friendPendingRevoke = nil
			}
		} message: {
			Text("This removes the connection for both of you and deletes shared location blobs.")
		}
	}
}

private struct FriendRowView: View {
	let friend: FriendSummaryDTO

	var body: some View {
		HStack(spacing: 12) {
			Image(systemName: "person.crop.circle.fill")
				.font(.system(size: 36))
				.foregroundStyle(.secondary)

			VStack(alignment: .leading, spacing: 3) {
				Text(friend.displayName ?? "Friend")
					.font(.body.weight(.semibold))

				HStack(spacing: 6) {
					if friend.publicKey != nil {
						Label("Key ready", systemImage: "lock.fill")
					} else {
						Label("No public key yet", systemImage: "lock.open")
					}
				}
				.font(.caption)
				.foregroundStyle(.secondary)

				if let since = friend.since {
					Text("Connected \(since.formatted(.relative(presentation: .named)))")
						.font(.caption2)
						.foregroundStyle(.tertiary)
				}
			}

			Spacer(minLength: 0)
		}
		.padding(.vertical, 2)
	}
}

// FriendsStore.preview is DEBUG-only, so the preview must be too — otherwise a
// Release build fails on a symbol that was compiled out.
#if DEBUG
#Preview {
	NavigationStack {
		FriendsView()
	}
	.environment(FriendsStore.preview(friends: [
		FriendSummaryDTO(
			pairId: "p1",
			userId: "u1",
			displayName: "Ada Lovelace",
			publicKey: "abc",
			keyVersion: 1,
			status: "ACTIVE",
			connectedVia: "INVITE_CODE",
			since: Date().addingTimeInterval(-86_400),
			initiatedByMe: true
		),
	]))
}
#endif
