import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
// noneSkipLast: opaque RGB with no alpha channel, as App Store icons require.
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r, green: g, blue: b, alpha: a) }
func gradient(_ colors: [CGColor], _ locations: [CGFloat]) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

let goldLight = rgb(1.0, 0.89, 0.56)
let gold = rgb(0.86, 0.70, 0.26)
let goldDark = rgb(0.50, 0.36, 0.09)
let goldGradient = gradient([goldLight, gold, goldDark, gold], [0, 0.35, 0.75, 1])

// Background: near-black with a red glow top-right and a faint gold glow bottom-left.
ctx.setFillColor(rgb(0.03, 0.03, 0.04))
ctx.fill(CGRect(x: 0, y: 0, width: size, height: size))
ctx.drawRadialGradient(gradient([rgb(0.90, 0.12, 0.16, 0.55), rgb(0.90, 0.12, 0.16, 0)], [0, 1]),
                       startCenter: CGPoint(x: 860, y: 900), startRadius: 0, endCenter: CGPoint(x: 860, y: 900), endRadius: 720, options: [])
ctx.drawRadialGradient(gradient([rgb(0.86, 0.70, 0.26, 0.22), rgb(0.86, 0.70, 0.26, 0)], [0, 1]),
                       startCenter: CGPoint(x: 140, y: 120), startRadius: 0, endCenter: CGPoint(x: 140, y: 120), endRadius: 640, options: [])

// Mirror: oval gold frame around dark glass.
let center = CGPoint(x: 512, y: 512)
let outer = CGRect(x: center.x - 300, y: center.y - 385, width: 600, height: 770)
let inner = outer.insetBy(dx: 46, dy: 46)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -18), blur: 50, color: rgb(0, 0, 0, 0.7))
ctx.addEllipse(in: outer)
ctx.setFillColor(gold)
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addEllipse(in: outer)
ctx.addEllipse(in: inner)
ctx.clip(using: .evenOdd)
ctx.drawLinearGradient(goldGradient, start: CGPoint(x: outer.minX, y: outer.maxY), end: CGPoint(x: outer.maxX, y: outer.minY), options: [])
ctx.restoreGState()

// Glass with a soft diagonal reflection.
ctx.saveGState()
ctx.addEllipse(in: inner)
ctx.clip()
ctx.drawLinearGradient(gradient([rgb(0.13, 0.12, 0.14), rgb(0.03, 0.03, 0.035)], [0, 1]),
                       start: CGPoint(x: 512, y: inner.maxY), end: CGPoint(x: 512, y: inner.minY), options: [])
ctx.translateBy(x: 512, y: 512)
ctx.rotate(by: -.pi / 5)
ctx.setFillColor(rgb(1, 1, 1, 0.06))
ctx.fill(CGRect(x: -600, y: 120, width: 1200, height: 90))
ctx.setFillColor(rgb(1, 1, 1, 0.035))
ctx.fill(CGRect(x: -600, y: 240, width: 1200, height: 36))
ctx.restoreGState()

// Bold V monogram.
let v = CGMutablePath()
v.addLines(between: [
    CGPoint(x: 352, y: 712), CGPoint(x: 452, y: 712), CGPoint(x: 512, y: 478),
    CGPoint(x: 572, y: 712), CGPoint(x: 672, y: 712), CGPoint(x: 548, y: 318),
    CGPoint(x: 476, y: 318),
])
v.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: rgb(0, 0, 0, 0.8))
ctx.addPath(v)
ctx.setFillColor(gold)
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(v)
ctx.clip()
ctx.drawLinearGradient(goldGradient, start: CGPoint(x: 352, y: 712), end: CGPoint(x: 672, y: 318), options: [])
ctx.restoreGState()

// Sparkles on the glass.
func sparkle(at p: CGPoint, radius r: CGFloat, color: CGColor) {
    let path = CGMutablePath()
    let waist = r * 0.22
    path.move(to: CGPoint(x: p.x, y: p.y + r))
    path.addQuadCurve(to: CGPoint(x: p.x + r, y: p.y), control: CGPoint(x: p.x + waist, y: p.y + waist))
    path.addQuadCurve(to: CGPoint(x: p.x, y: p.y - r), control: CGPoint(x: p.x + waist, y: p.y - waist))
    path.addQuadCurve(to: CGPoint(x: p.x - r, y: p.y), control: CGPoint(x: p.x - waist, y: p.y - waist))
    path.addQuadCurve(to: CGPoint(x: p.x, y: p.y + r), control: CGPoint(x: p.x - waist, y: p.y + waist))
    ctx.addPath(path)
    ctx.setFillColor(color)
    ctx.fillPath()
}
sparkle(at: CGPoint(x: 616, y: 768), radius: 42, color: goldLight)
sparkle(at: CGPoint(x: 696, y: 660), radius: 18, color: rgb(1, 0.45, 0.4))

let image = ctx.makeImage()!
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(dest, image, nil)
CGImageDestinationFinalize(dest)
