import CoreGraphics
import Foundation
import SwiftUI

/// Apple Weather–style particle sim: depth layers, wind, and splash-on-UI collisions.
@MainActor
final class WeatherParticleEngine {
	private enum Kind {
		case rain
		case snow
	}

	private struct Drop {
		var x: CGFloat
		var y: CGFloat
		var speed: CGFloat
		var length: CGFloat
		var width: CGFloat
		var opacity: CGFloat
		var depth: CGFloat
		var drift: CGFloat
		var wobble: CGFloat
		var phase: CGFloat
		var canCollide: Bool
		var kind: Kind
	}

	private struct SplashDroplet {
		var x: CGFloat
		var y: CGFloat
		var vx: CGFloat
		var vy: CGFloat
		var life: CGFloat
		var maxLife: CGFloat
		var size: CGFloat
	}

	private struct Splash {
		var droplets: [SplashDroplet]
	}

	private var drops: [Drop] = []
	private var splashes: [Splash] = []
	private var lastDate: Date?
	private var flashRemaining: TimeInterval = 0
	private var nextFlashIn: TimeInterval = 1.8
	private var seededFor: (MapWeatherCondition, Int, CGSize)?
	private var windAngle: CGFloat = -0.28

	func tick(
		date: Date,
		size: CGSize,
		condition: MapWeatherCondition,
		intensity: Double,
		obstacles: [WeatherObstacle]
	) {
		guard size.width > 1, size.height > 1 else { return }

		let dt: CGFloat
		if let lastDate {
			dt = CGFloat(min(date.timeIntervalSince(lastDate), 1.0 / 20.0))
		} else {
			dt = 1.0 / 60.0
		}
		lastDate = date

		windAngle = Self.angle(for: condition)
		ensureSeeded(condition: condition, size: size, intensity: intensity)

		switch condition {
		case .drizzle, .rain, .heavyRain, .thunderstorm:
			advanceRain(
				dt: dt,
				size: size,
				condition: condition,
				intensity: intensity,
				obstacles: obstacles
			)
		case .snow:
			advanceSnow(dt: dt, size: size, intensity: intensity, obstacles: obstacles)
		case .fog, .cloudy, .clear:
			drops.removeAll(keepingCapacity: true)
			splashes.removeAll(keepingCapacity: true)
		}

		advanceSplashes(dt: dt)

		if condition == .thunderstorm {
			advanceLightning(dt: TimeInterval(dt))
		} else {
			flashRemaining = 0
		}
	}

	func draw(
		context: GraphicsContext,
		size: CGSize,
		condition: MapWeatherCondition,
		intensity: Double
	) {
		drawAtmosphere(context: context, size: size, condition: condition, intensity: intensity)

		switch condition {
		case .drizzle, .rain, .heavyRain, .thunderstorm:
			drawRain(context: context)
			drawSplashes(context: context)
		case .snow:
			drawSnow(context: context)
			drawSplashes(context: context, snowy: true)
		case .fog:
			drawFog(context: context, size: size, intensity: intensity)
		case .cloudy, .clear:
			break
		}

		if flashRemaining > 0 {
			let flashOpacity = min(flashRemaining / 0.18, 1) * 0.55
			context.fill(
				Path(CGRect(origin: .zero, size: size)),
				with: .color(.white.opacity(flashOpacity))
			)
		}
	}

	// MARK: - Seeding

	private func ensureSeeded(condition: MapWeatherCondition, size: CGSize, intensity: Double) {
		let count = targetCount(condition: condition, intensity: intensity)
		if let seededFor,
		   seededFor.0 == condition,
		   seededFor.1 == count,
		   abs(seededFor.2.width - size.width) < 2,
		   abs(seededFor.2.height - size.height) < 2 {
			return
		}
		seededFor = (condition, count, size)
		drops = (0..<count).map { _ in
			spawn(condition: condition, size: size, intensity: intensity, fromTop: true)
		}
		splashes.removeAll(keepingCapacity: true)
		nextFlashIn = Double.random(in: 1.2...3.2)
		flashRemaining = 0
	}

