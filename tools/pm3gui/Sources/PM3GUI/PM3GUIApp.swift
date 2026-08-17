import SwiftUI
import AppKit

@main
struct PM3GUIApp: App {

    init() {
        // Built by SwiftPM as a bare executable rather than a .app bundle, so
        // the activation policy has to be set by hand or the window opens
        // behind everything with no Dock icon.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup("Proxmark3 LF Tags") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
    }
}
