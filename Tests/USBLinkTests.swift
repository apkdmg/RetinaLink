import Foundation

func runUSBLinkTests() throws {
    typealias Node = USBLinkRegistryNode
    let interface = Node(className:"IOEthernetInterface")
    let deviceData = Node(className:"AppleUSBDeviceNCM11Data",bundleIdentifier:"com.apple.driver.AppleUSBDeviceNCM")
    let dataFunction = Node(className:"IOUSBDeviceInterface",function:"AppleUSBNCMData")
    let controller = Node(className:"AppleT8112USBXDCI",deviceController:true)
    let deviceChain = [interface,deviceData,dataFunction,controller]
    try check(USBLinkInterfaces.classify(interfaceName:"en6",ancestry:deviceChain)?.source == .deviceNCM,
        "Public Apple Silicon NCM interface was not recognized")
    var inactiveData = deviceData; inactiveData.linkStatus = 1; inactiveData.linkSpeed = 0
    var activeData = deviceData; activeData.linkStatus = 3; activeData.linkSpeed = 5_000_000_000
    var unknownData = deviceData; unknownData.linkStatus = 0
    try check(USBLinkInterfaces.classify(interfaceName:"en6",ancestry:[interface,inactiveData,dataFunction,controller])?.linkActive == false,
        "Always-instantiated inactive NCM port was reported connected")
    let active = USBLinkInterfaces.classify(interfaceName:"en6",ancestry:[interface,activeData,dataFunction,controller])
    try check(active?.linkActive == true && active?.nominalLinkSpeed == 5_000_000_000,
        "Valid NCM link status/speed was lost")
    try check(USBLinkInterfaces.classify(interfaceName:"en6",ancestry:[interface,unknownData,dataFunction,controller])?.linkActive == nil,
        "Invalid NCM link status was treated as a definite physical link")
    let hostData = Node(className:"AppleUSBNCMData",bundleIdentifier:"com.apple.driver.usb.cdc.ncm")
    let mac = Node(className:"IOUSBHostDevice",vendorID:0x05ac,productID:0x1905,productName:"Mac",hostDevice:true)
    let hostChain = [interface,hostData,mac]
    try check(USBLinkInterfaces.classify(interfaceName:"en8",ancestry:hostChain)?.source == .hostMacNCM,
        "Known Apple Mac NCM peer was not recognized")
    var earlierMac = mac; earlierMac.productID = 0x1902
    try check(USBLinkInterfaces.classify(interfaceName:"en8",ancestry:[interface,hostData,earlierMac])?.source == .hostMacNCM,
        "Earlier Mac NCM product was not recognized")
    for name in ["anpi0","anri0","bridge0","utun2","awdl0","en","en-1","en1/2",String(repeating:"e",count:20),"en１"] {
        try check(USBLinkInterfaces.classify(interfaceName:name,ancestry:deviceChain) == nil,
            "Private, virtual or malformed interface became direct USB")
    }
    var privateInterface = interface; privateInterface.className = "AppleUSBDeviceNCMPrivateEthernetInterface"
    var restrictedInterface = interface; restrictedInterface.className = "AppleUSBHostNCMRestrictedEthernetInterface"
    var hiddenData = deviceData; hiddenData.hiddenInterface = true
    var auxFunction = dataFunction; auxFunction.function = "AppleUSBNCMDataAux"
    var wrongDriver = deviceData; wrongDriver.bundleIdentifier = "com.example.driver"
    for chain in [[],[interface],[privateInterface,deviceData,dataFunction,controller],
                  [restrictedInterface,deviceData,dataFunction,controller],
                  [interface,hiddenData,dataFunction,controller],
                  [interface,deviceData,auxFunction,controller],
                  [interface,wrongDriver,dataFunction,controller],
                  [interface,deviceData,dataFunction],Array(repeating:interface,count:13)] {
        try check(USBLinkInterfaces.classify(interfaceName:"en6",ancestry:chain) == nil,
            "Incomplete or private Apple NCM topology became direct USB")
    }
    let otherUSBDevices:[Node] = [
        Node(className:"IOUSBHostDevice",vendorID:0x0b95,productID:0x1790,productName:"AX88179B",hostDevice:true),
        Node(className:"IOUSBHostDevice",vendorID:0x0bda,productID:0x8156,productName:"USB 2.5G Ethernet",hostDevice:true),
        Node(className:"IOUSBHostDevice",vendorID:0x05ac,productID:0x12a8,productName:"iPhone",hostDevice:true),
        Node(className:"IOUSBHostDevice",vendorID:0x05ac,productID:0x1114,productName:"Studio Display",hostDevice:true),
        Node(className:"IOUSBHostDevice",vendorID:0x05ac,productID:0x800a,productName:"USB3 Gen2 Hub",hostDevice:true),
        Node(className:"IOUSBHostDevice",vendorID:0x0b95,productID:0x1905,productName:"Mac",hostDevice:true),
        Node(className:"IOUSBHostDevice",vendorID:0x05ac,productID:0x1999,productName:"Mac",hostDevice:true),
        Node(className:"IOUSBHostDevice",vendorID:0x05ac,productID:0x1905,productName:"iPhone",hostDevice:true),
        Node(className:"IOUSBHostDevice",vendorID:0x05ac,productID:0x1905,productName:"Mac",hostDevice:false)
    ]
    for peer in otherUSBDevices {
        try check(USBLinkInterfaces.classify(interfaceName:"en14",ancestry:[interface,hostData,peer]) == nil,
            "USB Ethernet dongle, iPhone, display or unverified Mac product became direct USB")
    }
    // A hub nearest to the NIC must not borrow the matching properties of a
    // farther Mac device. Runtime traversal also stops at this nearest device.
    try check(USBLinkInterfaces.classify(interfaceName:"en14",ancestry:[interface,hostData,otherUSBDevices[0],mac]) == nil,
        "An unrelated USB NIC borrowed the identity of an ancestor Mac")
    try check(USBLinkInterfaces.classify(interfaceName:"en3",ancestry:[interface,
        Node(className:"AppleThunderboltIPPort"),controller]) == nil,
        "Thunderbolt interface became direct USB")
    print("PASS: Read-only direct USB topology, public Mac NCM positives and USB NIC/iPhone/private/virtual negative controls")
}
