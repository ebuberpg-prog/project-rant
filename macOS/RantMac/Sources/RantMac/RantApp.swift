import AppKit
import SwiftUI

@main
struct RantApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = RantModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 600)
                .onAppear { appDelegate.attach(model) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 920, height: 720)

        Settings {
            SettingsView()
                .environmentObject(model)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var model: RantModel?
    private var hotKey = GlobalHotKey()
    private var companion: LocalCompanion?
    private var shortcutLabel: String?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        hotKey.onPress = { [weak self] in
            Task { @MainActor in self?.model?.toggleFromShortcut() }
        }
        hotKey.onRegistration = { [weak self] label in
            self?.shortcutLabel = label
            Task { @MainActor in self?.model?.setShortcutLabel(label) }
        }
        hotKey.register()
    }

    @MainActor func attach(_ model: RantModel) {
        self.model = model
        model.setShortcutLabel(shortcutLabel)
        if companion == nil { companion = LocalCompanion(model: model) }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
