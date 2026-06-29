import SwiftUI
import RealityKit
import ARKit
import Combine

struct ModelDisplayView: View {
    let glbData: Data?
    let isLoading: Bool

    var body: some View {
        ZStack {
            Theme.background
            ModelContainer(glbData: glbData)
            if isLoading {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(Theme.accent)
            } else if glbData == nil {
                VStack(spacing: 8) {
                    Image(systemName: "rotate.3d")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.accent.opacity(0.5))
                    Text("Generated model will appear here")
                        .foregroundColor(Theme.textPrimary.opacity(0.45))
                        .font(.subheadline)
                }
            }
        }
    }
}

struct ModelContainer: UIViewRepresentable {
    let glbData: Data?

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.cameraMode = .nonAR
        arView.environment.background = .color(UIColor(red: 0.051, green: 0.059, blue: 0.102, alpha: 1.0))
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        guard let data = glbData else {
            context.coordinator.reset(in: uiView)
            return
        }
        context.coordinator.load(data: data, into: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        private var currentData: Data?
        private var rotationSubscription: (any Cancellable)?
        private weak var rotatingModel: Entity?

        @MainActor func reset(in arView: ARView) {
            currentData = nil
            rotatingModel = nil
            rotationSubscription?.cancel()
            rotationSubscription = nil
            arView.scene.anchors.removeAll()
        }

        func load(data: Data, into arView: ARView) {
            guard currentData != data else { return }
            currentData = data
            print("[ModelLoad] starting load, data size: \(data.count) bytes")

            Task.detached(priority: .userInitiated) {
                do {
                    let tmp = FileManager.default.temporaryDirectory

                    // Detect format by magic bytes:
                    // GLB  → starts with 0x676C5446 ("glTF")
                    // USDZ → starts with 0x504B0304 (PK zip)
                    let isGLB = data.prefix(4) == Data([0x67, 0x6C, 0x54, 0x46])
                    print("[ModelLoad] format detected: \(isGLB ? "GLB" : "USDZ")")

                    let modelURL = tmp.appendingPathComponent(isGLB ? "model_in.glb" : "model_in.usdz")
                    try data.write(to: modelURL, options: [.atomic])
                    print("[ModelLoad] wrote \(isGLB ? "GLB" : "USDZ") to \(modelURL.path)")

                    if isGLB {
                        let entity = try await Entity(contentsOf: modelURL)
                        await self.display(entity: entity, in: arView)
                    } else {
                        await self.displayUSDZ(url: modelURL, in: arView)
                    }
                } catch {
                    print("[ModelLoad] error: \(error)")
                }
            }
        }

        @MainActor private func displayUSDZ(url: URL, in arView: ARView) {
            do {
                let entity = try ModelEntity.load(contentsOf: url)
                display(entity: entity, in: arView)
            } catch {
                print("[ModelLoad] error: \(error)")
            }
        }

        @MainActor private func display(entity: Entity, in arView: ARView) {
            arView.scene.anchors.removeAll()

            // Replace materials with a neutral grey PBR look
            var grey = PhysicallyBasedMaterial()
            grey.baseColor = .init(tint: .init(white: 0.75, alpha: 1.0))
            grey.roughness = .init(floatLiteral: 0.6)
            grey.metallic = .init(floatLiteral: 0.1)
            func applyMaterial(to entity: Entity) {
                if let model = entity as? ModelEntity {
                    model.model?.materials = [grey]
                }
                for child in entity.children { applyMaterial(to: child) }
            }
            applyMaterial(to: entity)

            // Scale and centre based on the actual mesh bounds
            let bounds = entity.visualBounds(relativeTo: nil)
            let extent = max(bounds.extents.x, max(bounds.extents.y, bounds.extents.z))
            let targetSize: Float = 1.6
            let scale = extent > 0.001 ? targetSize / extent : 1.0
            entity.scale = SIMD3<Float>(repeating: scale)
            let scaledCenter = bounds.center * scale
            entity.position = SIMD3<Float>(-scaledCenter.x, -scaledCenter.y, -scaledCenter.z)

            let anchor = AnchorEntity(world: .zero)
            anchor.addChild(entity)
            arView.scene.addAnchor(anchor)
            self.rotatingModel = entity

            // Lights
            let key = AnchorEntity(world: SIMD3<Float>(2, 3, 1))
            let keyLight = PointLight()
            keyLight.light.intensity = 80_000
            keyLight.light.color = .white
            key.addChild(keyLight)
            arView.scene.addAnchor(key)

            let fill = AnchorEntity(world: SIMD3<Float>(-2, 1, 1))
            let fillLight = PointLight()
            fillLight.light.intensity = 30_000
            fillLight.light.color = .white
            fill.addChild(fillLight)
            arView.scene.addAnchor(fill)

            // Slow rotation around the entity's own Y axis
            self.rotationSubscription?.cancel()
            self.rotationSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                guard let entity = self?.rotatingModel else { return }
                let angle = Float(event.deltaTime) * .pi / 10
                let dq = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
                entity.transform.rotation = entity.transform.rotation * dq
            }

            print("[ModelLoad] displayed scale=\(scale) extent=\(extent)")
        }
    }
}
