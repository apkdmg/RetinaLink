import Foundation
import IOKit

// These are transport observations, never device identities or proof that a
// cable reaches the trusted peer. The connection still has to authenticate TLS.
enum USBLinkSource:String,Equatable {
    case deviceNCM
    case hostMacNCM
}

struct USBLinkObservation:Equatable {
    let source:USBLinkSource
    var linkActive:Bool? = nil
    var nominalLinkSpeed:UInt64? = nil
}

// A deliberately small, read-only view of one IOService ancestor. Keeping the
// classifier separate makes USB dongles, iPhones and private Apple interfaces
// useful negative controls without needing to attach those devices in tests.
struct USBLinkRegistryNode {
    var className:String
    var bundleIdentifier:String? = nil
    var function:String? = nil
    var vendorID:Int? = nil
    var productID:Int? = nil
    var productName:String? = nil
    var hiddenInterface = false
    var deviceController = false
    var hostDevice = false
    var linkStatus:UInt32? = nil
    var linkSpeed:UInt64? = nil
}

enum USBLinkInterfaces {
    private static let deviceDataClasses:Set<String> = ["AppleUSBDeviceNCMData","AppleUSBDeviceNCM11Data"]
    private static let hostDataClasses:Set<String> = ["AppleUSBNCMData","AppleUSBNCM11Data"]
    private static let excludedClasses:Set<String> = [
        "AppleUSBDeviceNCMPrivateEthernetInterface","AppleUSBHostNCMRestrictedEthernetInterface"
    ]

    static func classify(interfaceName:String,ancestry:[USBLinkRegistryNode])->USBLinkObservation? {
        // Public USB NCM interfaces use en*. anpi/anri are private/restricted
        // management channels, and an arbitrary VPN or bridge is not USB.
        let suffix = interfaceName.dropFirst(2)
        guard interfaceName.hasPrefix("en"), !suffix.isEmpty, interfaceName.utf8.count <= 16,
              suffix.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }),
              !ancestry.isEmpty, ancestry.count <= 12,
              ancestry.first?.className == "IOEthernetInterface",
              !ancestry.contains(where:{ $0.hiddenInterface || excludedClasses.contains($0.className) }),
              !ancestry.contains(where:{ ($0.function?.hasSuffix("Aux") ?? false) }) else { return nil }

        if let driver = ancestry.first(where:{ deviceDataClasses.contains($0.className) &&
            $0.bundleIdentifier == "com.apple.driver.AppleUSBDeviceNCM" }),
           ancestry.contains(where:{ $0.function == "AppleUSBNCMData" }),
           ancestry.contains(where:{ $0.deviceController }) {
            return observation(source:.deviceNCM,driver:driver)
        }

        // NCM alone also describes ordinary USB-to-Ethernet adapters. On the
        // Intel USB-host side require the closest real USB device to be a known
        // Mac, not an iPhone, Studio Display, hub or a product named "Mac" by a
        // third party. Unknown future products remain ordinary network paths.
        // Mac 05ac:1905 is documented by upstream Linux commit a5148bc2fa27;
        // 1902 is the earlier Mac USB NCM product in the same family.
        if let driver = ancestry.first(where:{ hostDataClasses.contains($0.className) &&
            $0.bundleIdentifier == "com.apple.driver.usb.cdc.ncm" }),
           let device = ancestry.first(where:{ $0.hostDevice }),
           device.vendorID == 0x05ac,
           device.productID == 0x1905 || device.productID == 0x1902,
           device.productName == "Mac" {
            return observation(source:.hostMacNCM,driver:driver)
        }
        return nil
    }

    private static func observation(source:USBLinkSource,driver:USBLinkRegistryNode)->USBLinkObservation {
        // IONetworkMedium.h: kIONetworkLinkValid = IFM_AVALID (1),
        // kIONetworkLinkActive = IFM_ACTIVE (2). An instantiated NCM port whose
        // link is inactive is available hardware, not a connected USB peer.
        let active = driver.linkStatus.flatMap { $0 & 1 != 0 ? $0 & 2 != 0 : nil }
        let speed = driver.linkSpeed.flatMap { $0 > 0 ? $0 : nil }
        return USBLinkObservation(source:source,linkActive:active,nominalLinkSpeed:speed)
    }

    static func snapshot()->[String:USBLinkObservation] {
        var iterator:io_iterator_t = 0
        // NULL means the default IOKit main port on every supported macOS.
        // kIOMainPortDefault itself was introduced only in macOS 12.
        guard IOServiceGetMatchingServices(0,IOServiceMatching("IOEthernetInterface"),&iterator) == KERN_SUCCESS else { return [:] }
        defer { IOObjectRelease(iterator) }
        var result:[String:USBLinkObservation] = [:]
        for _ in 0..<128 {
            let interface = IOIteratorNext(iterator)
            guard interface != 0 else { break }
            defer { IOObjectRelease(interface) }
            guard let name = property(interface,"BSD Name") as? String,
                  name.hasPrefix("en"), name.utf8.count <= 16 else { continue }
            let nodes = ancestry(of:interface)
            if let observation = classify(interfaceName:name,ancestry:nodes) { result[name] = observation }
        }
        return result
    }

    private static func property(_ entry:io_registry_entry_t,_ key:String)->Any? {
        IORegistryEntryCreateCFProperty(entry,key as CFString,kCFAllocatorDefault,0)?.takeRetainedValue()
    }

    private static func ancestry(of interface:io_registry_entry_t)->[USBLinkRegistryNode] {
        var nodes:[USBLinkRegistryNode] = []
        var current = interface
        IOObjectRetain(current)
        defer { IOObjectRelease(current) }
        for _ in 0..<12 {
            let name = IOObjectCopyClass(current)?.takeRetainedValue() as String? ?? ""
            let controller = IOObjectConformsTo(current,"IOUSBDeviceController") != 0
            let host = IOObjectConformsTo(current,"IOUSBHostDevice") != 0 || IOObjectConformsTo(current,"IOUSBDevice") != 0
            nodes.append(USBLinkRegistryNode(className:name,
                bundleIdentifier:property(current,"CFBundleIdentifier") as? String,
                function:property(current,"USBDeviceFunction") as? String,
                vendorID:(property(current,"idVendor") as? NSNumber)?.intValue,
                productID:(property(current,"idProduct") as? NSNumber)?.intValue,
                productName:property(current,"USB Product Name") as? String,
                hiddenInterface:(property(current,"HiddenInterface") as? NSNumber)?.boolValue ?? false,
                deviceController:controller,hostDevice:host,
                linkStatus:(property(current,"IOLinkStatus") as? NSNumber)?.uint32Value,
                linkSpeed:(property(current,"IOLinkSpeed") as? NSNumber)?.uint64Value))
            // Do not wander through the USB host controller to a parent hub or
            // into the device tree after we have the actual USB peer/controller.
            if host || controller { break }
            var parent:io_registry_entry_t = 0
            guard IORegistryEntryGetParentEntry(current,kIOServicePlane,&parent) == KERN_SUCCESS else { break }
            IOObjectRelease(current); current = parent
        }
        return nodes
    }
}
