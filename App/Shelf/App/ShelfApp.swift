import AppKit
import ShelfCore
import SwiftUI

@main
struct ShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(replayOnboarding: { delegate.showOnboarding() })
                .environment(delegate.model)
        } label: {
            Image(systemName: "square.grid.2x2.fill")
                .accessibilityLabel("Shelf")
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(replayOnboarding: { delegate.showOnboarding() })
                .environment(delegate.model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private(set) lazy var host = DesktopHost(model: model)
    private var onboarding: OnboardingController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        Theme.registerFonts()
        if let directory = SnapshotRenderer.directory(from: ProcessInfo.processInfo.arguments) {
            SnapshotRenderer.run(into: directory, model: model)
            NSApp.terminate(nil)
            return
        }
        host.start()
        model.nowPlaying.start()
        if !model.onboardingCompleted || ProcessInfo.processInfo.arguments.contains("--onboarding") {
            showOnboarding()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls where url.scheme == "shelf" {
            switch url.host() {
            case "edit": model.isEditing = true
            case "add": model.isEditing = true; model.showingGallery = true
            case "welcome": showOnboarding()
            default: break
            }
        }
    }

    func showOnboarding() {
        if let onboarding {
            onboarding.focus()
            return
        }
        let controller = OnboardingController(model: model, host: host) { [weak self] in
            self?.onboarding = nil
        }
        onboarding = controller
        controller.show()
    }
}
