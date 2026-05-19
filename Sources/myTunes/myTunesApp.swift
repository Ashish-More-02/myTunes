import SwiftUI

@main
struct MyTunesApp: App {
    var body: some Scene {
        WindowGroup("myTunes") {
            ContentView()
        }
        .windowResizability(.contentMinSize)
    }
}
