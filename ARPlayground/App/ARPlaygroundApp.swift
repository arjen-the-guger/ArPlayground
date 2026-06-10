import SwiftUI

@main
struct ARPlaygroundApp: App {
    @State private var scene = SceneModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(scene)
                .preferredColorScheme(.dark)
                .statusBarHidden(true)
                .persistentSystemOverlays(.hidden)
        }
    }
}
