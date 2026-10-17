// Render only our own installer artwork; no desktop capture or UI bridge.
import AppKit

let destination = URL(fileURLWithPath:CommandLine.arguments[1], isDirectory:true)
let version = CommandLine.arguments[2]
let app = URL(fileURLWithPath:CommandLine.arguments[3], isDirectory:true)
let role = CommandLine.arguments.count > 4 ? CommandLine.arguments[4] : "Host"
let width: CGFloat = 800, height: CGFloat = 570
try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true)
let ink = NSColor(srgbRed:0.12, green:0.15, blue:0.23, alpha:1)
let secondary = NSColor(srgbRed:0.34, green:0.39, blue:0.49, alpha:1)
let accent = NSColor(srgbRed:0.28, green:0.34, blue:0.80, alpha:1)

func rect(_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ h:CGFloat)->NSRect {
    NSRect(x:x,y:height-y-h,width:w,height:h)
}
func text(_ value:String,_ x:CGFloat,_ y:CGFloat,_ w:CGFloat,_ size:CGFloat,
          _ weight:NSFont.Weight = .regular,_ color:NSColor = ink,_ centered:Bool = false) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = centered ? .center : .left
    paragraph.lineBreakMode = .byWordWrapping
    (value as NSString).draw(in:rect(x,y,w,size*2.8),withAttributes:[
        .font:NSFont.systemFont(ofSize:size,weight:weight),.foregroundColor:color,.paragraphStyle:paragraph])
}
func glass(_ r:NSRect,_ radius:CGFloat) {
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow(); shadow.shadowColor = ink.withAlphaComponent(0.055)
    shadow.shadowBlurRadius = 24; shadow.shadowOffset = NSSize(width:0,height:-7); shadow.set()
    let path = NSBezierPath(roundedRect:r,xRadius:radius,yRadius:radius)
    NSColor.white.withAlphaComponent(0.62).setFill(); path.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.9).setStroke(); path.lineWidth = 1; path.stroke()
}
func artwork(preview:Bool,scale:Int)->NSBitmapImageRep {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:Int(width)*scale,
        pixelsHigh:Int(height)*scale,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,
        isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    bitmap.size = NSSize(width:width,height:height)
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep:bitmap)!
    NSGraphicsContext.current = context
    // bitmap.size defines logical points; the context already supplies 2x scale.
    NSGradient(colors:[NSColor(srgbRed:0.98,green:0.985,blue:1,alpha:1),
                       NSColor(srgbRed:0.89,green:0.93,blue:1,alpha:1)])!.draw(in:NSRect(x:0,y:0,width:width,height:height),angle:-28)
    let glow = NSGradient(starting:NSColor(srgbRed:0.70,green:0.76,blue:1,alpha:0.5),ending:NSColor.white.withAlphaComponent(0))!
    glow.draw(in:NSBezierPath(ovalIn:rect(450,-180,600,600)),relativeCenterPosition:.zero)
    text("RetinaLink",44,30,300,20,.semibold,accent)
    text(version,658,35,98,12,.medium,secondary,true)
    text("Your iMac. A second display.",44,87,720,32,.semibold)
    text(role == "Host" ? "Install Host here. Open Viewer on your iMac once." : "Install Viewer on your iMac. Approve your main Mac once.",44,135,720,15,.regular,secondary)
    glass(rect(146,194,148,148),32)
    glass(rect(506,194,148,148),32)
    // A quiet directional affordance between the two draggable Finder icons.
    let arrow = NSBezierPath(); arrow.move(to:NSPoint(x:365,y:height-260))
    arrow.line(to:NSPoint(x:432,y:height-260)); arrow.move(to:NSPoint(x:418,y:height-247))
    arrow.line(to:NSPoint(x:432,y:height-260)); arrow.line(to:NSPoint(x:418,y:height-273))
    accent.withAlphaComponent(0.65).setStroke(); arrow.lineWidth = 2.5
    arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round; arrow.stroke()
    text("DRAG TO INSTALL",334,287,132,10,.semibold,secondary,true)
    glass(rect(40,382,720,148),24)
    text(role == "Host" ? "Open Host. Add your display." : "Open Viewer. Approve your Mac.",64,405,490,18,.semibold)
    text(role == "Host" ? "Open Host from Applications and choose Add Display.\nCompare the number on both Macs to pair once." : "Open Viewer from Applications on your iMac.\nOn your main Mac, open Host and choose Add Display.",64,437,493,13,.regular,secondary)
    text("Connects directly. Remote Login is not required.",64,492,495,12,.medium,secondary)
    if preview {
        let images:[(String,NSImage,CGFloat,CGFloat)] = [
            ("RetinaLink "+role,NSImage(contentsOf:app.appendingPathComponent("Contents/Resources/AppIcon.icns"))!,220,260),
            ("Applications",NSWorkspace.shared.icon(forFile:"/Applications"),580,260),
            ("Setup Guide",NSWorkspace.shared.icon(forFile:destination.appendingPathComponent("Setup Guide.html").path),666,449)]
        for (name,icon,x,y) in images {
            icon.draw(in:rect(x-48,y-48,96,96))
            text(name,x-100,y+57,200,13,.regular,ink,true)
        }
    }
    NSGraphicsContext.restoreGraphicsState()
    return bitmap
}
let reps = [artwork(preview:false,scale:1),artwork(preview:false,scale:2)]
try NSBitmapImageRep.representationOfImageReps(in:reps,using:.tiff,properties:[:])!
    .write(to:destination.appendingPathComponent("Installer Background.tiff"))
try artwork(preview:true,scale:2).representation(using:.png,properties:[:])!
    .write(to:destination.appendingPathComponent("Installer Preview.png"))