	private func targetCount(condition: MapWeatherCondition, intensity: Double) -> Int {
		switch condition {
		case .drizzle: Int(55 + 70 * intensity)
		case .rain: Int(110 + 140 * intensity)
		case .heavyRain: Int(180 + 160 * intensity)
		case .thunderstorm: Int(200 + 180 * intensity)
		case .snow: Int(70 + 90 * intensity)
		default: 0
		}
	}

	private func spawn(
		condition: MapWeatherCondition,
		size: CGSize,
		intensity: Double,
		fromTop: Bool
	) -> Drop {
		let depth = CGFloat.random(in: 0.15...1)
		let depthBias = 0.45 + depth * 0.55
		let xPad = size.width * 0.12
		let x = CGFloat.random(in: -xPad...(size.width + xPad))
		let y: CGFloat = fromTop
			? CGFloat.random(in: -size.height...(size.height * 0.9))
			: -CGFloat.random(in: 10...90)

		// Nearer drops collide with chrome; enough of them that tab bar / cards clearly splash.
		let collideChance: CGFloat = condition == .snow ? 0.55 : 0.78
		let canCollide = depth > 0.35 && CGFloat.random(in: 0...1) < collideChance

		if condition == .snow {
			let scale = (1.6 + depth * 2.2) * CGFloat(0.7 + intensity * 0.4)
			return Drop(
				x: x,
				y: y,
				speed: CGFloat.random(in: 24...58) * depthBias * CGFloat(0.6 + intensity * 0.6),
				length: scale,
				width: scale,
				opacity: (0.25 + depth * 0.55) * CGFloat(0.7 + intensity * 0.3),
				depth: depth,
				drift: CGFloat.random(in: -18...18),
				wobble: CGFloat.random(in: 6...16),
				phase: CGFloat.random(in: 0...(2 * .pi)),
				canCollide: canCollide,
				kind: .snow
			)
		}

		let heavy = condition == .heavyRain || condition == .thunderstorm
		let baseSpeed = heavy ? CGFloat.random(in: 520...860) : CGFloat.random(in: 340...620)
		return Drop(
			x: x,
			y: y,
			speed: baseSpeed * depthBias * CGFloat(0.75 + intensity * 0.45),
			length: (heavy ? CGFloat.random(in: 12...24) : CGFloat.random(in: 9...17)) * depthBias,
			width: (heavy ? CGFloat.random(in: 1.0...1.7) : CGFloat.random(in: 0.7...1.25)) * depthBias,
			opacity: (heavy ? 0.22 : 0.14) + depth * 0.38,
			depth: depth,
			drift: CGFloat.random(in: -10...(-2)),
			wobble: 0,
			phase: 0,
			canCollide: canCollide,
			kind: .rain
		)
	}

	// MARK: - Advance

	private func advanceRain(
		dt: CGFloat,
		size: CGSize,
		condition: MapWeatherCondition,
		intensity: Double,
		obstacles: [WeatherObstacle]
	) {
		let windX = sin(windAngle) * 220
		let tipDX = sin(windAngle)
		let tipDY = cos(windAngle)

		var index = 0
		while index < drops.count {
			var drop = drops[index]
			let previousTipY = drop.y + tipDY * drop.length
			drop.y += drop.speed * dt
			drop.x += (drop.drift + windX) * dt * 0.28

			let tipX = drop.x + tipDX * drop.length
			let tipY = drop.y + tipDY * drop.length

			if drop.canCollide,
			   let hit = firstHit(
				tipX: tipX,
				tipY: tipY,
				previousY: previousTipY,
				step: max(drop.speed * dt, 12),
				obstacles: obstacles
			   ) {
				spawnSplash(at: CGPoint(x: tipX, y: hit.topY + 1), depth: drop.depth, snowy: false)
				drops[index] = spawn(condition: condition, size: size, intensity: intensity, fromTop: false)
				continue
			}

			if tipY > size.height + 40 || tipX < -80 || tipX > size.width + 80 {
				drops[index] = spawn(condition: condition, size: size, intensity: intensity, fromTop: false)
			} else {
				drops[index] = drop
				index += 1
			}
		}
	}

