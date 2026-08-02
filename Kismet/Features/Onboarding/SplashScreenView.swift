import SwiftUI

struct SplashScreenView: View {
    @Environment(\.colorScheme) private var colorScheme

    private var foregroundColor: Color {
        colorScheme == .dark ? .white : Color(red: 0.05, green: 0.10, blue: 0.13)
    }

    private var accentColor: Color {
        colorScheme == .dark
            ? Color(red: 0.24, green: 0.76, blue: 0.58)
            : Color(red: 0.12, green: 0.50, blue: 0.38)
    }

    private var supportingTextColor: Color {
        colorScheme == .dark
            ? Color(red: 0.95, green: 0.95, blue: 0.95).opacity(0.84)
            : foregroundColor.opacity(0.78)
    }

    private var orangeAccent: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 1.00, green: 0.67, blue: 0.18),
                Color(red: 0.95, green: 0.38, blue: 0.12)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Image(colorScheme == .dark ? "blacfirst" : "whitefirst")
                    .resizable()
                    .scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .accessibilityHidden(true)

                VStack(spacing: 0) {
                    Color.clear
                        .frame(height: 192)

                    brand

                    tagline
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 32)

                    Spacer()

                    privacyMessage
                        .padding(.bottom, max(32, geometry.safeAreaInsets.bottom + 16))
                }
                .padding(.horizontal, 32)
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(colorScheme)
    }

    private var brand: some View {
        ZStack {
            Text("indeKismet")
                .font(.system(size: 58, weight: .bold, design: .rounded))
                .fontWidth(.expanded)
                .tracking(1.2)
                .foregroundStyle(foregroundColor)
                .shadow(
                    color: colorScheme == .dark
                        ? .black.opacity(0.28)
                        : .white.opacity(0.55),
                    radius: 3,
                    y: 1
                )

            OrbitLogo()
                .frame(width: 78, height: 78)
                .scaleEffect(1.35)
                .offset(x: -84, y: -32)
        }
        .frame(width: 320, height: 96)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("indeKismet")
    }

    private var tagline: some View {
        VStack(spacing: 8) {
            Text("Paths Cross.")
                .foregroundStyle(supportingTextColor)

            HStack(spacing: 4) {
                Text("Movements")
                    .foregroundStyle(supportingTextColor)

                Text("Happen.")
                    .fontWeight(.semibold)
                    .foregroundStyle(orangeAccent)
            }
        }
        .font(.headline)
        .fontWeight(.regular)
        .accessibilityElement(children: .combine)
    }

    private var privacyMessage: some View {
        HStack(spacing: 24) {
            Image(systemName: "lock")
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundStyle(accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 8) {
                Text("Private by design.")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundStyle(foregroundColor.opacity(0.82))

                Text("On-device AI.")
                    .font(.subheadline)
                    .fontWeight(.regular)
                    .foregroundStyle(foregroundColor.opacity(0.70))
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct OrbitLogo: View {
    var body: some View {
        ZStack {
            Circle()
                .stroke(
                    Color.primary.opacity(0.16),
                    style: StrokeStyle(lineWidth: 1.5, dash: [2, 3])
                )
                .frame(width: 43, height: 43)

            orbitDot(color: .orange, size: 13, x: -20, y: -13)
            orbitDot(
                color: Color(red: 0.22, green: 0.70, blue: 0.54),
                size: 8,
                x: 8,
                y: -23
            )
            orbitDot(
                color: Color(red: 0.45, green: 0.63, blue: 0.26),
                size: 10,
                x: 24,
                y: -8
            )
            orbitDot(
                color: Color(red: 0.20, green: 0.64, blue: 0.70),
                size: 10,
                x: -26,
                y: 20
            )
        }
        .accessibilityHidden(true)
    }

    private func orbitDot(
        color: Color,
        size: CGFloat,
        x: CGFloat,
        y: CGFloat
    ) -> some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .offset(x: x, y: y)
            .shadow(color: color.opacity(0.35), radius: 3)
    }
}

#Preview("Light") {
    SplashScreenView()
        .preferredColorScheme(.light)
}

#Preview("Dark") {
    SplashScreenView()
        .preferredColorScheme(.dark)
}
