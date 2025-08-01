import SwiftUI

@main
struct UDPVideoHemisphereApp: App {
    @StateObject private var udpReceiver = UDPReceiver(port: 15001)
    @State private var useSplitHemisphere = false
    
    var body: some Scene {
        WindowGroup {
            ContentView(udpReceiver: udpReceiver, useSplitHemisphere: $useSplitHemisphere)
            
        }
        
        ImmersiveSpace(id: "VideoHemisphere") {
            HemisphereView(udpReceiver: udpReceiver, useSplitHemisphere: $useSplitHemisphere)
        }
    }
}

