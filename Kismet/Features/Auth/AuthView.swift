import AuthenticationServices
import SwiftUI

struct AuthView: View {
	@Environment(\.colorScheme) private var colorScheme

	var onSignInCompletion: (Result<ASAuthorization, Error>) -> Void = { _ in }

	private var foregroundColor: Color {
		colorScheme == .dark
			? Color(red: 0.95, green: 0.95, blue: 0.95)
			: Color(red: 0.05, green: 0.10, blue: 0.13)
	}

	var body: some View {
		GeometryReader { geometry in
			ZStack {
				Image(colorScheme == .dark ? "blacksecond" : "whitesecond")
					.resizable()
					.scaledToFill()
					.frame(width: geometry.size.width, height: geometry.size.height)
					.scaleEffect(1.04)
					.blur(radius: 7)
					.clipped()
					.accessibilityHidden(true)

				Color.black
					.opacity(colorScheme == .dark ? 0.12 : 0.02)
					.ignoresSafeArea()

				VStack(alignment: .leading, spacing: 0) {
					VStack(alignment: .leading, spacing: 8) {
						Text("Welcome to")
							.font(.title3)
							.fontWeight(.semibold)
							.foregroundStyle(foregroundColor.opacity(0.82))

						Text("Who's Out")
							.font(.system(size: 52, weight: .bold, design: .rounded))
							.tracking(1)
							.foregroundStyle(foregroundColor)

						Text("Sign in to get started.")
							.font(.headline)
							.fontWeight(.regular)
							.foregroundStyle(foregroundColor.opacity(0.74))
							.padding(.top, 16)
					}
					.padding(.top, 176)

					Spacer()

					SignInWithAppleButton(.continue) { request in
						request.requestedScopes = [.fullName, .email]
					} onCompletion: { result in
						onSignInCompletion(result)
					}
					.signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
					.frame(height: 56)
					.clipShape(Capsule())
					.accessibilityHint("Signs in securely using your Apple Account")
					.padding(.bottom, max(48, geometry.safeAreaInsets.bottom + 24))
				}
				.padding(.horizontal, 32)
			}
			.ignoresSafeArea()
		}
	}
}

#Preview("Light") {
	AuthView()
		.preferredColorScheme(.light)
}

#Preview("Dark") {
	AuthView()
		.preferredColorScheme(.dark)
}
