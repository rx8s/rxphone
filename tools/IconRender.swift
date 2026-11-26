import AppKit
import SwiftUI

// Renders RxPhone app icon concepts to 1024×1024 PNGs.
// Usage: swift tools/IconRender.swift <outdir> [variant] [style]
// Then flatten icon-light.png (no alpha) and copy into AppIcon.appiconset.
// variant: a | b | c   style: light | dark | tinted | all

let ink = Color(red: 0x18 / 255, green: 0x18 / 255, blue: 0x1B / 255)
let ink2 = Color(red: 0x3F / 255, green: 0x3F / 255, blue: 0x46 / 255)
let paper = Color(red: 0xFA / 255, green: 0xFA / 255, blue: 0xFA / 255)

enum Style: String { case light, dark, tinted }

/// Background: dark gradient for the default icon; transparent for dark and
/// tinted variants (iOS draws its own background behind those).
struct Background: View {
    let style: Style
    var body: some View {
        switch style {
        case .light:
            LinearGradient(colors: [ink2, ink], startPoint: .top, endPoint: .bottom)
        case .dark, .tinted:
            Color.clear
        }
    }
}

/// Mountain + sun inside a photo, used as a cutout on a filled card.
struct PhotoGlyph: View {
    let fill: Color
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            ZStack {
                Circle().fill(fill).frame(width: w * 0.2).position(x: w * 0.7, y: h * 0.3)
                Path { p in
                    p.move(to: CGPoint(x: 0, y: h))
                    p.addLine(to: CGPoint(x: w * 0.36, y: h * 0.42))
                    p.addLine(to: CGPoint(x: w * 0.58, y: h * 0.72))
                    p.addLine(to: CGPoint(x: w * 0.72, y: h * 0.56))
                    p.addLine(to: CGPoint(x: w, y: h))
                    p.closeSubpath()
                }
                .fill(fill)
            }
        }
    }
}

struct Sparkle: Shape {
    func path(in r: CGRect) -> Path {
        let c = CGPoint(x: r.midX, y: r.midY), a = r.width / 2, k = a * 0.18
        var p = Path()
        p.move(to: CGPoint(x: c.x, y: c.y - a))
        p.addQuadCurve(to: CGPoint(x: c.x + a, y: c.y), control: CGPoint(x: c.x + k, y: c.y - k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + a), control: CGPoint(x: c.x + k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x - a, y: c.y), control: CGPoint(x: c.x - k, y: c.y + k))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - a), control: CGPoint(x: c.x - k, y: c.y - k))
        return p
    }
}