	private func advanceSnow(
		dt: CGFloat,
		size: CGSize,
		intensity: Double,
		obstacles: [WeatherObstacle]
	) {
		var index = 0
		while index < drops.count {
			var drop = drops[index]
			drop.phase += dt * 2.1
			let previousY = drop.y
			drop.y += drop.speed * dt
			drop.x += (drop.drift + sin(drop.phase) * drop.wobble) * dt

			if drop.canCollide,
			   let hit = firstHit(
				tipX: drop.x,
				tipY: drop.y,
				previousY: previousY,
				step: max(drop.speed * dt, 10),
				obstacles: obstacles
			   ) {
				spawnSplash(at: CGPoint(x: drop.x, y: hit.topY + 1), depth: drop.depth, snowy: true)
				drops[index] = spawn(condition: .snow, size: size, intensity: intensity, fromTop: false)
				continue
			}

			if drop.y > size.height + 24 {
				drops[index] = spawn(condition: .snow, size: size, intensity: intensity, fromTop: false)
			} else {
				drops[index] = drop
				index += 1
			}
		}
	}

	private func firstHit(
		tipX: CGFloat,
		tipY: CGFloat,
		previousY: CGFloat,
		step: CGFloat,
		obstacles: [WeatherObstacle]
	) -> WeatherObstacle? {
		var best: WeatherObstacle?
		let band = max(step + 8, 28)
		for obstacle in obstacles {
			// Only the flat top of the rounded shape — not the empty side margins / corner cutouts.
			guard obstacle.containsTopEdge(atX: tipX) else { continue }
			let top = obstacle.topY
			let crossed = previousY <= top && tipY >= top
			let landedInBand = tipY >= top - 2 && tipY <= top + band && tipY <= obstacle.rect.maxY
			guard crossed || landedInBand else { continue }
			if best == nil || top < best!.topY {
				best = obstacle
			}
		}
		return best
	}

	private func spawnSplash(at point: CGPoint, depth: CGFloat, snowy: Bool) {
		let count = snowy ? Int.random(in: 2...3) : Int.random(in: 3...5)
		var droplets: [SplashDroplet] = []
		droplets.reserveCapacity(count)
		for _ in 0..<count {
			let angle = CGFloat.random(in: (-.pi * 0.92)...(-.pi * 0.08))
			let speed = CGFloat.random(in: snowy ? 28...70 : 55...130) * (0.55 + depth * 0.6)
			let life = CGFloat.random(in: 0.18...0.38)
			droplets.append(
				SplashDroplet(
					x: point.x + CGFloat.random(in: -3...3),
					y: point.y,
					vx: cos(angle) * speed,
					vy: sin(angle) * speed,
					life: life,
					maxLife: life,
					size: (snowy ? CGFloat.random(in: 1.4...2.6) : CGFloat.random(in: 1.1...2.2)) * (0.6 + depth * 0.5)
				)
			)
		}
		splashes.append(Splash(droplets: droplets))
		if splashes.count > 80 {
			splashes.removeFirst(splashes.count - 80)
		}
	}

	private func advanceSplashes(dt: CGFloat) {
		guard !splashes.isEmpty else { return }
		var next: [Splash] = []
		next.reserveCapacity(splashes.count)
		for splash in splashes {
			var droplets: [SplashDroplet] = []
			for var droplet in splash.droplets {
				droplet.life -= dt
				guard droplet.life > 0 else { continue }
				droplet.x += droplet.vx * dt
				droplet.y += droplet.vy * dt
				droplet.vy += 420 * dt
				droplet.vx *= (1 - 1.8 * dt)
				droplets.append(droplet)
			}
			if !droplets.isEmpty {
				next.append(Splash(droplets: droplets))
			}
		}
		splashes = next
	}

	private func advanceLightning(dt: TimeInterval) {
		if flashRemaining > 0 {
			flashRemaining = max(0, flashRemaining - dt)
			return
		}
		nextFlashIn -= dt
		if nextFlashIn <= 0 {
			flashRemaining = Double.random(in: 0.08...0.22)
			nextFlashIn = Double.random(in: 1.4...4.5)
		}
	}

	// MARK: - Draw

