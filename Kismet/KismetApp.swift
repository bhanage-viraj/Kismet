//
//  KismetApp.swift
//  Kismet
//
//  Created by Viraj Bhanage on 29/07/26.
//

import SwiftUI

@main
struct KismetApp: App {
	@State private var authSession = AppEnvironment.shared.authSession

	var body: some Scene {
		WindowGroup {
			ContentView()
				.environment(authSession)
				.task {
					await authSession.restore()
				}
		}
	}
}
