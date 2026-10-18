import Foundation
import Network

func runDirectLinkTests() throws {
    // Exercise the dictionary path explicitly: on the real Big Sur receiver,
    // NWBrowser provides a valid dictionary while subscript/getEntry return nil.
    let disposableID = UUID().uuidString
    try check(DirectLinkTXT.identity(["hostID":disposableID,"direct":"1"],key:"hostID") == disposableID,
        "Bonjour compatibility dictionary lost its Host identity")
    try check(DirectLinkTXT.identity(["HoStId":disposableID],key:"hostID") == disposableID,
        "Bonjour TXT identity keys were treated as case-sensitive")
    for dictionary in [["hostID":""],["hostID":"not-a-uuid"],["hostID":String(repeating:"A",count:65)],
                       ["hostID":disposableID,"HOSTID":disposableID],["viewerID":disposableID]] {
        try check(DirectLinkTXT.identity(dictionary,key:"hostID") == nil,"Ambiguous or invalid Bonjour identity was accepted")
    }
    let synthetic = NWTXTRecord(["hostID":disposableID,"direct":"1"])
    try check(DirectLinkTXT.identity(synthetic,key:"hostID") == disposableID,
        "NWTXTRecord dictionary extraction is incompatible with this OS")
    let wire = NetService.data(fromTXTRecord:["hostID":Data(disposableID.utf8),"direct":Data("1".utf8)])
    let decodedWire = NetService.dictionary(fromTXTRecord:wire).reduce(into:[String:String]()) { result,item in
        result[item.key] = String(data:item.value,encoding:.utf8)
    }
    try check(DirectLinkTXT.identity(decodedWire,key:"hostID") == disposableID,"Legacy NetService TXT wire format lost its identity")
    if #available(macOS 13.0,*) {
        try check(DirectLinkTXT.identity(NWTXTRecord(wire),key:"hostID") == disposableID,
            "NWTXTRecord could not parse the published NetService TXT wire format")
    }
    print("PASS: Big Sur-compatible Bonjour TXT dictionary identity, case-insensitive keys and malformed/ambiguous rejection")
    typealias State = DirectLinkInterfaceState
    try check(State.classifyIPv4([169,254,30,50]) == .linkLocal,"IPv4 automatic addressing classification")
    try check(State.classifyIPv4([10,28,114,241]) == .configured,"Company IPv4 address treated as automatic")
    for bytes:[UInt8] in [[127,0,0,1],[0,0,0,0],[224,0,0,251],[255,255,255,255],[]] {
        try check(State.classifyIPv4(bytes) == .ignored,"Special IPv4 address became cable preference")
    }
    let linkLocal:[UInt8] = [0xfe,0x80]+Array(repeating:0,count:13)+[1]
    let linkLocalEnd:[UInt8] = [0xfe,0xbf]+Array(repeating:0,count:13)+[1]
    let global:[UInt8] = [0x20,1]+Array(repeating:0,count:13)+[1]
    let privateIPv6:[UInt8] = [0xfd,1]+Array(repeating:0,count:13)+[1]
    try check(State.classifyIPv6(linkLocal) == .linkLocal && State.classifyIPv6(linkLocalEnd) == .linkLocal,"IPv6 link-local /10 scope classification")
    try check(State.classifyIPv6(global) == .configured && State.classifyIPv6(privateIPv6) == .configured,"Configured IPv6 network treated as cable-only")
    for bytes:[UInt8] in [Array(repeating:0,count:16),Array(repeating:0,count:15)+[1],[0xff,2]+Array(repeating:0,count:13)+[0xfb],[]] {
        try check(State.classifyIPv6(bytes) == .ignored,"Special IPv6 address became cable preference")
    }
    let automatic = State(hasLinkLocal:true,hasIPv6LinkLocal:true,hasConfiguredAddress:false,isUp:true)
    let company = State(hasLinkLocal:true,hasIPv6LinkLocal:true,hasConfiguredAddress:true,isUp:true)
    try check(automatic.automaticAddressing && !company.automaticAddressing,"Company Ethernet incorrectly labeled automatic-only")
    let cableRank = DirectLinkPreference.rank(type:.wiredEthernet,state:automatic)
    let companyRank = DirectLinkPreference.rank(type:.wiredEthernet,state:company)
    let wifiRank = DirectLinkPreference.rank(type:.wifi,state:company)
    try check(cableRank < companyRank && companyRank < wifiRank,"Automatic Ethernet/LAN/Wi-Fi preference order")
    // A physical cable cannot be inferred from these observations. This policy
    // only prefers an interface; the real peer must still pass TLS authentication.
    print("PASS: IPv4/IPv6 automatic addressing, configured company network preservation and interface preference policy")
}