/// A: two stacked photo cards with a sparkle — "manage + clean up".
struct ConceptA: View {
    let fg: Color
    var body: some View {
        ZStack {
            // Back card, with the front card's footprint (plus a gap) cut out
            // so it never shows through the front card's photo cutout.
            ZStack {
                RoundedRectangle(cornerRadius: 70, style: .continuous)
                    .stroke(fg.opacity(0.45), lineWidth: 36)
                    .frame(width: 470, height: 470)
                    .rotationEffect(.degrees(-10))
                    .offset(x: -50, y: -40)
                RoundedRectangle(cornerRadius: 96, style: .continuous)
                    .fill(Color.black)
                    .frame(width: 530, height: 530)
                    .rotationEffect(.degrees(6))
                    .offset(x: 40, y: 50)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            RoundedRectangle(cornerRadius: 70, style: .continuous)
                .fill(fg)
                .frame(width: 470, height: 470)
                .overlay(
                    PhotoGlyph(fill: Color.black)
                        .frame(width: 330, height: 250)
                        .offset(y: 30)
                        .blendMode(.destinationOut)
                )
                .compositingGroup()
                .rotationEffect(.degrees(6))
                .offset(x: 40, y: 50)
            Sparkle().fill(fg).frame(width: 170, height: 170).offset(x: 290, y: -300)
        }
    }
}

/// B: a 3×3 grid of tiles, some selected with a tick — "select and clean".
struct ConceptB: View {
    let fg: Color
    var body: some View {
        let selected: Set<Int> = [0, 1, 4, 5, 8]
        VStack(spacing: 34) {
            ForEach(0..<3) { row in
                HStack(spacing: 34) {
                    ForEach(0..<3) { col in
                        let i = row * 3 + col
                        RoundedRectangle(cornerRadius: 42, style: .continuous)
                            .fill(fg.opacity(selected.contains(i) ? 1 : 0.28))
                            .frame(width: 190, height: 190)
                    }
                }
            }
        }
        .overlay(alignment: .bottomTrailing) {
            Circle()
                .fill(fg)
                .frame(width: 250, height: 250)
                .overlay(
                    Path { p in
                        p.move(to: CGPoint(x: 70, y: 128))
                        p.addLine(to: CGPoint(x: 110, y: 170))
                        p.addLine(to: CGPoint(x: 182, y: 90))
                    }
                    .stroke(Color.black, style: StrokeStyle(lineWidth: 30, lineCap: .round, lineJoin: .round))
                    .blendMode(.destinationOut)
                )
                .compositingGroup()
                .padding(10)
                .background(Circle().fill(Color.black).blendMode(.destinationOut))
                .offset(x: 70, y: 70)
        }
        .compositingGroup()
    }
}

/// C: one photo frame with a play badge — "photos + videos".
struct ConceptC: View {
    let fg: Color
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 90, style: .continuous)
                .fill(fg)
                .frame(width: 600, height: 520)
                .overlay(
                    PhotoGlyph(fill: Color.black)
                        .frame(width: 440, height: 300)
                        .offset(y: 40)
                        .blendMode(.destinationOut)
                )
                .compositingGroup()
            Circle()
                .fill(fg)
                .frame(width: 260, height: 260)
                .overlay(
                    Path { p in
                        p.move(to: CGPoint(x: 100, y: 72))
                        p.addLine(to: CGPoint(x: 196, y: 130))
                        p.addLine(to: CGPoint(x: 100, y: 188))
                        p.closeSubpath()
                    }
                    .fill(Color.black)
                    .blendMode(.destinationOut)
                )
                .compositingGroup()
                .padding(24)
                .background(Circle().fill(Color.black).blendMode(.destinationOut))
                .offset(x: 230, y: 210)
        }
        .compositingGroup()
    }
}

struct Icon: View {
    let variant: String
    let style: Style
    var body: some View {
        let fg: Color = switch style {
        case .light: paper
        case .dark: paper
        case .tinted: .white
        }
        ZStack {
            Background(style: style)
            Group {
                switch variant {
                case "a": ConceptA(fg: fg)
                case "b": ConceptB(fg: fg)
                default: ConceptC(fg: fg)
                }
            }
            .compositingGroup()
        }
        .frame(width: 1024, height: 1024)
    }
}

@MainActor
func render(_ view: some View, to url: URL) {
    let renderer = ImageRenderer(content: view)
    renderer.scale = 1
    guard let image = renderer.nsImage,
          let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("render failed: \(url.lastPathComponent)")
    }
    try! png.write(to: url)
    print("wrote \(url.path)")
}

/// Preview sheet: each concept masked to the iOS icon shape, light and dark.
struct Sheet: View {
    var body: some View {
        VStack(spacing: 40) {
            ForEach(["a", "b", "c"], id: \.self) { v in
                HStack(spacing: 40) {
                    Text(v.uppercased()).font(.system(size: 120, weight: .bold)).frame(width: 140)
                    Icon(variant: v, style: .light)
                        .scaleEffect(0.35).frame(width: 360, height: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 80, style: .continuous))
                    ZStack {
                        Color(white: 0.11)
                        Icon(variant: v, style: .dark).scaleEffect(0.35)
                    }
                    .frame(width: 360, height: 360)
                    .clipShape(RoundedRectangle(cornerRadius: 80, style: .continuous))
                }
            }
        }
        .padding(60)
        .background(Color(white: 0.93))
    }
}

let args = CommandLine.arguments
let out = URL(fileURLWithPath: args.count > 1 ? args[1] : ".")
MainActor.assumeIsolated {
    if args.count > 3 {
        let variant = args[2]
        let styles: [Style] = args[3] == "all" ? [.light, .dark, .tinted] : [Style(rawValue: args[3])!]
        for s in styles {
            render(Icon(variant: variant, style: s), to: out.appendingPathComponent("icon-\(s.rawValue).png"))
        }
    } else {
        render(Sheet(), to: out.appendingPathComponent("concepts.png"))
    }
}
