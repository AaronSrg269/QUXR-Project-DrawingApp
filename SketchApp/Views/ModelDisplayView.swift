import SwiftUI
import RealityKit
import ARKit
import ModelIO
import Combine

struct ModelDisplayView: View {
    let glbData: Data?
    let isLoading: Bool

    var body: some View {
        ZStack {
            Theme.background
            ARModelContainer(glbData: glbData)
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

struct ARModelContainer: UIViewRepresentable {
    let glbData: Data?

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)
        arView.cameraMode = .nonAR
        arView.environment.background = .color(UIColor(red: 0.051, green: 0.059, blue: 0.102, alpha: 1.0)) // Theme.background #0D0F1A
        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        guard let data = glbData else { return }
        context.coordinator.load(data: data, into: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject {
        private var currentData: Data?
        private var rotationSubscription: (any Cancellable)?
        private weak var rotatingModel: Entity?

        func load(data: Data, into arView: ARView) {
            guard currentData != data else {
                print("[ModelLoad] skipped — data unchanged")
                return
            }
            currentData = data
            print("[ModelLoad] starting load, data size: \(data.count) bytes")

            Task.detached(priority: .userInitiated) {
                do {
                    let tmp = FileManager.default.temporaryDirectory

                    // Detect format by magic bytes:
                    // GLB  → starts with 0x46546C67 ("glTF")
                    // USDZ → starts with 0x504B0304 (PK zip)
                    let isGLB = data.prefix(4) == Data([0x67, 0x6C, 0x54, 0x46])
                    print("[ModelLoad] format detected: \(isGLB ? "GLB" : "USDZ")")

                    let usdzURL: URL
                    if isGLB {
                        let glbURL = tmp.appendingPathComponent("model_in.glb")
                        usdzURL    = tmp.appendingPathComponent("model_out.usdz")
                        try data.write(to: glbURL, options: [.atomic])
                        print("[ModelLoad] wrote GLB (\(data.count) bytes) to \(glbURL.lastPathComponent)")

                        // Convert GLB → USDZ via ModelIO off the main thread
                        let t0 = Date()
                        let asset = MDLAsset(url: glbURL)
                        asset.loadTextures()
                        guard MDLAsset.canExportFileExtension("usdz") else {
                            throw NSError(domain: "ModelLoad", code: 1,
                                userInfo: [NSLocalizedDescriptionKey: "ModelIO cannot export USDZ on this OS version"])
                        }
                        try asset.export(to: usdzURL)
                        print("[ModelLoad] ModelIO conversion done in \(String(format: "%.2f", -t0.timeIntervalSinceNow))s")
                    } else {
                        usdzURL = tmp.appendingPathComponent("model_in.usdz")
                        try data.write(to: usdzURL, options: [.atomic])
                        print("[ModelLoad] wrote USDZ (\(data.count) bytes) directly")
                    }

                    print("[ModelLoad] calling ModelEntity.load (synchronous)…")
                    let model = try ModelEntity.load(contentsOf: usdzURL)
                    print("[ModelLoad] ModelEntity.load succeeded: \(model)")

                    await MainActor.run {
                        arView.scene.anchors.removeAll()

                        // Apply a neutral grey PBR material to every ModelEntity in the hierarchy
                        // to replace RealityKit's pink "missing material" error pattern.
                        var mat = PhysicallyBasedMaterial()
                        mat.baseColor = .init(tint: .init(white: 0.75, alpha: 1.0))
                        mat.roughness = .init(floatLiteral: 0.6)
                        mat.metallic  = .init(floatLiteral: 0.1)
                        func applyMaterial(to entity: Entity) {
                            if let me = entity as? ModelEntity {
                                me.model?.materials = [mat]
                            }
                            for child in entity.children { applyMaterial(to: child) }
                        }
                        applyMaterial(to: model)

                        // Find the deepest ModelEntity for accurate bounds
                        func findMeshEntity(_ entity: Entity) -> ModelEntity? {
                            if let me = entity as? ModelEntity, me.model != nil { return me }
                            for child in entity.children {
                                if let found = findMeshEntity(child) { return found }
                            }
                            return nil
                        }
                        let meshEntity = findMeshEntity(model) ?? model as? ModelEntity

                        // Compute bounds on the mesh entity, fall back to root
                        let boundsEntity: Entity = meshEntity ?? model
                        let preBounds = boundsEntity.visualBounds(relativeTo: nil)
                        let preExtent = max(preBounds.extents.x, max(preBounds.extents.y, preBounds.extents.z))
                        print("[ModelLoad] meshEntity bounds extents=\(preBounds.extents) center=\(preBounds.center)")

                        // Scale to fit 1.6 m for comfortable viewing distance
                        let targetSize: Float = 1.6
                        let scale = preExtent > 0.001 ? targetSize / preExtent : 1.0
                        model.scale = SIMD3<Float>(repeating: scale)
                        let scaledCenter = preBounds.center * scale

                        // Centre and place 1.8 m in front of camera (camera looks down -Z)
                        model.position = SIMD3<Float>(-scaledCenter.x, -scaledCenter.y, -1.8)

                        let anchor = AnchorEntity(world: .zero)
                        anchor.addChild(model)
                        arView.scene.addAnchor(anchor)
                        self.rotatingModel = model

                        // Key light above-right, fill light from left
                        let keyAnchor = AnchorEntity(world: SIMD3<Float>(2, 3, 1))
                        var key = PointLight()
                        key.light.intensity = 80_000
                        key.light.color = .white
                        keyAnchor.addChild(key)
                        arView.scene.addAnchor(keyAnchor)

                        let fillAnchor = AnchorEntity(world: SIMD3<Float>(-2, 1, 1))
                        var fill = PointLight()
                        fill.light.intensity = 30_000
                        fill.light.color = .white
                        fillAnchor.addChild(fill)
                        arView.scene.addAnchor(fillAnchor)

                        // Slow Y-axis rotation: ~18°/s around the model's own centre
                        self.rotationSubscription?.cancel()
                        self.rotationSubscription = arView.scene.subscribe(to: SceneEvents.Update.self) { [weak self] event in
                            guard let entity = self?.rotatingModel else { return }
                            let angle = Float(event.deltaTime) * .pi / 10  // π/10 rad/s ≈ 18°/s
                            let dq = simd_quatf(angle: angle, axis: SIMD3<Float>(0, 1, 0))
                            entity.transform.rotation = entity.transform.rotation * dq
                        }

                        print("[ModelLoad] placed at \(model.position) scale \(scale)")
                    }
                } catch {
                    print("[ModelLoad] error: \(error)")
                }
            }
        }
    }
}
