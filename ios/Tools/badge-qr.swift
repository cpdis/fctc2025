// Badge a setup-QR image with a centered initial and a name caption, then
// verify the result still decodes via the Vision framework.
//
//   swift ios/Tools/badge-qr.swift in.bmp out.png A Aaron
//
// The badge covers ~3% of the modules against the code's 15% level-M error
// correction budget; the verification step keeps that honest.
import AppKit
import Vision

let args = CommandLine.arguments
guard args.count == 5 else { fatalError("usage: badge-qr in-image out.png initial name") }
let (inPath, outPath, initial, name) = (args[1], args[2], args[3], args[4])

guard let src = NSImage(contentsOfFile: inPath),
      let srcRep = NSBitmapImageRep(data: src.tiffRepresentation!) else {
    fatalError("cannot read \(inPath)")
}
let qrSize = srcRep.pixelsWide           // square QR canvas
let captionHeight = 96
let width = qrSize, height = qrSize + captionHeight

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height,
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                           isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

// White ground, QR on top; the caption owns the bottom strip.
NSColor.white.setFill()
NSRect(x: 0, y: 0, width: width, height: height).fill()
src.draw(in: NSRect(x: 0, y: captionHeight, width: qrSize, height: qrSize))

// Center badge: white rounded square with a black border. Sized relative to
// the code so smaller versions keep the same safety margin (a fixed 138pt
// badge broke version-10 codes by swallowing the central alignment pattern).
let badge: CGFloat = (CGFloat(qrSize) * 0.14).rounded()
let bx = (CGFloat(qrSize) - badge) / 2
let by = CGFloat(captionHeight) + (CGFloat(qrSize) - badge) / 2
let badgeRect = NSRect(x: bx, y: by, width: badge, height: badge)
let path = NSBezierPath(roundedRect: badgeRect, xRadius: 22, yRadius: 22)
NSColor.white.setFill(); path.fill()
path.lineWidth = 6; NSColor.black.setStroke(); path.stroke()

func drawCentered(_ text: String, fontSize: CGFloat, centerX: CGFloat, centerY: CGFloat) {
    let font = NSFont(name: "Helvetica-Bold", size: fontSize)!
    let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
    let str = NSAttributedString(string: text, attributes: attrs)
    let bounds = str.boundingRect(with: .zero, options: [.usesLineFragmentOrigin])
    str.draw(at: NSPoint(x: centerX - bounds.width / 2, y: centerY - bounds.height / 2))
}

drawCentered(initial, fontSize: (badge * 0.62).rounded(), centerX: badgeRect.midX, centerY: badgeRect.midY)
drawCentered(name, fontSize: 54, centerX: CGFloat(width) / 2, centerY: CGFloat(captionHeight) / 2)

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: outPath))

// Verify the badged code still decodes and names the right device.
let handler = VNImageRequestHandler(url: URL(fileURLWithPath: outPath))
let request = VNDetectBarcodesRequest()
request.symbologies = [.qr]
try! handler.perform([request])
guard let payload = request.results?.first?.payloadStringValue else {
    print("VERIFY FAILED \(name): no QR decoded"); exit(1)
}
let device = payload.contains("\"deviceName\":\"\(name) iPhone\"")
print("VERIFY \(name): decoded=\(payload.count) chars, deviceName match=\(device)")
exit(device ? 0 : 1)
