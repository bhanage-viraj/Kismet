import SwiftUI

struct ProfileView: View {
	@Environment(AuthSession.self) private var authSession
	@Environment(MeetupMemoryStore.self) private var meetupMemoryStore
	@Environment(InterestSuggestionStore.self) private var interestSuggestions
	@Environment(\.colorScheme) private var colorScheme

	@State private var selectedInterests: Set<String> = []
	@State private var isSaving = false
	@State private var saveMessage: String?

	var body: some View {
		List {
			Section {
				LabeledContent("Name", value: authSession.preferredDisplayName)
				LabeledContent("Email", value: authSession.user?.email ?? "—")
			} header: {
				Text("Account")
			}

			if !interestSuggestions.pending.isEmpty {
				Section {
					ForEach(interestSuggestions.pending, id: \.self) { interestID in
						interestSuggestionRow(interestID)
					}
				} header: {
					Text("Suggested from hangouts")
				} footer: {
					Text("Based on places you actually met. Nothing is saved until you tap Add.")
				}
			}

			Section {
				LazyVGrid(
					columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3),
					spacing: 10
				) {
					ForEach(InterestCatalog.all) { interest in
						interestChip(interest)
					}
				}
				.padding(.vertical, 4)
				.listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))

				Button {
					Task { await saveInterests() }
				} label: {
					if isSaving {
						ProgressView()
							.frame(maxWidth: .infinity)
					} else {
						Text("Save interests")
							.frame(maxWidth: .infinity)
					}
				}
				.disabled(isSaving || selectedInterests.isEmpty)
			} header: {
				Text("Your interests")
			} footer: {
				if let saveMessage {
					Text(saveMessage)
				} else {
					Text("These feed ranking and Pulse targeting. Edit anytime.")
				}
			}
		}
		.listStyle(.insetGrouped)
		.navigationTitle("Profile")
		.onAppear {
			selectedInterests = Set(authSession.user?.interests ?? [])
			interestSuggestions.refresh(
				meetups: meetupMemoryStore.meetupSnapshots(),
				currentInterests: authSession.user?.interests ?? []
			)
		}
	}

	private func interestSuggestionRow(_ interestID: String) -> some View {
		let name = InterestCatalog.displayName(for: interestID)
		return HStack {
			VStack(alignment: .leading, spacing: 2) {
				Text("Add \(name)?")
					.font(.body.weight(.medium))
				Text("Seen in recent hangouts")
					.font(.caption)
					.foregroundStyle(.secondary)
			}
			Spacer()
			Button("Add") {
				Task { await acceptSuggestion(interestID) }
			}
			.buttonStyle(.borderedProminent)
			.controlSize(.small)
			Button {
				interestSuggestions.dismiss(interestID)
			} label: {
				Image(systemName: "xmark")
			}
			.buttonStyle(.borderless)
			.accessibilityLabel("Dismiss \(name)")
		}
	}

	private func interestChip(_ interest: InterestItem) -> some View {
		let isSelected = selectedInterests.contains(interest.id)
		return Button {
			withAnimation(.easeInOut(duration: 0.15)) {
				if isSelected {
					selectedInterests.remove(interest.id)
				} else {
					selectedInterests.insert(interest.id)
				}
			}
		} label: {
			VStack(spacing: 8) {
				Image(systemName: interest.symbol)
					.font(.system(size: 22, weight: .semibold))
					.foregroundStyle(interest.color)
				Text(interest.name)
					.font(.caption.weight(.semibold))
					.foregroundStyle(colorScheme == .dark ? Color.white : Color.primary)
					.lineLimit(1)
					.minimumScaleFactor(0.75)
			}
			.frame(maxWidth: .infinity)
			.frame(height: 72)
			.background(
				isSelected ? interest.color.opacity(0.18) : Color.clear,
				in: RoundedRectangle(cornerRadius: 14)
			)
			.overlay {
				RoundedRectangle(cornerRadius: 14)
					.stroke(isSelected ? interest.color : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
			}
		}
		.buttonStyle(.plain)
	}

	private func acceptSuggestion(_ interestID: String) async {
		var next = Set(authSession.user?.interests ?? [])
		next.insert(interestID)
		selectedInterests = next
		let ok = await authSession.saveInterests(Array(next).sorted())
		if ok {
			interestSuggestions.removeAccepted(interestID)
			saveMessage = "Added \(InterestCatalog.displayName(for: interestID))."
			interestSuggestions.refresh(
				meetups: meetupMemoryStore.meetupSnapshots(),
				currentInterests: authSession.user?.interests ?? Array(next)
			)
		} else {
			saveMessage = "Couldn't save that interest. Try again."
		}
	}

	private func saveInterests() async {
		isSaving = true
		defer { isSaving = false }
		let ok = await authSession.saveInterests(selectedInterests.sorted())
		saveMessage = ok ? "Interests saved." : "Couldn't save interests."
		if ok {
			interestSuggestions.refresh(
				meetups: meetupMemoryStore.meetupSnapshots(),
				currentInterests: authSession.user?.interests ?? selectedInterests.sorted()
			)
		}
	}
}

#if DEBUG
#Preview("Interest chips") {
	ProfileInterestChipsPreviewHost(pending: ["coffee", "food", "nature"])
}

#Preview("Interest chips Dark") {
	ProfileInterestChipsPreviewHost(pending: ["coffee"])
		.preferredColorScheme(.dark)
}

private struct ProfileInterestChipsPreviewHost: View {
	let pending: [String]
	@State private var authSession = AuthSession.previewSignedIn()
	@State private var meetupMemoryStore = MeetupMemoryStore(
		container: try! MeetupModelContainer.makeInMemory()
	)
	@State private var interestSuggestions = InterestSuggestionStore()

	var body: some View {
		NavigationStack {
			ProfileView()
		}
		.environment(authSession)
		.environment(meetupMemoryStore)
		.environment(interestSuggestions)
		.onAppear {
			// Re-seed after ProfileView.onAppear refresh (empty memory → no inferences).
			interestSuggestions.previewSetPending(pending)
		}
	}
}
#endif
