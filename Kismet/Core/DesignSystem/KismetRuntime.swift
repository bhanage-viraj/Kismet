import Foundation

enum KismetRuntime {
	static var isXcodePreview: Bool {
		let env = ProcessInfo.processInfo.environment
		if env["XCODE_RUNNING_FOR_PREVIEWS"] == "1" { return true }
		if env["XCODE_RUNNING_FOR_PLAYGROUNDS"] == "1" { return true }
		return Bundle.main.bundleURL.path.contains("/Previews/")
	}
}
