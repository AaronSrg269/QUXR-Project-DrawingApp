import SwiftUI

struct ContentView: View {
    @StateObject private var strokeManager = StrokeManager()
    @State private var mode: DrawingMode = .pen
    @State private var canvasSize: CGSize = .zero
    @State private var glbData: Data?
    @State private var isLoading = false
    @State private var errorMessage = ""
    @State private var showError = false
    @State private var isFinished = false
    @State private var drawingAspectRatio: CGFloat = 1.0

    // DEV: set to true to load bundled test model instead of calling the backend
    private let useDevModel = false
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
                GeometryReader { geometry in
                    HStack(spacing: panelGap) {
                        DrawingCanvasView(strokeManager: strokeManager, mode: $mode, isLocked: isFinished)
                            .padding(panelPadding)
                            .frame(width: isFinished ? geometry.size.width * 0.42 : geometry.size.width * 0.50)
                            .frame(maxHeight: .infinity)
                            .aspectRatio(drawingAspectRatio, contentMode: .fit)
                            .background(Color.white)
                            .overlay(
                                RoundedRectangle(cornerRadius: panelCornerRadius)
                                    .stroke(Theme.accent.opacity(0.80), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius))

                        ModelDisplayView(glbData: glbData, isLoading: isLoading)
                            .padding(panelPadding)
                            .frame(width: isFinished ? geometry.size.width * 0.58 : geometry.size.width * 0.50)
                            .frame(maxHeight: .infinity)
                            .background(Theme.background.opacity(0.92))
                            .overlay(
                                RoundedRectangle(cornerRadius: panelCornerRadius)
                                    .stroke(Theme.accent.opacity(0.80), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: panelCornerRadius))
                    }
                    .frame(maxHeight: .infinity)
                    .animation(.easeInOut(duration: 0.55), value: isFinished)
                    .onChange(of: geometry.size, initial: true) { _, newSize in
                        guard newSize.width > 50, newSize.height > 50 else { return }
                        let canvasW = newSize.width * 0.50 - 2 * panelPadding
                        let canvasH = newSize.height - 2 * panelPadding
                        if !isFinished {
                            canvasSize = CGSize(width: canvasW, height: canvasH)
                            drawingAspectRatio = canvasW / canvasH
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                GeometryReader { geo in
                    HStack(spacing: 0) {
                        HStack(spacing: 24) {
                            if isFinished {
                                AppButton(title: "Done") {
                                    isFinished = false
                                    glbData = nil
                                    strokeManager.clear()
                                }
                            } else {
                                AppIconButton(systemImage: "arrow.uturn.backward") {
                                    strokeManager.undo()
                                }
                                .disabled(!strokeManager.canUndo)

                                AppIconButton(systemImage: "arrow.uturn.forward") {
                                    strokeManager.redo()
                                }
                                .disabled(!strokeManager.canRedo)

                                AppButton(title: "Clear") {
                                    strokeManager.clear()
                                }
                                .disabled(strokeManager.strokes.isEmpty)

                                AppButton(
                                    title: isLoading ? "Generating…" : "Generate Instance",
                                    action: { generateModel() }
                                )
                                .disabled(isLoading || strokeManager.strokes.isEmpty)
                            }
                        }
                        .frame(width: isFinished ? geo.size.width * 0.42 : geo.size.width * 0.50)

                        if !isFinished {
                            Spacer()

                            AppButton(
                                title: "Finish",
                                color: Theme.buttonPink,
                                pressedColor: Theme.buttonPinkPressed,
                                action: {
                                    isFinished = true
                                    if glbData == nil {
                                        generateModel()
                                    }
                                }
                            )
                            .disabled(isLoading || strokeManager.strokes.isEmpty)
                        }
                    }
                }
                .frame(height: 50)
                .padding(.vertical, 4)
            }
            .padding(outerPadding)
        }
        .alert("Generation failed", isPresented: $showError) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(errorMessage)
        }
    }

    @MainActor private func generateModel() {
        guard !isLoading else { return }

        if useDevModel {
            // DEV: loads bundled test file instead of calling backend
            if let url = Bundle.main.url(forResource: devModelName, withExtension: "usdz"),
               let data = try? Data(contentsOf: url) {
                glbData = data
            } else {
                errorMessage = "Dev model '\(devModelName).usdz' not found in app bundle."
                showError = true
            }
            return
        }

        guard !strokeManager.strokes.isEmpty, canvasSize != .zero else { return }
        let svg = strokeManager.generateSVG(canvasSize: canvasSize)
        guard !svg.isEmpty else { return }

        isLoading = true

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
