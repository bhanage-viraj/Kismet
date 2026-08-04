import AppIntents
import WidgetKit

/// Home Screen widget button — queues Accept and opens the app to finish ack + Live Activity.
struct AcceptPulseIntent: AppIntent {
	static var title: LocalizedStringResource = "Accept Pulse"
	static var description = IntentDescription("Accept the open Pulse from a friend.")
	static var openAppWhenRun: Bool = true

	@Parameter(title: "Blob ID")
	var blobId: String

	init() {
		self.blobId = ""
	}

	init(blobId: String) {
		self.blobId = blobId
	}

	func perform() async throws -> some IntentResult {
		guard !blobId.isEmpty else { return .result() }
		WidgetAppGroup.pendingAcceptPulseBlobId = blobId
		return .result()
	}
}
