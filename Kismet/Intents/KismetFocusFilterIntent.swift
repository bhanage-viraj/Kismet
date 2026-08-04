import AppIntents
import Foundation

/// Appears under Settings → Focus → [Focus] → Focus Filters → Kismet.
struct KismetFocusFilterIntent: SetFocusFilterIntent {
	static var title: LocalizedStringResource = "Kismet"
	static var description = IntentDescription(
		"Pause meetup suggestions while this Focus is on."
	)

	@Parameter(title: "Pause suggestions", default: true)
	var blocksSocial: Bool

	var displayRepresentation: DisplayRepresentation {
		DisplayRepresentation(
			title: "Kismet",
			subtitle: blocksSocial ? "Suggestions paused" : "Suggestions on"
		)
	}

	func perform() async throws -> some IntentResult {
		FocusSocialGate.setBlocksSocial(blocksSocial)
		return .result()
	}
}
