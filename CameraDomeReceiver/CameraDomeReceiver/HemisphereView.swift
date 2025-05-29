import SwiftUI
import RealityKit
import Foundation
import Combine

struct HemisphereView: View {
    @ObservedObject var udpReceiver: UDPReceiver
    @State private var backHemisphereEntity: ModelEntity?
    @State private var frontHemisphereEntity: ModelEntity?
    @State private var fullHemisphereEntity: ModelEntity?
    @State private var useSplitHemisphere = true

    var body: some View {
        VStack {
            Toggle("Use Split Hemisphere", isOn: $useSplitHemisphere)
                .padding()

            RealityView { content in
                if useSplitHemisphere {
                    var videoMaterial = UnlitMaterial()
                    videoMaterial.color = .init(tint: .white)
                    let backHemisphere = ModelEntity(
                        mesh: .generateHalfHemisphere(radius: 5, back: true),
                        materials: [videoMaterial]
                    )
                    backHemisphere.scale *= SIMD3<Float>(x: -1, y: 1, z: 1)

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
                } else {
                    var material = UnlitMaterial()
                    material.color = .init(tint: .white)

                    let hemisphere = ModelEntity(
                        mesh: .generateHemisphere(radius: 5),
                        materials: [material]
                    )
                    hemisphere.scale *= SIMD3<Float>(x: -1, y: 1, z: 1)
                    hemisphere.components.set(
                        CollisionComponent(shapes: [.generateSphere(radius: 5)])
                    )

                    fullHemisphereEntity = hemisphere
                    content.add(hemisphere)
                }
            }
            .onChange(of: udpReceiver.receivedFrameData) { _, newData in
                updateTexture(with: newData)
            }
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
                        var material = UnlitMaterial()
                        material.color = .init(texture: .init(texture))

                        if useSplitHemisphere {
                            backHemisphereEntity?.model?.materials = [material]
                        } else {
                            fullHemisphereEntity?.model?.materials = [material]
                        }
                    }
                } catch {
                    print("Error generating texture: \(error)")
                }
            }
        }
    }
}

// MARK: - MeshResource Extensions

extension MeshResource {
    static func generateHemisphere(radius: Float, segments: Int = 36, rings: Int = 18) -> MeshResource {
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        for ring in 0...rings {
            let phi = Float.pi * 0.5 * Float(ring) / Float(rings)
            let y = radius * sin(phi)
            let r = radius * cos(phi)
            let v = Float(ring) / Float(rings)

            for seg in 0...segments {
                let theta = 2 * Float.pi * Float(seg) / Float(segments)
                let x = r * cos(theta)
                let z = r * sin(theta)

                vertices.append(SIMD3<Float>(x, y, z))
                normals.append(normalize(SIMD3<Float>(x, y, z)))
                uvs.append(SIMD2<Float>(Float(seg) / Float(segments), v))
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

        var descriptor = MeshDescriptor(name: "Hemisphere")
        descriptor.positions = MeshBuffer(vertices)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)

        return try! MeshResource.generate(from: [descriptor])
    }

    static func generateHalfHemisphere(radius: Float, back: Bool, segments: Int = 36, rings: Int = 18) -> MeshResource {
        var vertices: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var uvs: [SIMD2<Float>] = []
        var indices: [UInt32] = []

        let thetaStart: Float = back ? Float.pi : 0
        let thetaEnd: Float = back ? 2 * Float.pi : Float.pi

        for ring in 0...rings {
            let phi = Float.pi * 0.5 * Float(ring) / Float(rings)
            let y = radius * sin(phi)
            let r = radius * cos(phi)
            let v = Float(ring) / Float(rings)

            for seg in 0...segments {
                let theta = thetaStart + (thetaEnd - thetaStart) * Float(seg) / Float(segments)
                let x = r * cos(theta)
                let z = r * sin(theta)
                vertices.append(SIMD3<Float>(x, y, z))
                normals.append(normalize(SIMD3<Float>(x, y, z)))

                let u: Float = back
                    ? 1.0 - (0.5 + 0.5 * ((theta - Float.pi) / Float.pi))
                    : 1.0 - (0.5 * (theta / Float.pi))
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

        var descriptor = MeshDescriptor(name: back ? "BackHemisphere" : "FrontHemisphere")
        descriptor.positions = MeshBuffer(vertices)
        descriptor.normals = MeshBuffer(normals)
        descriptor.textureCoordinates = MeshBuffer(uvs)
        descriptor.primitives = .triangles(indices)

        return try! MeshResource.generate(from: [descriptor])
    }
}
