import SwiftUI

@main
struct Warp12ReleaseHeadApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var runner = BuildRunner()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(runner)
        }
        .defaultSize(width: 720, height: 640)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
