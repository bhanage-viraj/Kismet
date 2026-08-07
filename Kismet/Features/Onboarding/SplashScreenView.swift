import SwiftUI

struct SplashScreenView: View {
	var body: some View {
		GeometryReader { geometry in
			Image("WhosOutSplash")
				.resizable()
				.scaledToFill()
				.frame(width: geometry.size.width, height: geometry.size.height)
				.clipped()
				.accessibilityLabel("Who's Out. Find your people. Find your moment.")
		}
		.ignoresSafeArea()
	}
}

#Preview {
	SplashScreenView()
}
