import SwiftUI

@main
struct CameraC64App: App {
    init() {
        SharedFile.removeOldFiles()
    }

    var body: some Scene {
        WindowGroup {
            CameraScreen()
        }
    }
}
