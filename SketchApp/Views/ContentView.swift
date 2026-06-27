import SwiftUI

struct ContentView: View {
    @StateObject private var strokeManager = StrokeManager()
    @State private var mode: DrawingMode = .pen
    @State private var canvasSize: CGSize = .zero
    @State private var glbData: Data?
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showError = false

    // DEV: set to true to load bundled test model instead of calling the backend
    private let useDevModel = true
    private let devModelName = "test_model"   // must match filename in bundle (without extension, expects .usdz)

    private let panelCornerRadius: CGFloat = 12
    private let panelPadding: CGFloat = 18
    private let panelGap: CGFloat = 16
    private let outerPadding: CGFloat = 20

    var body: some View {
        ZStack {
            Theme.background
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack(spacing: panelGap) {
                    GeometryReader { geometry in
                        DrawingCanvasView(strokeManager: strokeManager, mode: $mode)
                            .padding(panelPadding)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                            .onChange(of: geometry.size, initial: true) { _, newSize in
                                canvasSize = newSize
                            }
                    }
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: panelCornerRadius)
                            .stroke(Theme.accent.opacity(0.80), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius))

                    ModelDisplayView(glbData: glbData, isLoading: isLoading)
                        .padding(panelPadding)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Theme.background.opacity(0.92))
                        .overlay(
                            RoundedRectangle(cornerRadius: panelCornerRadius)
                                .stroke(Theme.accent.opacity(0.80), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius))
                }
                .frame(maxHeight: .infinity)

                HStack(spacing: 24) {
                    // TODO: re-enable erase mode
                    // AppButton(title: "Pen", isActive: mode == .pen) { mode = .pen }
                    // AppButton(title: "Erase", isActive: mode == .erase) { mode = .erase }

                    AppIconButton(systemImage: "arrow.uturn.backward") {
                        strokeManager.undo()
                    }
                    .disabled(!strokeManager.canUndo)

                    AppIconButton(systemImage: "arrow.uturn.forward") {
                        strokeManager.redo()
                    }
                    .disabled(!strokeManager.canRedo)

                    AppButton(title: "Reset") { strokeManager.clear() }
                        .disabled(strokeManager.strokes.isEmpty)

                    AppButton(
                        title: isLoading ? "Generating…" : "Finish",
                        color: Theme.buttonPink,
                        pressedColor: Theme.buttonPinkPressed,
                        action: generateModel
                    )
                    .disabled(isLoading || strokeManager.strokes.isEmpty)
                }
                .padding(.vertical, 12)
            }
            .padding(outerPadding)
        }
        .alert("Generation failed", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    private func generateModel() {
        guard !isLoading else { return }

        if useDevModel {
            // DEV: loads bundled test file instead of calling backend
            if let url = Bundle.main.url(forResource: devModelName, withExtension: "usdz"),
               let data = try? Data(contentsOf: url) {
                glbData = data
            } else {
                errorMessage = "Dev model '\(devModelName).glb' not found in app bundle."
                showError = true
            }
            return
        }

        guard !strokeManager.strokes.isEmpty, canvasSize != .zero else { return }
        let svg = strokeManager.generateSVG(canvasSize: canvasSize)
        guard !svg.isEmpty else { return }

        isLoading = true
        glbData = nil

        Task {
            do {
                let data = try await APIClient().generateMesh(svgText: svg)
                await MainActor.run {
                    glbData = data
                    isLoading = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    showError = true
                    isLoading = false
                }
            }
        }
    }
}

private struct AppButton: View {
    let title: String
    var isActive: Bool = false
    var color: Color = Theme.buttonBlue
    var pressedColor: Color = Theme.buttonBluePressed
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundColor(Theme.textPrimary)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isPressed ? pressedColor : (isActive ? pressedColor : color))
                )
        }
        .buttonStyle(PressableButtonStyle(isPressed: $isPressed))
    }
}

private struct AppIconButton: View {
    let systemImage: String
    let action: () -> Void

    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body.weight(.semibold))
                .foregroundColor(Theme.textPrimary)
                .frame(width: 44, height: 44)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isPressed ? Theme.buttonBluePressed : Theme.buttonBlue)
                )
        }
        .buttonStyle(PressableButtonStyle(isPressed: $isPressed))
    }
}

private struct PressableButtonStyle: ButtonStyle {
    @Binding var isPressed: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onChange(of: configuration.isPressed) { _, pressed in
                isPressed = pressed
            }
    }
}

#Preview {
    ContentView()
}
