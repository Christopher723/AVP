import SwiftUI
import RealityKit
import RealityKitContent

struct ContentView: View {
    @ObservedObject var udpReceiver: UDPReceiver
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    
    var body: some View {
        VStack {
            Text("UDP Video Stream")
                .font(.largeTitle)
            
            Button("Enter Immersive Space") {
                Task {
                    await openImmersiveSpace(id: "VideoHemisphere")
                }
            }
            .padding()
            .buttonStyle(.borderedProminent)
        }
    }
}
