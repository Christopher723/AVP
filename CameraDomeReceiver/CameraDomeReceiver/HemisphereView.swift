import SwiftUI
import RealityKit

struct HemisphereView: View {
    @ObservedObject var udpReceiver: UDPReceiver
    @State private var backHemisphereEntity: ModelEntity?
    @State private var frontHemisphereEntity: ModelEntity?

    var body: some View {
        RealityView { content in
            // Back half: video texture
            var videoMaterial = UnlitMaterial()
            videoMaterial.color = .init(tint: .white)
            let backHemisphere = ModelEntity(
                mesh: .generateHalfHemisphere(radius: 5, back: true),
                materials: [videoMaterial]
            )
            backHemisphere.scale *= SIMD3<Float>(x: -1, y: 1, z: 1)

            // Front half: pitch black
            var blackMaterial = UnlitMaterial()
            blackMaterial.color = .init(tint: .black)
            let frontHemisphere = ModelEntity(
                mesh: .generateHalfHemisphere(radius: 5, back: false),
                materials: [blackMaterial]
            )
            frontHemisphere.scale *= SIMD3<Float>(x: -1, y: 1, z: 1)

            backHemisphereEntity = backHemisphere
            frontHemisphereEntity = frontHemisphere

            content.add(backHemisphere)
            content.add(frontHemisphere)
        }
        .onChange(of: udpReceiver.receivedFrameData) { _, newData in
            updateTexture(with: newData)
        }
    }

    private func updateTexture(with data: Data) {
        guard !data.isEmpty else { return }

        if let dataProvider = CGDataProvider(data: data as CFData),
           let cgImage = CGImage(
                jpegDataProviderSource: dataProvider,
                decode: nil,
                shouldInterpolate: true,
                intent: .defaultIntent
           ) {

            Task {
                do {
                    let texture = try await TextureResource(
                        image: cgImage,
                        options: .init(semantic: .color)
                    )

                    await MainActor.run {
                        if let backHemisphereEntity = backHemisphereEntity {
                            var material = UnlitMaterial()
                            material.color = .init(texture: .init(texture))
                            backHemisphereEntity.model?.materials = [material]
                        }
                    }
                } catch {
                    print("error generating texture: \(error)")
                }
            }
        }
    }
}

extension MeshResource {
    static func generateHalfHemisphere(radius: Float, back: Bool, segments: Int = 36, rings: Int = 18) -> MeshResource {
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        // θ range for front: [0, π]
        // θ range for back: [π, 2π]
        let thetaStart: Float = back ? Float.pi : 0
        let thetaEnd: Float = back ? 2 * Float.pi : Float.pi

        for ring in 0...rings {
            let phi = Float.pi * 0.5 * Float(ring) / Float(rings) // 0 to π/2
            let y = radius * sin(phi)
            let r = radius * cos(phi)
            let v = Float(ring) / Float(rings)
            for seg in 0...segments {
                let theta = thetaStart + (thetaEnd - thetaStart) * Float(seg) / Float(segments)
                let x = r * cos(theta)
                let z = r * sin(theta)
                vertices.append(SIMD3<Float>(x, y, z))
                normals.append(normalize(SIMD3<Float>(x, y, z)))


                let u: Float
                if back {
                    u = 0.5 * (1.0 - ((theta - Float.pi) / Float.pi))
                } else {
                    u = 0.5
                }
                uvs.append(SIMD2<Float>(u, v))
            }
        }
        for ring in 0..<rings {
            for seg in 0..<segments {
                let a = UInt32(ring * (segments + 1) + seg)
                let b = UInt32((ring + 1) * (segments + 1) + seg)
                let c = UInt32((ring + 1) * (segments + 1) + seg + 1)
                let d = UInt32(ring * (segments + 1) + seg + 1)

                indices.append(contentsOf: [a, b, d])
                indices.append(contentsOf: [b, c, d])
            }
        }
        var meshDescriptor = MeshDescriptor(name: back ? "BackHemisphere" : "FrontHemisphere")
        meshDescriptor.positions = MeshBuffer(vertices)
        meshDescriptor.normals = MeshBuffer(normals)
        meshDescriptor.textureCoordinates = MeshBuffer(uvs)
        meshDescriptor.primitives = .triangles(indices)
        return try! MeshResource.generate(from: [meshDescriptor])
    }
}
