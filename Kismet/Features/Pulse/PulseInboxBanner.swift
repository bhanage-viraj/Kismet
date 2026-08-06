import SwiftUI

/// Compact map banner for the newest active incoming Pulse.
struct PulseInboxBanner: View {
	let pulse: IncomingPulse
	var onAccept: () -> Void
	var onDismiss: () -> Void

	var body: some View {
		HStack(alignment: .center, spacing: 12) {
			Text(pulse.payload.emoji)
				.font(.title2)

			VStack(alignment: .leading, spacing: 2) {
				Text("\(pulse.senderDisplayName) · \(pulse.payload.label)")
					.font(.subheadline.weight(.semibold))
					.lineLimit(1)
				Text(subtitle)
					.font(.caption)
					.foregroundStyle(.secondary)
					.lineLimit(1)
			}

			Spacer(minLength: 0)

			Button("Accept", action: onAccept)
				.font(.caption.weight(.bold))
				.buttonStyle(.borderedProminent)
				.tint(KismetTheme.Status.free)
				.controlSize(.small)

			Button(action: onDismiss) {
				Image(systemName: "xmark")
					.font(.caption.weight(.bold))
					.foregroundStyle(.secondary)
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Dismiss Pulse")
		}
		.padding(12)
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
	}

	private var subtitle: String {
		var parts: [String] = []
		if let message = pulse.payload.message?.trimmingCharacters(in: .whitespacesAndNewlines),
		   !message.isEmpty {
			parts.append(message)
		} else if let venue = pulse.payload.venueName, !venue.isEmpty {
			parts.append(venue)
		}
		parts.append(expiresText)
		return parts.joined(separator: " · ")
	}

	private var expiresText: String {
		let minutes = max(0, Int(ceil(pulse.payload.expiresAt.timeIntervalSinceNow / 60)))
		if minutes <= 0 { return "Expired" }
		if minutes == 1 { return "1 min left" }
		return "\(minutes) min left"
	}
}
