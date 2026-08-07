import CoreMotion
import Foundation

struct MotionContextProvider: ContextProviding {
	private static let queryTimeout: Duration = .milliseconds(300)

	func current() async -> MotionSlice {
		guard CMMotionActivityManager.isActivityAvailable() else {
			return MotionSlice(activity: .unknown)
		}

		return await withTaskGroup(of: MotionSlice.self) { group in
			group.addTask { await self.queryActivity() }
			group.addTask {
				try? await Task.sleep(for: Self.queryTimeout)
				return MotionSlice(activity: .unknown)
			}
			let first = await group.next() ?? MotionSlice(activity: .unknown)
			group.cancelAll()
			return first
		}
	}

	private func queryActivity() async -> MotionSlice {
		await withCheckedContinuation { continuation in
			let manager = CMMotionActivityManager()
			let queue = OperationQueue()
			queue.maxConcurrentOperationCount = 1
			var resumed = false

			func finish(_ slice: MotionSlice) {
				guard !resumed else { return }
				resumed = true
				continuation.resume(returning: slice)
			}

			manager.queryActivityStarting(
				from: Date().addingTimeInterval(-120),
				to: Date(),
				to: queue
			) { activities, _ in
				guard let activity = activities?.last else {
					finish(MotionSlice(activity: .unknown))
					return
				}
				if activity.automotive {
					finish(MotionSlice(activity: .automotive))
				} else if activity.walking || activity.running {
					finish(MotionSlice(activity: .walking))
				} else if activity.stationary {
					finish(MotionSlice(activity: .stationary))
				} else {
					finish(MotionSlice(activity: .unknown))
				}
			}
		}
	}
}
