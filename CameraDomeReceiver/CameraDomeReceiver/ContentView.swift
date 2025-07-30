import SwiftUI
import RealityKitContent

struct ContentView: View {
    @ObservedObject var udpReceiver: UDPReceiver
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace
    @Binding var useSplitHemisphere: Bool

    @State private var isImmersiveSpaceOpen = false

    var body: some View {
        VStack {
            Text("UDP Video Stream")
                .font(.largeTitle)

            Toggle("Use Split Hemisphere", isOn: $useSplitHemisphere)
                .padding()

            Button(isImmersiveSpaceOpen ? "Close Immersive Space" : "Enter Immersive Space") {
                Task {
                    if isImmersiveSpaceOpen {
                        await dismissImmersiveSpace()
                        isImmersiveSpaceOpen = false
                    } else {
                        await openImmersiveSpace(id: "VideoHemisphere")
                        isImmersiveSpaceOpen = true
                    }
                }
            }
            .padding()
            .buttonStyle(.borderedProminent)
        }
    }
}
