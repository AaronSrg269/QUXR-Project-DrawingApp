# QU-XR iPad Drawing App — Project Context Document
> For use by Windsurf AI and developer reference. Last updated: June 2025.

---

## Project Overview

This is a **native iPad drawing app** built in Swift/SwiftUI, developed as part of a university XR research project at TU Berlin. The app serves as the **tablet condition** in a study comparing VR-based and tablet-based 3D sketch-to-mesh interfaces.

The user draws a 2D sketch with Apple Pencil or finger on the iPad. The sketch is transmitted as SVG to a backend API (MeshPad) which returns a 3D mesh in GLB format. The mesh is then displayed interactively in the app.

A reference Python/PyQt6 desktop app exists and serves as a reference for API behavior and core features. Strict UI/UX parity with that app is not required; the iPad app follows its own native SwiftUI design while matching the same backend API and sketch-to-mesh workflow.

---

## Repository & Team Context

- **This app:** Native Swift/SwiftUI iPad app (Aaron's responsibility)
- **Reference desktop app:** Python/PyQt6, by teammate Christian — same API, same concept
- **VR condition app:** Unity/C# on Meta Quest, by another teammate — feature parity target
- **Backend:** MeshPad Gradio API server, hosted at TU Berlin, set up by teammate
- **Network config:** Managed by teammate Tobias
- **SVG/stylus work:** Teammate Niki

---

## Backend API

This is everything needed to call the backend. Do not deviate from this.

**Endpoint:**
```
POST http://ln-dsk-0hxrv.qu.tu-berlin.de/api_model/generate
```

**Request:**
```json
{
  "svg_text": "<svg xmlns=...>...</svg>"
}
```
- Content-Type: `application/json`
- Accept: `application/octet-stream`

**Response:**
- Raw binary GLB bytes (3D mesh in GLTF Binary format)
- Successful status code: `200`
- Timeout: set to **90 seconds minimum** — the model can be slow

**Important — iOS App Transport Security:**
The server uses HTTP, not HTTPS. iOS blocks HTTP by default. You MUST add an `Info.plist` exception:
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSExceptionDomains</key>
    <dict>
        <key>ln-dsk-0hxrv.qu.tu-berlin.de</key>
        <dict>
            <key>NSExceptionAllowsInsecureHTTPLoads</key>
            <true/>
        </dict>
    </dict>
</dict>
```

---

## App Architecture

Four components. Keep them cleanly separated.

### 1. `DrawingCanvasView`
- `UIViewRepresentable` wrapping a `UIView`
- Handles raw touch input including Apple Pencil
- Renders strokes via `drawRect` or `setNeedsDisplay`
- Communicates stroke events up to `StrokeManager`
- Displays the last committed stroke in a distinct highlight color (e.g. red/coral)
- All previous strokes rendered in standard color (e.g. dark blue/black)
- Erase mode: renders eraser path as a wide semi-transparent stroke preview

### 2. `StrokeManager` (ObservableObject)
- Single source of truth for all stroke state
- `var strokes: [[CGPoint]]` — all committed strokes
- `var undoStack: [[CGPoint]]` — strokes removed by undo, available for redo
- `func commitStroke(_ points: [CGPoint])` — adds stroke, clears redo stack
- `func undo()` — pops last stroke to undoStack
- `func redo()` — pops from undoStack back to strokes
- `func clear()` — clears everything
- `func eraseOverlapping(eraserPath: [CGPoint], radius: CGFloat)` — removes strokes whose points fall within radius of any eraser point (whole-stroke removal, matching Python behavior)
- `func generateSVG(canvasSize: CGSize) -> String` — builds SVG string from strokes

### 3. `APIClient`
- Simple struct with one async function
- `func generateMesh(svgText: String) async throws -> Data`
- Uses `URLSession` with async/await
- POST to endpoint above
- Sets timeout to 90 seconds via `URLSessionConfiguration`
- Returns raw `Data` (GLB bytes) on success
- Throws descriptive errors on failure

### 4. `ModelDisplayView`
- Takes GLB `Data` as input
- Writes bytes to a **temporary file** with `.glb` extension (RealityKit requires this)
- Loads using `RealityKit` — `ModelEntity.loadModel(contentsOf: url)`
- Displays in an `ARView` configured for non-AR use (`.nonAR` world tracking) or a `RealityView` if targeting iOS 18+
- Camera controls: allow orbit/pan/zoom

---

## SVG Generation

Matches the Python reference implementation exactly. Build the SVG from `strokes: [[CGPoint]]`:

```swift
func generateSVG(canvasSize: CGSize) -> String {
    guard !strokes.isEmpty else { return "" }
    let w = Int(canvasSize.width)
    let h = Int(canvasSize.height)
    var lines = ["<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 \(w) \(h)\" width=\"\(w)\" height=\"\(h)\">"]
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
```

---

## UI Layout

**Orientation:** Landscape only (lock to landscape in project settings)

**Layout:** Horizontal split — drawing canvas left, 3D model viewer right. Mirrors the Python desktop app and keeps sketch + result visible simultaneously.

**Toolbar (top or bottom):**
- Pen Mode button (active state: highlighted)
- Erase Mode button (active state: highlighted)
- Undo button (disabled when nothing to undo)
- Redo button (disabled when nothing to redo)
- Clear button
- Generate 3D Model button (shows loading state during API call)

**States of the Generate button:**
- Default: enabled, "Generate 3D Model"
- Loading: disabled, "Generating..." with activity indicator
- Re-enabled on success or error

**Error handling:** Show an alert on API error with the error message.

---

## Required Features (Parity with Python Reference App)

| Feature | Python App | iPad App |
|---|---|---|
| Freehand drawing | ✅ | ✅ |
| Pen / Erase mode toggle | ✅ | ✅ |
| Whole-stroke eraser | ✅ | ✅ |
| Clear canvas | ✅ | ✅ |
| SVG generation | ✅ | ✅ |
| POST SVG to API | ✅ | ✅ |
| Loading state during generation | ✅ | ✅ |
| Display GLB result | ✅ (via web) | ✅ (via RealityKit) |
| Undo / Redo | ❌ | ✅ |
| Last stroke highlight color | ❌ | ✅ |
| Apple Pencil support | ❌ | ✅ |

---

## Known Technical Gotchas

1. **App Transport Security (HTTP blocker):** Must add Info.plist exception for the server domain. Without this, all API calls will silently fail.

2. **RealityKit GLB loading:** RealityKit cannot load GLB from raw `Data` directly. You must write the bytes to a temp file with a `.glb` extension first, then load from that URL:
    ```swift
    let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent("model.glb")
    try data.write(to: tempURL)
    let entity = try await ModelEntity.load(contentsOf: tempURL)
    ```

3. **API timeout:** Default URLSession timeout is 60 seconds. The MeshPad model can take longer. Always configure a custom timeout of at least 90 seconds.

4. **Erase behavior:** Eraser removes entire strokes (not partial segments), matching the Python app. A stroke is removed if any of its points falls within the eraser radius of any eraser path point.

5. **Redo stack clearing:** When a new stroke is committed, the redo stack must be cleared. Standard undo/redo behavior.

---

## Tech Stack

| Component | Technology |
|---|---|
| Language | Swift 5.9+ |
| UI Framework | SwiftUI |
| Drawing Canvas | UIViewRepresentable + UIKit UIView |
| 3D Display | RealityKit |
| Networking | URLSession (async/await) |
| IDE | Xcode (build/run) + Windsurf (code editing) |
| Target | iPadOS 17+ |
| Device | Fresh iPad provided by university supervisors |
| AI Coding Assistant | Windsurf Premium |

---

## Development Workflow

- Write and edit Swift code in **Windsurf**
- Build and deploy to iPad via USB in **Xcode**
- Both can have the project folder open simultaneously
- Target device connected via USB, Developer Mode enabled on iPad

## File Structure (recommended)
```
QU-XR-iPad-App/
├── QU_XR_iPad_App.xcodeproj
└── QU-XR-iPad-App/
    ├── App/
    │   └── QU_XR_iPad_AppApp.swift
    ├── Views/
    │   ├── ContentView.swift          ← root split layout
    │   ├── DrawingCanvasView.swift    ← UIViewRepresentable canvas
    │   └── ModelDisplayView.swift    ← RealityKit GLB viewer
    ├── Models/
    │   └── StrokeManager.swift       ← ObservableObject, all stroke state
    ├── Networking/
    │   └── APIClient.swift           ← URLSession API call
    └── Info.plist                    ← HTTP exception lives here
```

---

## What is MeshPad (Backend Context)

MeshPad is a research system from TU Munich that generates 3D triangle meshes from 2D sketch input. It uses a large Transformer model. The Gradio API wraps the model and exposes the `/api_model/generate` endpoint. Input is an SVG sketch string. Output is a GLB binary mesh. Generation takes a few seconds to up to ~90 seconds depending on complexity. The server must be manually started by a teammate before the app can generate meshes.

---

*Document maintained by Aaron. Update as the project evolves.*
