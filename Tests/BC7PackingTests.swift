import Foundation

func testShuffledPacking() throws {
    var state:UInt64=0x8f1a7c623de05b94
    func noise(_ count:Int,mask:UInt64=UInt64.max)->Data {
        var data=Data(count:count)
        data.withUnsafeMutableBytes { bytes in
            for offset in stride(from:0,to:count,by:8) {
                state ^= state<<13;state ^= state>>7;state ^= state<<17
                bytes.storeBytes(of:state & mask,toByteOffset:offset,as:UInt64.self)
            }
        }
        return data
    }
    // All supported sizes, arbitrary BC7 modes/alpha, wraparound, unaligned
    // pointers, and every bit position exercise the native inverse directly.
    var inputs=(1...128).map {noise($0*128)}
    inputs += [Data(repeating:0,count:16384),Data(repeating:255,count:16384)]
    var bits=Data(count:16384)
    for i in 0..<128 {bits[i*16+i/8] = 1 << (i%8)}
    inputs.append(bits)
    for input in inputs {
        let padded=Data([0])+input
        var encoded=Data(count:input.count), decoded=Data(count:input.count)
        let forward=encoded.withUnsafeMutableBytes { dst in padded.withUnsafeBytes { src in
            retinalink_bc7_transform(src.bindMemory(to:UInt8.self).baseAddress!.advanced(by:1),dst.bindMemory(to:UInt8.self).baseAddress!,input.count,0)
        }}
        let reverse=decoded.withUnsafeMutableBytes { dst in encoded.withUnsafeBytes { src in
            retinalink_bc7_transform(src.bindMemory(to:UInt8.self).baseAddress!,dst.bindMemory(to:UInt8.self).baseAddress!,input.count,1)
        }}
        try check(forward==1 && reverse==1 && decoded==input,"BC7 transform must restore every bit")
    }
    try check(retinalink_bc7_transform(nil,nil,16384,0)==0,"Invalid native transform buffers accepted")
    let legacy=try JSONDecoder().decode(Hello.self,from:Data("{\"version\":1,\"bc7\":true,\"name\":\"legacy\",\"chunkedPacking\":true}".utf8))
    try check(legacy.shuffledPacking==nil,"Older Viewers must not receive encoding 3")
    let greeting=Hello(version:1,bc7:true,name:"new",chunkedPacking:true,shuffledPacking:true)
    try check(try JSONDecoder().decode(Hello.self,from:JSONEncoder().encode(greeting)).shuffledPacking==true,"Transform capability round trip")
    let packer=FramePacker()
    var retained:[(Data,Frame)]=[]
    for (w,h) in [(2560,1440),(3840,2160),(5120,2880)] {
        let total=((w+127)/128)*((h+127)/128)
        let tiles=(0..<total).map {id -> TileUpdate in
            let d=Frame.dimensions(id,w,h)
            return TileUpdate(id:id,bytes:noise(d.w*d.h,mask:0x0000ffffffffffff))
        }
        let frame=Frame(sequence:UInt64(w),width:w,height:h,keyframe:true,tiles:tiles)
        let packet=try packer.serialize(frame,parallel:true,shuffled:true)
        try check(packet.first==3,"Dense fixture did not exercise shuffled packing")
        try check(try packer.serialize(frame,parallel:true).first != 3,"Unnegotiated transform was used")
        retained.append((packet,frame))
        // Include sparse, out-of-order tile IDs and the partial bottom row.
        let sparse=Frame(sequence:UInt64(w+1),width:w,height:h,keyframe:false,tiles:Array(tiles.suffix(100).reversed()))
        let sparsePacket=try packer.serialize(sparse,parallel:true,shuffled:true)
        try check(sparsePacket.first==3,"Sparse fixture did not exercise shuffled packing")
        retained.append((sparsePacket,sparse))
    }
    for (packet,frame) in retained {
        for copy in [false,true] {
            let decoded=try Frame.parse((Data([0xff])+packet).dropFirst(),copyBuffers:copy)
            try check(decoded.sequence==frame.sequence && decoded.width==frame.width && decoded.height==frame.height && decoded.keyframe==frame.keyframe,"Shuffled frame identity changed")
            try check(decoded.tiles.count==frame.tiles.count && zip(decoded.tiles,frame.tiles).allSatisfy {$0.id==$1.id && $0.bytes==$1.bytes},"Shuffled frame changed BC7 data, tile order or buffer ownership")
        }
        for size in [0,9,20,packet.count-1] {try expectInvalid {_ = try Frame.parse(packet.prefix(size))}}
    }
    let solid=Frame(sequence:1,width:5120,height:2880,keyframe:false,tiles:(0..<100).map {TileUpdate(id:$0,bytes:Data(repeating:0x40,count:16384))})
    try check(try packer.serialize(solid,parallel:true,shuffled:true)==packer.serialize(solid,parallel:true),"Easily compressed desktop content must retain its fast path")
    let random=Frame(sequence:2,width:5120,height:2880,keyframe:false,tiles:(0..<100).map {TileUpdate(id:$0,bytes:noise(16384))})
    let fallback=try packer.serialize(random,parallel:true,shuffled:true)
    try check(fallback.first==0,"Incompressible frame must exercise original-byte fallback")
    try check(try Frame.parse(fallback).tiles.map(\.bytes)==random.tiles.map(\.bytes),"Raw fallback retained transformed data")
    // Chunk validation is shared with encoding 2. Malformed inner metadata must
    // be rejected before any native tile transform sees an untrusted length.
    func envelope(_ raw:Data)->Data {
        let split=raw.count/2
        var body=Data();body.put32(2)
        for part in [raw.prefix(split),raw.suffix(raw.count-split)] {body.put32(UInt32(part.count));body.put32(UInt32(part.count));body.append(part)}
        var packet=Data([3]);packet.put32(UInt32(raw.count));packet.put32(UInt32(body.count));packet.append(body);return packet
    }
    for (width,flags,ids) in [(UInt32(5119),UInt32(0),[0]),(5120,1,[0]),(5120,0,[0,0]),(5120,0,[9999])] {
        var raw=Data();raw.put64(1);raw.put32(width);raw.put32(2880);raw.put32(flags);raw.put32(UInt32(ids.count))
        for id in ids {raw.put32(UInt32(id));raw.append(Data(repeating:0,count:16384))}
        try expectInvalid {_ = try Frame.parse(envelope(raw))}
    }
    print("PASS: lossless BC7 transform, 1440p/4K/5K and edge tiles, sparse ordering, retained buffers, legacy/adaptive/raw fallback, malformed metadata")
}
