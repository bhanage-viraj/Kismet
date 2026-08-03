import AppIntents

struct KismetShortcuts: AppShortcutsProvider {
	static var appShortcuts: [AppShortcut] {
		// Apple requires \(.applicationName) in every phrase. Say "Kismet" (or "Orbit")
		// instead of "indeKismet" — those are registered as INAlternativeAppNames.
		AppShortcut(
			intent: HowAreMyFriendsDoingIntent(),
			phrases: [
				"How are my friends doing in \(.applicationName)",
				"How are my friends in \(.applicationName)",
				"What's up with my friends in \(.applicationName)",
				"Friend status in \(.applicationName)",
				"How is everyone doing in \(.applicationName)",
				"\(.applicationName) how are my friends doing",
				"Ask \(.applicationName) how my friends are doing"
			],
			shortTitle: "Friend Status",
			systemImageName: "person.3.fill"
		)
		AppShortcut(
			intent: WhosFreeNearbyIntent(),
			phrases: [
				"Who's free nearby in \(.applicationName)",
				"Anyone free nearby in \(.applicationName)",
				"Anyone up for coffee in \(.applicationName)",
				"\(.applicationName) who's free nearby"
			],
			shortTitle: "Who's Free",
			systemImageName: "person.2.fill"
		)
		AppShortcut(
			intent: WhosNearbyIntent(),
			phrases: [
				"Who's nearby in \(.applicationName)",
				"\(.applicationName) who's nearby"
			],
			shortTitle: "Who's Nearby",
			systemImageName: "mappin.and.ellipse"
		)
		AppShortcut(
			intent: StartPulseIntent(),
			phrases: [
				"Start a Pulse in \(.applicationName)",
				"Send a Pulse with \(.applicationName)",
				"\(.applicationName) start a Pulse"
			],
			shortTitle: "Start Pulse",
			systemImageName: "wave.3.right"
		)
	}
}
