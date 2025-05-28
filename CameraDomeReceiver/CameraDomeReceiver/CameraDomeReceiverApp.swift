import SwiftUI

@main
struct UDPVideoHemisphereApp: App {
    @StateObject private var udpReceiver = UDPReceiver(port: 15001) 
    
    var body: some Scene {
        WindowGroup {
            ContentView(udpReceiver: udpReceiver)
            
        }
        
        ImmersiveSpace(id: "VideoHemisphere") {
            HemisphereView(udpReceiver: udpReceiver)
        }
    }
}

