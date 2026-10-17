import AppKit
let directory = CommandLine.arguments[1]
try FileManager.default.createDirectory(atPath:directory,withIntermediateDirectories:true)
for size in [16,32,64,128,256,512,1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:size,pixelsHigh:size,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    let context = NSGraphicsContext(bitmapImageRep:bitmap)!
    NSGraphicsContext.saveGraphicsState();NSGraphicsContext.current = context
    context.cgContext.scaleBy(x:CGFloat(size)/1024,y:CGFloat(size)/1024)
    let tile = NSBezierPath(roundedRect:NSRect(x:44,y:44,width:936,height:936),xRadius:205,yRadius:205)
    NSGraphicsContext.saveGraphicsState();tile.addClip()
    NSGradient(colors:[NSColor(red:0.23,green:0.22,blue:0.86,alpha:1),NSColor(red:0.05,green:0.55,blue:0.98,alpha:1)])!.draw(in:NSRect(x:44,y:44,width:936,height:936),angle:45)
    NSGraphicsContext.restoreGraphicsState()
    NSColor.white.withAlphaComponent(0.98).setFill()
    NSBezierPath(roundedRect:NSRect(x:184,y:333,width:656,height:440),xRadius:41,yRadius:41).fill()
    NSBezierPath(roundedRect:NSRect(x:468,y:247,width:88,height:100),xRadius:14,yRadius:14).fill()
    NSBezierPath(roundedRect:NSRect(x:360,y:224,width:304,height:34),xRadius:17,yRadius:17).fill()
    NSGraphicsContext.saveGraphicsState();let screen=NSRect(x:209,y:378,width:606,height:371)
    NSBezierPath(roundedRect:screen,xRadius:20,yRadius:20).addClip()
    NSGradient(colors:[NSColor(red:0.48,green:0.40,blue:0.98,alpha:1),NSColor(red:0.20,green:0.85,blue:0.95,alpha:1),NSColor(red:0.08,green:0.52,blue:0.98,alpha:1)])!.draw(in:screen,angle:25)
    NSColor.white.withAlphaComponent(0.25).setFill();NSBezierPath(roundedRect:NSRect(x:250,y:422,width:330,height:270),xRadius:26,yRadius:26).fill()
    NSColor.white.withAlphaComponent(0.4).setFill();NSBezierPath(roundedRect:NSRect(x:322,y:400,width:360,height:243),xRadius:26,yRadius:26).fill()
    NSGraphicsContext.restoreGraphicsState();NSGraphicsContext.restoreGraphicsState()
    let data=bitmap.representation(using:.png,properties:[:])!
    let names:[String]
    if size==16 {names=["icon_16x16"]}
    else if size==32 {names=["icon_16x16@2x","icon_32x32"]}
    else if size==64 {names=["icon_32x32@2x"]}
    else if size==128 {names=["icon_128x128"]}
    else if size==256 {names=["icon_128x128@2x","icon_256x256"]}
    else if size==512 {names=["icon_256x256@2x","icon_512x512"]}
    else {names=["icon_512x512@2x"]}
    for name in names {try data.write(to:URL(fileURLWithPath:directory+"/"+name+".png"))}
}
