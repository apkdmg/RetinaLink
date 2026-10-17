import AppKit
import CoreGraphics
let screens=NSScreen.screens.map { s -> [String:Any] in
 let id=(s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as! NSNumber).uint32Value
 let mode=CGDisplayCopyDisplayMode(id)
 return ["id":id,"builtin":CGDisplayIsBuiltin(id) != 0,"main":CGDisplayIsMain(id) != 0,"active":CGDisplayIsActive(id) != 0,"asleep":CGDisplayIsAsleep(id) != 0,"vendor":CGDisplayVendorNumber(id),"model":CGDisplayModelNumber(id),"width":mode?.pixelWidth ?? 0,"height":mode?.pixelHeight ?? 0,"hz":mode?.refreshRate ?? 0,"scale":s.backingScaleFactor]
}
let session=CGSessionCopyCurrentDictionary() as? [String:Any]
let info:[String:Any]=["screens":screens,"onConsole":session?["kCGSessionOnConsoleKey"] ?? "unknown","thermalState":ProcessInfo.processInfo.thermalState.rawValue]
print(String(data:try! JSONSerialization.data(withJSONObject:info,options:[.sortedKeys]),encoding:.utf8)!)
