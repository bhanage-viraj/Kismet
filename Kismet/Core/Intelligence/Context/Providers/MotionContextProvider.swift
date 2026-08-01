import CoreMotion
import Foundation

struct MotionContextProvider: ContextProviding {
	func current() async -> MotionSlice {
		guard CMMotionActivityManager.isActivityAvailable() else {
			return MotionSlice(activity: .unknown)
		}

		return await withCheckedContinuation { continuation in
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
