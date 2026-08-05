import SwiftUI

/// "What's the plan?" compose screen for sending a Pulse.
struct PulseComposeView: View {
	@Environment(\.colorScheme) private var colorScheme
	@Environment(\.dismiss) private var dismiss

	@Binding var draft: PulseComposeDraft
	var isSending: Bool = false
	var onSend: () -> Void

	@State private var showWhenPicker = false
	@State private var showWhereEditor = false
	@State private var showMoreActivities = false

	private var titleColor: Color { KismetTheme.Insight.titleColor(for: colorScheme) }
	private var bodyColor: Color { KismetTheme.Insight.bodyColor(for: colorScheme) }
	private var sheetBg: Color { KismetTheme.Insight.sheetBackground(for: colorScheme) }
	private var fieldBg: Color {
		colorScheme == .dark
			? Color(red: 0.20, green: 0.20, blue: 0.21)
			: Color.white
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			Text("What's the plan?")
				.font(.system(size: 34, weight: .bold, design: .rounded))
				.foregroundStyle(titleColor)
				.padding(.horizontal, 24)
				.padding(.top, 28)
				.padding(.bottom, 20)

			ScrollView {
				VStack(alignment: .leading, spacing: 28) {
					titleField
					activitySection
					whereSection
					whenSection
				}
				.padding(.horizontal, 24)
				.padding(.bottom, 24)
			}

			sendButton
				.padding(.horizontal, 24)
				.padding(.bottom, 16)
		}
		.background(sheetBg.ignoresSafeArea())
		.sheet(isPresented: $showWhenPicker) {
			NavigationStack {
				DatePicker(
					"When",
					selection: $draft.startsAt,
					in: Date()...,
					displayedComponents: [.date, .hourAndMinute]
				)
				.datePickerStyle(.graphical)
				.padding()
				.navigationTitle("When?")
				.navigationBarTitleDisplayMode(.inline)
				.toolbar {
					ToolbarItem(placement: .confirmationAction) {
						Button("Done") { showWhenPicker = false }
					}
				}
			}
			.presentationDetents([.medium, .large])
		}
		.sheet(isPresented: $showWhereEditor) {
			whereEditor
				.presentationDetents([.medium])
		}
		.sheet(isPresented: $showMoreActivities) {
			moreActivitiesSheet
				.presentationDetents([.medium])
		}
	}

	// MARK: - Title

	private var titleField: some View {
		HStack(spacing: 10) {
			TextField("What's happening?", text: $draft.title)
				.font(.system(size: 17, weight: .semibold, design: .rounded))
				.foregroundStyle(titleColor)

			if !draft.title.isEmpty {
				Button {
					draft.title = ""
				} label: {
					Image(systemName: "xmark.circle.fill")
						.font(.system(size: 18))
						.foregroundStyle(.tertiary)
				}
				.buttonStyle(.plain)
				.accessibilityLabel("Clear title")
			}
		}
		.padding(.horizontal, 16)
		.padding(.vertical, 14)
		.background(fieldBg, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
		.overlay(
			RoundedRectangle(cornerRadius: 16, style: .continuous)
				.strokeBorder(Color.primary.opacity(0.06), lineWidth: 1)
		)
	}

	// MARK: - Activity

	private var activitySection: some View {
		VStack(alignment: .leading, spacing: 12) {
			Text("Activity")
				.font(.subheadline.weight(.medium))
				.foregroundStyle(bodyColor)

			HStack(spacing: 0) {
				ForEach(PulseActivity.allCases) { activity in
					activityChip(activity)
						.frame(maxWidth: .infinity)
				}
			}
		}
	}

	private func activityChip(_ activity: PulseActivity) -> some View {
		let selected = draft.activity == activity
		return Button {
			if activity == .more {
				showMoreActivities = true
			} else {
				selectActivity(activity)
			}
		} label: {
			VStack(spacing: 8) {
				ZStack {
					Circle()
						.fill(selected ? activity.accent.opacity(0.22) : fieldBg)
						.overlay(
							Circle()
								.strokeBorder(
									selected ? activity.accent.opacity(0.55) : Color.primary.opacity(0.08),
									lineWidth: selected ? 1.5 : 1
								)
						)
						.frame(width: 56, height: 56)

					Image(systemName: activity.symbol)
						.font(.system(size: 20, weight: .semibold))
						.foregroundStyle(selected ? activity.accent : titleColor.opacity(0.75))
				}

				Text(activity.title)
					.font(.caption.weight(selected ? .semibold : .medium))
					.foregroundStyle(selected ? titleColor : bodyColor)
			}
		}
		.buttonStyle(.plain)
	}

	private func selectActivity(_ activity: PulseActivity) {
		let wasDefault = PulseActivity.allCases.contains { draft.title == $0.defaultTitle }
		draft.activity = activity
		if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || wasDefault {
			draft.title = activity.defaultTitle
		}
	}

	// MARK: - Where / When

	private var whereSection: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("Where?")
				.font(.subheadline.weight(.medium))
				.foregroundStyle(bodyColor)

			Button { showWhereEditor = true } label: {
				detailRow(
					title: draft.venueName.isEmpty ? "Add a place" : draft.venueName,
					subtitle: draft.venueAddress.isEmpty ? nil : draft.venueAddress,
					titleIsPlaceholder: draft.venueName.isEmpty
				)
			}
			.buttonStyle(.plain)
		}
	}

	private var whenSection: some View {
		VStack(alignment: .leading, spacing: 10) {
			Text("When?")
				.font(.subheadline.weight(.medium))
				.foregroundStyle(bodyColor)

			Button { showWhenPicker = true } label: {
				detailRow(title: Self.formatWhen(draft.startsAt), subtitle: nil)
			}
			.buttonStyle(.plain)
		}
	}

	private func detailRow(title: String, subtitle: String?, titleIsPlaceholder: Bool = false) -> some View {
		HStack(alignment: .center, spacing: 12) {
			VStack(alignment: .leading, spacing: 2) {
				Text(title)
					.font(.body.weight(.semibold))
					.foregroundStyle(titleIsPlaceholder ? bodyColor : titleColor)
				if let subtitle {
					Text(subtitle)
						.font(.subheadline)
						.foregroundStyle(bodyColor)
				}
			}
			Spacer(minLength: 0)
			Image(systemName: "chevron.right")
				.font(.system(size: 13, weight: .semibold))
				.foregroundStyle(.tertiary)
		}
		.padding(.vertical, 4)
	}

	// MARK: - Send

	private var sendButton: some View {
		Button(action: onSend) {
			HStack {
				if isSending {
					ProgressView()
						.tint(.white)
				}
				Text(isSending ? "Sending…" : "Send Pulse")
					.font(.headline.weight(.bold))
			}
			.frame(maxWidth: .infinity)
			.frame(height: 56)
			.foregroundStyle(.white)
			.background(
				LinearGradient(
					colors: [
						Color(red: 1.00, green: 0.52, blue: 0.32),
						Color(red: 0.98, green: 0.38, blue: 0.36),
					],
					startPoint: .leading,
					endPoint: .trailing
				),
				in: RoundedRectangle(cornerRadius: 18, style: .continuous)
			)
		}
		.buttonStyle(.plain)
		.disabled(isSending || !canSend)
		.opacity(canSend || isSending ? 1 : 0.55)
	}

	private var canSend: Bool {
		!draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
			&& !draft.recipientUserId.isEmpty
	}

	// MARK: - Sheets

	private var whereEditor: some View {
		NavigationStack {
			Form {
				TextField("Place name", text: $draft.venueName)
				TextField("Neighborhood / address", text: $draft.venueAddress)
			}
			.navigationTitle("Where?")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .confirmationAction) {
					Button("Done") { showWhereEditor = false }
				}
			}
		}
	}

	private var moreActivitiesSheet: some View {
		NavigationStack {
			List(InterestCatalog.all) { item in
				Button {
					if let matched = PulseActivity(rawValue: item.id) {
						selectActivity(matched)
					} else {
						draft.activity = .more
						if draft.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
							draft.title = item.name
						}
					}
					showMoreActivities = false
				} label: {
					Label {
						Text(item.name)
					} icon: {
						Image(systemName: item.symbol)
							.foregroundStyle(item.color)
					}
				}
			}
			.navigationTitle("More activities")
			.navigationBarTitleDisplayMode(.inline)
			.toolbar {
				ToolbarItem(placement: .cancellationAction) {
					Button("Close") { showMoreActivities = false }
				}
			}
		}
	}

	static func formatWhen(_ date: Date) -> String {
		let cal = Calendar.current
		let time = date.formatted(date: .omitted, time: .shortened)
		if cal.isDateInToday(date) { return "Today, \(time)" }
		if cal.isDateInTomorrow(date) { return "Tomorrow, \(time)" }
		return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
	}
}

#Preview {
	PulseComposeView(
		draft: .constant(
			PulseComposeDraft(
				title: "Coffee catch-up ☕",
				activity: .coffee,
				venueName: "Third Wave Coffee",
				venueAddress: "Koramangala 4th Block",
				startsAt: Calendar.current.date(bySettingHour: 17, minute: 0, second: 0, of: Date()) ?? Date(),
				recipientUserId: "friend-1",
				recipientDisplayName: "Aarav"
			)
		),
		onSend: {}
	)
}

/// Sheet wrapper that owns editable draft state while presenting.
struct PulseComposeSheetHost: View {
	@State private var draft: PulseComposeDraft
	var isSending: Bool
	var onSend: (PulseComposeDraft) -> Void

	init(draft: PulseComposeDraft, isSending: Bool, onSend: @escaping (PulseComposeDraft) -> Void) {
		_draft = State(initialValue: draft)
		self.isSending = isSending
		self.onSend = onSend
	}

	var body: some View {
		PulseComposeView(draft: $draft, isSending: isSending) {
			onSend(draft)
		}
	}
}
