import AppKit
import SwiftUI

struct AppIcon: View {
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 220).fill(LinearGradient(colors: [Color(red: 0.13, green: 0.25, blue: 0.28), Color(red: 0.04, green: 0.12, blue: 0.18)], startPoint: .topLeading, endPoint: .bottomTrailing))
            Circle().trim(from: 0.05, to: 0.87).stroke(Color(red: 0.38, green: 0.88, blue: 0.66), style: StrokeStyle(lineWidth: 55, lineCap: .round)).rotationEffect(.degrees(85)).padding(190)
            Path { p in
                p.move(to: CGPoint(x: 225, y: 535)); p.addLine(to: CGPoint(x: 385, y: 535)); p.addLine(to: CGPoint(x: 448, y: 405)); p.addLine(to: CGPoint(x: 540, y: 650)); p.addLine(to: CGPoint(x: 612, y: 490)); p.addLine(to: CGPoint(x: 805, y: 490))
            }.stroke(.white, style: StrokeStyle(lineWidth: 38, lineCap: .round, lineJoin: .round))
        }.frame(width: 1024, height: 1024)
    }
}
@main struct RenderIcon {
    @MainActor static func main() throws {
        _ = NSApplication.shared
        let root = URL(fileURLWithPath: CommandLine.arguments[1])
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for size in [16, 32, 128, 256, 512] {
            for scale in [1, 2] {
                let renderer = ImageRenderer(content: AppIcon().scaleEffect(Double(size)/1024, anchor: .topLeading).frame(width: CGFloat(size), height: CGFloat(size), alignment: .topLeading))
                renderer.scale = CGFloat(scale)
                guard let image = renderer.cgImage else { throw CocoaError(.fileWriteUnknown) }
                let bitmap = NSBitmapImageRep(cgImage: image)
                let name = "icon_\(size)x\(size)" + (scale == 2 ? "@2x" : "") + ".png"
                try bitmap.representation(using: .png, properties: [:])!.write(to: root.appendingPathComponent(name))
            }
        }
    }
}
