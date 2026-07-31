import SwiftUI

struct PersonDetailView: View {
	@Environment(\.colorScheme) private var colorScheme

	let person: MapPerson
	var onClose: () -> Void = {}
	var onSayHi: () -> Void = {}
	var onMessage: () -> Void = {}

	private var cardFill: Color {
		colorScheme == .dark
			? Color(red: 0.11, green: 0.11, blue: 0.12)
			: Color(.systemBackground)
	}

	private var primaryButtonFill: Color {
		colorScheme == .dark ? .white : Color(red: 0.10, green: 0.11, blue: 0.14)
	}

	private var primaryButtonForeground: Color {
		colorScheme == .dark ? .black : .white
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 0) {
			HStack(alignment: .top) {
				Color.clear
					.frame(width: KismetTheme.Chrome.detailAvatarSize, height: 28)

				Spacer(minLength: 0)

				Button(action: onClose) {
					Image(systemName: "xmark")
						.font(.footnote.weight(.bold))
						.foregroundStyle(.secondary)
						.frame(width: 32, height: 32)
						.background(Color.primary.opacity(0.06), in: Circle())
				}
				.buttonStyle(.plain)
				.accessibilityLabel("Close")
			}
			.padding(.horizontal, 18)
			.padding(.top, 14)

			VStack(alignment: .leading, spacing: 8) {
				HStack(spacing: 8) {
					Text(person.displayName)
						.font(.title.bold())
						.foregroundStyle(.primary)

					Circle()
						.fill(person.availability.statusColor)
						.frame(width: 10, height: 10)
						.accessibilityLabel(person.availability.rawValue)
				}

				Text(person.neighborhoodLabel)
					.font(.subheadline)
					.foregroundStyle(.secondary)

				Text(person.intentLabel)
					.font(.subheadline.weight(.medium))
					.foregroundStyle(.primary.opacity(0.85))

				mutualFriendsRow
					.padding(.top, 6)

				actionRow
					.padding(.top, 18)
			}
			.padding(.horizontal, 22)
			.padding(.bottom, 22)
		}
		.background(cardFill, in: RoundedRectangle(cornerRadius: 32, style: .continuous))
		.overlay(alignment: .topLeading) {
			avatarBadge
				.offset(x: 22, y: -KismetTheme.Chrome.detailAvatarSize * 0.72)
		}
		.shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.14), radius: 24, y: 10)
		.padding(.top, KismetTheme.Chrome.detailAvatarSize * 0.72)
	}

	private var avatarBadge: some View {
		ZStack {
			Circle()
				.fill(KismetTheme.Map.ring(for: person.availability).gradient)
				.frame(
					width: KismetTheme.Chrome.detailAvatarSize + 8,
					height: KismetTheme.Chrome.detailAvatarSize + 8
				)

			Image(systemName: person.accentSystemImage)
				.resizable()
				.scaledToFit()
				.foregroundStyle(.white)
				.padding(22)
				.frame(
					width: KismetTheme.Chrome.detailAvatarSize,
					height: KismetTheme.Chrome.detailAvatarSize
				)
				.background(
					LinearGradient(
						colors: [
							KismetTheme.Map.ring(for: person.availability).opacity(0.85),
							KismetTheme.Map.ring(for: person.availability).opacity(0.55),
						],
						startPoint: .topLeading,
						endPoint: .bottomTrailing
					),
					in: Circle()
				)
				.overlay {
					Circle()
						.stroke(cardFill, lineWidth: 4)
				}
		}
		.accessibilityHidden(true)
	}

	private var mutualFriendsRow: some View {
		HStack(spacing: 10) {
			HStack(spacing: -8) {
				ForEach(0..<min(4, max(person.mutualFriendCount, 1)), id: \.self) { index in
					Image(systemName: "person.crop.circle.fill")
						.font(.title3)
						.foregroundStyle(mutualAvatarColor(at: index))
						.background(cardFill, in: Circle())
				}
			}

			Text("\(person.mutualFriendCount) mutual friends")
				.font(.footnote)
				.foregroundStyle(.secondary)
		}
	}

	private var actionRow: some View {
		HStack(spacing: 12) {
			Button(action: onSayHi) {
				Text("Say Hi")
					.font(.headline)
					.frame(maxWidth: .infinity)
					.padding(.vertical, 16)
					.foregroundStyle(primaryButtonForeground)
					.background(primaryButtonFill, in: Capsule())
			}
			.buttonStyle(.plain)

			Button(action: onMessage) {
				Image(systemName: "bubble.left.fill")
					.font(.body.weight(.semibold))
					.foregroundStyle(.primary)
					.frame(width: 54, height: 54)
					.background(
						Circle()
							.strokeBorder(Color.primary.opacity(0.12), lineWidth: 1)
							.background(Circle().fill(cardFill))
					)
			}
			.buttonStyle(.plain)
			.accessibilityLabel("Message")
		}
	}

	private func mutualAvatarColor(at index: Int) -> Color {
		let palette: [Color] = [
			KismetTheme.Status.free,
			KismetTheme.Status.busy,
			KismetTheme.Status.unknown,
			KismetTheme.Map.userPulse,
		]
		return palette[index % palette.count].opacity(0.85)
	}
}

#Preview("Light") {
	ZStack {
		Color.gray.opacity(0.25).ignoresSafeArea()
		PersonDetailView(
			person: MockFriendsProvider.friends(around: MockFriendsProvider.fallbackCoordinate)[0]
		)
		.padding(.horizontal, 18)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
		.padding(.bottom, 28)
	}
	.preferredColorScheme(.light)
}

#Preview("Dark") {
	ZStack {
		Color.black.ignoresSafeArea()
		PersonDetailView(
			person: MockFriendsProvider.friends(around: MockFriendsProvider.fallbackCoordinate)[0]
		)
		.padding(.horizontal, 18)
		.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
		.padding(.bottom, 28)
	}
	.preferredColorScheme(.dark)
}
