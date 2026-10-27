import SwiftUI
import AppKit

@main
struct PokeNX2iOSApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var builder = Builder()

    var body: some Scene {
        WindowGroup("PokeNX2iOS") {
            ContentView()
                .environmentObject(builder)
                .frame(minWidth: 820, minHeight: 760)
                .onAppear { builder.checkRequirements() }
        }
        .windowResizability(.contentMinSize)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // started with `swift run` the process is not an app bundle: give it a Dock icon and focus
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
