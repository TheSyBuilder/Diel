import CoreGraphics
import Foundation

// Run from the repository root: swift scripts/generate-diel-symbols.swift
// Uses Apple's documented custom symbol format and native path outline tooling.
// Draw guide syntax was verified against an SF Symbols 27 export of line.diagonal.
// Fractions are distances around the filled path, paired across its stroke.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
  .appendingPathComponent("Diel/Assets.xcassets")
func path(_ body: (CGMutablePath) -> Void) -> CGPath {
  let p = CGMutablePath()
  body(p)
  return p
}
func line(_ points: [CGPoint]) -> CGPath {
  path { p in p.addLines(between: points) }
}
func svg(_ p: CGPath) -> String {
  var s = ""
  func n(_ v: CGFloat) -> String { String(format: "%.7f", Double(v)) }
  p.applyWithBlock { ptr in
    let e = ptr.pointee
    func pt(_ i: Int) -> String { "\(n(e.points[i].x)) \(n(e.points[i].y))" }
    switch e.type {
    case .moveToPoint: s += "M\(pt(0))"
    case .addLineToPoint: s += "L\(pt(0))"
    case .addQuadCurveToPoint: s += "Q\(pt(0)) \(pt(1))"
    case .addCurveToPoint: s += "C\(pt(0)) \(pt(1)) \(pt(2))"
    case .closeSubpath: s += "Z"
    @unknown default: fatalError()
    }
  }
  return s
}
/// Measure each outline segment to pair opposite edges for native Draw clipping.
func drawGuides(_ p: CGPath, curved: Bool) -> String {
  var start = CGPoint.zero
  var current = CGPoint.zero
  var lengths: [Double] = []
  func distance(_ a: CGPoint, _ b: CGPoint) -> Double { hypot(a.x - b.x, a.y - b.y) }
  p.applyWithBlock { pointer in
    let e = pointer.pointee
    switch e.type {
    case .moveToPoint:
      start = e.points[0]
      current = start
    case .addLineToPoint:
      lengths.append(distance(current, e.points[0]))
      current = e.points[0]
    case .addCurveToPoint:
      let a = current
      let b = e.points[0]
      let c = e.points[1]
      let d = e.points[2]
      var previous = a
      var length = 0.0
      for step in 1...1024 {
        let t = Double(step) / 1024
        let u = 1 - t
        let q = CGPoint(
          x: u * u * u * a.x + 3 * u * u * t * b.x + 3 * u * t * t * c.x + t * t * t * d.x,
          y: u * u * u * a.y + 3 * u * u * t * b.y + 3 * u * t * t * c.y + t * t * t * d.y)
        length += distance(previous, q)
        previous = q
      }
      lengths.append(length)
      current = d
    case .closeSubpath:
      let length = distance(current, start)
      if length > 0.000001 { lengths.append(length) }
      current = start
    default: fatalError("Unexpected outline segment")
    }
  }
  // CoreGraphics produces edge, two cap curves, reverse edge, two cap curves.
  precondition(lengths.count == 6)
  let total = lengths.reduce(0, +)
  let firstEnd = lengths[0] / total
  let reverseStart = (lengths[0] + lengths[1] + lengths[2]) / total
  let reverseEnd = (lengths[0] + lengths[1] + lengths[2] + lengths[3]) / total
  func n(_ d: Double) -> String { String(format: "%.8f", d) }
  let middle =
    curved
    ? " 0 0.5 \(n(firstEnd/2)) \(n((reverseStart+reverseEnd)/2))" : ""
  return "0 0 0 0 \(n(reverseEnd))\(middle) 0 1 \(n(firstEnd)) \(n(reverseStart))"
}

