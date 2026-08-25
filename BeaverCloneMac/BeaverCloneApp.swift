import SwiftUI
import BeaverCloneKit

@main
struct BeaverCloneApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 700, minHeight: 450)
        }
        .windowStyle(.automatic)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        #if os(macOS)
        Settings {
            SettingsView()
                .frame(width: 480, height: 420)
        }
        #endif
    }
}
