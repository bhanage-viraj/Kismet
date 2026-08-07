import SwiftUI

struct AboutDeveloperView: View {
	@State private var headerOpacity: Double = 0
	@State private var headerOffset: CGFloat = 10

	var body: some View {
		VStack(spacing: 24) {
			Text("Designed & developed by")
				.font(.system(size: 12, weight: .medium, design: .rounded))
				.tracking(2.4)
				.textCase(.uppercase)
				.foregroundStyle(.secondary)
				.opacity(headerOpacity)
				.offset(y: headerOffset)

			DeveloperSignatureBlock(signature: SanjivSignatureOnly())

			Text("&")
				.font(.custom("Didot", size: 36))
				.foregroundStyle(.tertiary)

			DeveloperSignatureBlock(
				signature: VirajSignatureOnly(),
				animationDelay: 1.1
			)
		}
		.frame(maxWidth: .infinity, maxHeight: .infinity)
		.padding(.horizontal, 20)
		.padding(.top, 12)
		.padding(.bottom, 20)
		.onAppear {
			withAnimation(.easeOut(duration: 0.55)) {
				headerOpacity = 1
				headerOffset = 0
			}
		}
	}
}

private struct DeveloperSignatureBlock<Signature: Shape>: View {
	let signature: Signature
	var animationDelay: Double = 0.45

	@State private var trimProgress: Double = 0
	@State private var fillOpacity: Double = 0
	@State private var strokeOpacity: Double = 1

	private let signatureDuration: Double = 2.4

	var body: some View {
		ZStack {
			signature
				.trim(from: 0, to: trimProgress)
				.stroke(
					Color.primary,
					style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round)
				)
				.opacity(strokeOpacity)

			signature
				.fill(Color.primary, style: FillStyle(eoFill: true))
				.opacity(fillOpacity)
		}
		.frame(width: 280, height: 120)
		.onAppear { animate() }
	}

	private func animate() {
		DispatchQueue.main.asyncAfter(deadline: .now() + animationDelay) {
			withAnimation(.linear(duration: signatureDuration)) {
				trimProgress = 1
			}
		}

		DispatchQueue.main.asyncAfter(deadline: .now() + animationDelay + signatureDuration) {
			withAnimation(.easeInOut(duration: 0.4)) {
				fillOpacity = 1
				strokeOpacity = 0
			}
		}
	}
}

/// Skips the leading bounding-box subpath so trim/stroke animates the signature itself.
private struct SignatureInk<Base: Shape>: Shape {
	let base: Base

	func path(in rect: CGRect) -> Path {
		let full = base.path(in: rect)
		var result = Path()
		var subpathIndex = -1

		full.forEach { element in
			switch element {
			case .move(let to):
				subpathIndex += 1
				if subpathIndex > 0 { result.move(to: to) }
			case .line(let to):
				if subpathIndex > 0 { result.addLine(to: to) }
			case .curve(let to, let c1, let c2):
				if subpathIndex > 0 { result.addCurve(to: to, control1: c1, control2: c2) }
			case .quadCurve(let to, let c):
				if subpathIndex > 0 { result.addQuadCurve(to: to, control: c) }
			case .closeSubpath:
				if subpathIndex > 0 { result.closeSubpath() }
			@unknown default:
				break
			}
		}
		return result
	}
}

struct SanjivSignatureOnly: Shape {
	func path(in rect: CGRect) -> Path {
		SignatureInk(base: SanjivSignature()).path(in: rect)
	}
}

struct VirajSignatureOnly: Shape {
	func path(in rect: CGRect) -> Path {
		SignatureInk(base: VirajSignature()).path(in: rect)
	}
}

#Preview {
	Color.gray
		.ignoresSafeArea()
		.sheet(isPresented: .constant(true)) {
			AboutDeveloperView()
				.presentationDetents([.height(480)])
				.presentationDragIndicator(.visible)
		}
}