	private func drawAtmosphere(
		context: GraphicsContext,
		size: CGSize,
		condition: MapWeatherCondition,
		intensity: Double
	) {
		let rect = CGRect(origin: .zero, size: size)
		let strength = min(max(intensity, 0), 1)

		let color: Color
		let opacity: Double
		switch condition {
		case .clear:
			return
		case .cloudy:
			color = Color(red: 0.55, green: 0.60, blue: 0.68)
			opacity = 0.10 + 0.08 * strength
		case .drizzle:
			color = Color(red: 0.32, green: 0.40, blue: 0.54)
			opacity = 0.12 + 0.10 * strength
		case .rain:
			color = Color(red: 0.20, green: 0.28, blue: 0.44)
			opacity = 0.16 + 0.14 * strength
		case .heavyRain:
			color = Color(red: 0.12, green: 0.18, blue: 0.32)
			opacity = 0.24 + 0.16 * strength
		case .thunderstorm:
			color = Color(red: 0.08, green: 0.10, blue: 0.26)
			opacity = 0.30 + 0.18 * strength
		case .snow:
			color = Color(red: 0.72, green: 0.78, blue: 0.88)
			opacity = 0.10 + 0.12 * strength
		case .fog:
			color = Color(red: 0.78, green: 0.80, blue: 0.84)
			opacity = 0.20 + 0.20 * strength
		}

		context.fill(Path(rect), with: .color(color.opacity(opacity)))
	}

	private func drawRain(context: GraphicsContext) {
		// Far → near so closer streaks sit on top.
		let ordered = drops.sorted { $0.depth < $1.depth }
		for drop in ordered where drop.kind == .rain {
			var path = Path()
			let dx = sin(windAngle) * drop.length
			let dy = cos(windAngle) * drop.length
			path.move(to: CGPoint(x: drop.x, y: drop.y))
			path.addLine(to: CGPoint(x: drop.x + dx, y: drop.y + dy))
			context.stroke(
				path,
				with: .color(Color.white.opacity(drop.opacity)),
				style: StrokeStyle(lineWidth: drop.width, lineCap: .round)
			)
			// Soft tip — Weather-app droplet head.
			let tip = CGRect(
				x: drop.x + dx - drop.width * 0.7,
				y: drop.y + dy - drop.width * 0.7,
				width: drop.width * 1.4,
				height: drop.width * 1.4
			)
			context.fill(Path(ellipseIn: tip), with: .color(Color.white.opacity(drop.opacity * 0.85)))
		}
	}

	private func drawSnow(context: GraphicsContext) {
		let ordered = drops.sorted { $0.depth < $1.depth }
		for drop in ordered where drop.kind == .snow {
			let rect = CGRect(
				x: drop.x - drop.width / 2,
				y: drop.y - drop.length / 2,
				width: drop.width,
				height: drop.length
			)
			context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(drop.opacity)))
		}
	}

	private func drawSplashes(context: GraphicsContext, snowy: Bool = false) {
		for splash in splashes {
			for droplet in splash.droplets {
				let t = max(droplet.life / droplet.maxLife, 0)
				let opacity = t * (snowy ? 0.7 : 0.85)
				let size = droplet.size * (0.55 + 0.45 * t)
				let rect = CGRect(
					x: droplet.x - size / 2,
					y: droplet.y - size / 2,
					width: size,
					height: size
				)
				context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(opacity)))
			}
		}
	}

	private func drawFog(context: GraphicsContext, size: CGSize, intensity: Double) {
		let strength = CGFloat(min(max(intensity, 0), 1))
		for band in 0..<4 {
			let y = size.height * (0.15 + CGFloat(band) * 0.18)
			let height = size.height * (0.22 + strength * 0.08)
			let rect = CGRect(x: -20, y: y, width: size.width + 40, height: height)
			let opacity = 0.10 + 0.06 * Double(strength) + Double(band) * 0.02
			context.fill(Path(ellipseIn: rect), with: .color(Color.white.opacity(opacity)))
		}
	}

	private static func angle(for condition: MapWeatherCondition) -> CGFloat {
		switch condition {
		case .thunderstorm: -0.40
		case .heavyRain: -0.34
		case .rain: -0.28
		case .drizzle: -0.22
		default: -0.28
		}
	}
}
