import AppIntents

struct WhosOutShortcuts: AppShortcutsProvider {
	static var shortcutTileColor: ShortcutTileColor = .teal

	static var appShortcuts: [AppShortcut] {
		// Every phrase must include \(.applicationName) — resolves to "Who's Out".
		AppShortcut(
			intent: HowAreMyFriendsDoingIntent(),
			phrases: [
				"How are my friends doing in \(.applicationName)",
				"How are friends doing in \(.applicationName)",
				"How are my friends in \(.applicationName)",
				"What's up with my friends in \(.applicationName)",
				"Friend status in \(.applicationName)",
				"How is everyone doing in \(.applicationName)",
				"Ask \(.applicationName) how my friends are doing",
				"Who's out among my friends in \(.applicationName)"
			],
			shortTitle: "Friend Status",
			systemImageName: "person.3.fill"
		)
		AppShortcut(
			intent: SearchInWhosOutIntent(),
			phrases: [
				"Search \(.applicationName)",
				"Find friends in \(.applicationName)",
				"Look up friends in \(.applicationName)",
				"Who's out in \(.applicationName)"
			],
			shortTitle: "Search Friends",
			systemImageName: "magnifyingglass"
		)
		AppShortcut(
			intent: WhosFreeNearbyIntent(),
			phrases: [
				"Who's free nearby in \(.applicationName)",
				"Anyone free nearby in \(.applicationName)",
				"Anyone up for coffee in \(.applicationName)",
				"Who's out nearby in \(.applicationName)"
			],
			shortTitle: "Who's Free",
			systemImageName: "person.2.fill"
		)
		AppShortcut(
			intent: WhosNearbyIntent(),
			phrases: [
				"Who's nearby in \(.applicationName)",
				"Who's out around me in \(.applicationName)"
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
		AppShortcut(
			intent: PulseThemIntent(),
			phrases: [
				"Pulse them in \(.applicationName)",
				"Pulse my friends in \(.applicationName)",
				"Pulse everyone nearby in \(.applicationName)",
				"Send them a Pulse in \(.applicationName)",
				"Pulse friends nearby in \(.applicationName)",
				"Ask \(.applicationName) to Pulse them"
			],
			shortTitle: "Pulse Them",
			systemImageName: "wave.3.forward"
		)
	}
}
