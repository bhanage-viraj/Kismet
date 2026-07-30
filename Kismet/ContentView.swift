//
//  ContentView.swift
//  Kismet
//
//  Created by Viraj Bhanage on 29/07/26.
//

import SwiftUI

struct ContentView: View {
	var body: some View {
		RootView()
	}
}

#Preview {
	ContentView()
		.environment(AuthSession())
}
