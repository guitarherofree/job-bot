import SwiftUI
import AppKit
import JobBotUI

@main
struct JobBotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var app = AppModel()

    var body: some Scene {
        Window("Job Bot", id: "main") {
            RootView()
                .environmentObject(app)
                .frame(minWidth: 1080, minHeight: 680)
                .onAppear {
                    delegate.app = app
                    app.start()
                }
        }
        .windowResizability(.contentMinSize)
        .commands { JobBotCommands(app: app) }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var app: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Needed when launched as a bare executable (`swift run`); harmless in a bundle.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated { app?.shutdown() }
    }
}