func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x, y: y - 64) }
struct Part {
  let path: CGPath
  var fill = false
}
let designs: [(String, [Part])] = [
  (
    "readiness",
    [
      Part(
        path: path { p in
          p.move(to: point(14, 50))
          p.addCurve(to: point(50, 50), control1: point(14, 24), control2: point(50, 24))
        }),
      Part(path: line([point(4, 50), point(60, 50)])),
      Part(
        path: CGPath(ellipseIn: CGRect(x: 28, y: 12 - 64, width: 8, height: 8), transform: nil),
        fill: true),
    ]
  ),
  (
    "load",
    [
      Part(path: line([point(14, 51), point(14, 42)])),
      Part(path: line([point(32, 51), point(32, 28)])),
      Part(path: line([point(50, 51), point(50, 9)])),
    ]
  ),
  (
    "sleep",
    [
      Part(
        path: path { p in
          p.move(to: point(40, 7))
          p.addCurve(to: point(35, 58), control1: point(3, 8), control2: point(5, 58))
          p.addCurve(to: point(61, 35), control1: point(49, 58), control2: point(59, 48))
          p.addCurve(to: point(40, 7), control1: point(39, 47), control2: point(25, 29))
          p.closeSubpath()
        }),
      Part(
        path: CGPath(ellipseIn: CGRect(x: 52, y: 9 - 64, width: 6, height: 6), transform: nil),
        fill: true),
    ]
  ),
  (
    "hrv",
    [
      Part(
        path: path { p in
          p.move(to: point(32, 56))
          p.addLine(to: point(9, 33))
          p.addCurve(to: point(32, 12), control1: point(-8, 14), control2: point(15, -3))
          p.addCurve(to: point(55, 33), control1: point(49, -3), control2: point(72, 14))
          p.closeSubpath()
        }),
      Part(
        path: line([
          point(15, 31), point(23, 31), point(28, 23), point(34, 39), point(39, 30), point(49, 30),
        ])),
    ]
  ),
  (
    "stages",
    [
      Part(
        path: line([
          point(5, 18), point(18, 18), point(18, 31), point(29, 31), point(29, 24), point(40, 24),
          point(40, 45), point(58, 45),
        ]))
    ]
  ),
  (
    "battery",
    [
      Part(
        path: CGPath(
          roundedRect: CGRect(x: 18, y: 10 - 64, width: 28, height: 48), cornerWidth: 7,
          cornerHeight: 7, transform: nil)),
      Part(path: line([point(27, 4), point(37, 4)])),
      Part(path: line([point(25, 35), point(39, 35)])),
      Part(path: line([point(25, 45), point(39, 45)])),
    ]
  ),
  (
    "breathing",
    [0, 16].map { offset in
      Part(
        path: path { p in
          let dy = CGFloat(offset)
          p.move(to: point(6, 23 + dy))
          p.addCurve(
            to: point(25, 19 + dy), control1: point(15, 23 + dy), control2: point(15, 13 + dy))
          p.addCurve(
            to: point(42, 20 + dy), control1: point(33, 25 + dy), control2: point(34, 26 + dy))
          p.addCurve(
            to: point(59, 23 + dy), control1: point(50, 14 + dy), control2: point(52, 17 + dy))
        })
    }
  ),
]
let weights: [(String, CGFloat)] = [
  ("Ultralight", 1.6), ("Thin", 2), ("Light", 2.8), ("Regular", 4.2), ("Medium", 4.8),
  ("Semibold", 5.6), ("Bold", 6.4), ("Heavy", 7.2), ("Black", 8),
]
let scales: [(String, CGFloat)] = [("S", 0.783), ("M", 1), ("L", 1.29)]
for (name, parts) in designs {
  let dir = root.appendingPathComponent("diel.\(name).symbolset")
  try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
  var css =
    ".defaults {-sfsymbols-variable-value-mode:color;-sfsymbols-draw-reverses-motion-groups:false;}\n"
  for i in parts.indices {
    let threshold = name == "load" ? ";-sfsymbols-variable-threshold:\(Double(i)/3)" : ""
    let motion =
      name == "readiness" ? ";-sfsymbols-motion-group:\(i == 0 ? 1 : i == 1 ? 0 : 2)" : ""
    css += ".monochrome-\(i) {fill:#000000\(threshold)\(motion);}\n"
    css += ".hierarchical-\(i):primary {fill:#000000\(threshold)\(motion);}\n"
  }
  var guides = ""
  var groups = ""
  for (si, (scale, factor)) in scales.enumerated() {
    let y = CGFloat(300 + si * 220)
    guides +=
      "<line id=\"Baseline-\(scale)\" x1=\"0\" y1=\"\(y)\" x2=\"1800\" y2=\"\(y)\"/><line id=\"Capline-\(scale)\" x1=\"0\" y1=\"\(y-64*factor)\" x2=\"1800\" y2=\"\(y-64*factor)\"/>"
    for (wi, (weight, width)) in weights.enumerated() {
      let x = CGFloat(100 + wi * 180)
      let variant = "\(weight)-\(scale)"
      guides +=
        "<line id=\"left-margin-\(variant)\" x1=\"\(x)\" y1=\"\(y-90)\" x2=\"\(x)\" y2=\"\(y+20)\"/><line id=\"right-margin-\(variant)\" x1=\"\(x+64*factor)\" y1=\"\(y-90)\" x2=\"\(x+64*factor)\" y2=\"\(y+20)\"/>"
      groups += "<g id=\"\(variant)\" transform=\"matrix(1 0 0 1 \(x) \(y))\">\n"
      for (i, part) in parts.enumerated() {
        let outlined =
          part.fill
          ? part.path
          : part.path.copy(
            strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 10)
        var t = CGAffineTransform(scaleX: factor, y: factor)
        let scaled = outlined.copy(using: &t)!
        let draw =
          name == "readiness" && i < 2
          ? " data-clipstroke-keyframes=\"\(drawGuides(outlined, curved: i == 0))\"" : ""
        groups +=
          "<path class=\"monochrome-\(i) hierarchical-\(i):primary\" d=\"\(svg(scaled))\"\(draw)/>\n"
      }
      groups += "</g>\n"
    }
  }
  let doc = """
    <?xml version="1.0" encoding="UTF-8"?>
    <svg xmlns="http://www.w3.org/2000/svg" width="1800" height="900" viewBox="0 0 1800 900" version="1.1">
    <style>\(css)</style>
    <g id="Notes"><text id="template-version">Template v.7.0</text></g>
    <g id="Guides">\(guides)</g>
    <g id="Symbols">\(groups)</g>
    </svg>
    """
  try doc.write(
    to: dir.appendingPathComponent("diel.\(name).svg"), atomically: true, encoding: .utf8)
  let contents = """
    {"info":{"author":"xcode","version":1},"symbols":[{"filename":"diel.\(name).svg","idiom":"universal"}]}
    """
  try contents.write(
    to: dir.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}
