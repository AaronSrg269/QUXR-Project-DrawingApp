import SwiftUI
import UIKit

enum DrawingMode {
    case pen
    case erase
}

struct DrawingCanvasView: UIViewRepresentable {
    @ObservedObject var strokeManager: StrokeManager
    @Binding var mode: DrawingMode

    func makeUIView(context: Context) -> CanvasView {
        let view = CanvasView()
        view.delegate = context.coordinator
        view.mode = mode
        return view
    }

    func updateUIView(_ uiView: CanvasView, context: Context) {
        uiView.mode = mode
        uiView.strokes = strokeManager.strokes
        uiView.setNeedsDisplay()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(strokeManager: strokeManager)
    }

    final class Coordinator: NSObject, CanvasViewDelegate {
        let strokeManager: StrokeManager

        init(strokeManager: StrokeManager) {
            self.strokeManager = strokeManager
        }

        func canvasView(_ canvasView: CanvasView, didFinishStroke points: [CGPoint]) {
            strokeManager.commitStroke(points)
        }

        // TODO: re-enable erase mode
        // func canvasView(_ canvasView: CanvasView, didFinishEraser points: [CGPoint]) {
        //     strokeManager.eraseOverlapping(eraserPath: points, radius: 20)
        // }
    }
}

protocol CanvasViewDelegate: AnyObject {
    func canvasView(_ canvasView: CanvasView, didFinishStroke points: [CGPoint])
    // TODO: re-enable erase mode
    // func canvasView(_ canvasView: CanvasView, didFinishEraser points: [CGPoint])
}

final class CanvasView: UIView {
    weak var delegate: CanvasViewDelegate?
    var mode: DrawingMode = .pen
    var strokes: [[CGPoint]] = []

    private var currentStroke: [CGPoint] = []
    private var currentEraserPath: [CGPoint] = []
    private var activeTouch: UITouch?

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func draw(_ rect: CGRect) {
        let committedColor = UIColor(red: 0, green: 0, blue: 0, alpha: 1.0)       // Theme.strokeCommitted #000000
        let currentColor   = UIColor(red: 0.922, green: 0.180, blue: 0.200, alpha: 1.0) // Theme.strokeCurrent  #EB2E33

        for stroke in strokes {
            guard stroke.count >= 2 else { continue }
            drawStroke(stroke, color: committedColor, lineWidth: 4)
        }

        if currentStroke.count >= 2 {
            drawStroke(currentStroke, color: currentColor, lineWidth: 4)
        }

        // TODO: re-enable erase mode
        // if currentEraserPath.count >= 2 {
        //     let path = UIBezierPath()
        //     for (i, point) in currentEraserPath.enumerated() {
        //         if i == 0 {
        //             path.move(to: point)
        //         } else {
        //             path.addLine(to: point)
        //         }
        //     }
        //     path.lineWidth = 40
        //     path.lineCapStyle = .round
        //     path.lineJoinStyle = .round
        //     UIColor.lightGray.withAlphaComponent(0.4).setStroke()
        //     path.stroke()
        // }
    }

    private func drawStroke(_ points: [CGPoint], color: UIColor, lineWidth: CGFloat) {
        let path = UIBezierPath()
        for (i, point) in points.enumerated() {
            if i == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.lineWidth = lineWidth
        path.lineCapStyle = .round
        path.lineJoinStyle = .round
        color.setStroke()
        path.stroke()
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard activeTouch == nil, let touch = touches.first else { return }
        activeTouch = touch
        let point = touch.location(in: self)
        if mode == .pen {
            currentStroke = [point]
        }
        // TODO: re-enable erase mode
        // else {
        //     currentEraserPath = [point]
        // }
        setNeedsDisplay()
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        let point = touch.location(in: self)
        if mode == .pen {
            currentStroke.append(point)
        }
        // TODO: re-enable erase mode
        // else {
        //     currentEraserPath.append(point)
        // }
        setNeedsDisplay()
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let touch = activeTouch, touches.contains(touch) else { return }
        activeTouch = nil
        if mode == .pen {
            if currentStroke.count >= 2 {
                delegate?.canvasView(self, didFinishStroke: currentStroke)
            }
            currentStroke.removeAll()
        }
        // TODO: re-enable erase mode
        // else {
        //     if currentEraserPath.count >= 2 {
        //         delegate?.canvasView(self, didFinishEraser: currentEraserPath)
        //     }
        //     currentEraserPath.removeAll()
        // }
        setNeedsDisplay()
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        activeTouch = nil
        currentStroke.removeAll()
        currentEraserPath.removeAll()
        setNeedsDisplay()
    }
}
