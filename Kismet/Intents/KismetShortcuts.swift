import AppIntents

struct KismetShortcuts: AppShortcutsProvider {
	static var appShortcuts: [AppShortcut] {
		AppShortcut(
			intent: WhosFreeNearbyIntent(),
			phrases: [
				"Who's free nearby in \(.applicationName)",
				"Anyone free nearby in \(.applicationName)",
				"Anyone up for coffee in \(.applicationName)"
			],
			shortTitle: "Who's Free",
			systemImageName: "person.2.fill"
		)
		AppShortcut(
			intent: WhosNearbyIntent(),
			phrases: [
				"Who's nearby in \(.applicationName)"
			],
			shortTitle: "Who's Nearby",
			systemImageName: "mappin.and.ellipse"
		)
		AppShortcut(
			intent: DraftPulseIntent(),
			phrases: [
				"Draft a Pulse in \(.applicationName)",
				"Prepare a Pulse with \(.applicationName)"
			],
			shortTitle: "Draft Pulse",
			systemImageName: "square.and.pencil"
		)
		AppShortcut(
			intent: ConfirmPulseIntent(),
			phrases: [
				"Confirm Pulse in \(.applicationName)",
				"Send that Pulse with \(.applicationName)",
				"Send the Pulse draft in \(.applicationName)"
			],
			shortTitle: "Confirm Pulse",
			systemImageName: "paperplane.fill"
		)
		AppShortcut(
			intent: StartPulseIntent(),
			phrases: [
				"Start a Pulse in \(.applicationName)",
				"Send a Pulse with \(.applicationName)"
			],
			shortTitle: "Start Pulse",
			systemImageName: "wave.3.right"
		)
	}
}
