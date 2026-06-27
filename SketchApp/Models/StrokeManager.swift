import Foundation
import SwiftUI
import Combine

class StrokeManager: ObservableObject {
    @Published var strokes: [[CGPoint]] = []
    @Published var undoStack: [[CGPoint]] = []

    var canUndo: Bool { !strokes.isEmpty }
    var canRedo: Bool { !undoStack.isEmpty }

    func commitStroke(_ points: [CGPoint]) {
        guard points.count >= 2 else { return }
        strokes.append(points)
        undoStack.removeAll()
    }

    func undo() {
        guard let stroke = strokes.popLast() else { return }
        undoStack.append(stroke)
    }

    func redo() {
        guard let stroke = undoStack.popLast() else { return }
        strokes.append(stroke)
    }

    func clear() {
        strokes.removeAll()
        undoStack.removeAll()
    }

    // TODO: re-enable erase mode
    // func eraseOverlapping(eraserPath: [CGPoint], radius: CGFloat) {
    //     guard !eraserPath.isEmpty else { return }
    //     let radiusSquared = radius * radius
    //     strokes.removeAll { stroke in
    //         stroke.contains { point in
    //             eraserPath.contains { eraserPoint in
    //                 let dx = point.x - eraserPoint.x
    //                 let dy = point.y - eraserPoint.y
    //                 return (dx * dx + dy * dy) <= radiusSquared
    //             }
    //         }
    //     }
    // }

    func generateSVG(canvasSize: CGSize) -> String {
        guard !strokes.isEmpty else { return "" }
        let w = Int(canvasSize.width)
        let h = Int(canvasSize.height)
        var lines = [
            "<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(w) \(h)\" width=\"\(w)\" height=\"\(h)\">"
        ]
        for path in strokes {
            guard path.count >= 2 else { continue }
            var d = "M \(Int(path[0].x)) \(Int(path[0].y))"
            for pt in path.dropFirst() {
                d += " L \(Int(pt.x)) \(Int(pt.y))"
            }
            lines.append("  <path d=\"\(d)\" fill=\"none\" stroke=\"black\" stroke-width=\"5\" stroke-linecap=\"round\" stroke-linejoin=\"round\"/>")
        }
        lines.append("</svg>")
        return lines.joined(separator: "\n")
    }
}
