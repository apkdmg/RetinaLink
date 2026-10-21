import Foundation
import Compression

// Encoding 3 preserves the encoding-2 chunk envelope and frame/tile metadata.
// Only each tile's BC7 bytes are transformed, independently of previous frames.
enum BC7Packing {
    static func shouldTransform(_ tiles:[TileUpdate])->Bool {
        guard !tiles.isEmpty, tiles.allSatisfy({$0.bytes.count > 0 && $0.bytes.count <= 16384 && $0.bytes.count % 128 == 0}) else {return false}
        // Four evenly spaced samples avoid paying for two complete encodes.
        // LZ4 already handles solid fills/text very well; leave those unchanged.
        var buffer=[UInt8](repeating:0,count:17408), transformed=[UInt8](repeating:0,count:16384)
        var stored=0, candidate=0, original=0
        for sample in 0..<min(4,tiles.count) {
            let bytes=tiles[sample*(tiles.count-1)/max(1,min(4,tiles.count)-1)].bytes
            let n=bytes.withUnsafeBytes { source in
                compression_encode_buffer(&buffer,buffer.count,source.bindMemory(to:UInt8.self).baseAddress!,bytes.count,nil,COMPRESSION_LZ4)
            }
            let shuffled=bytes.withUnsafeBytes { source -> Int in
                _ = retinalink_bc7_transform(source.bindMemory(to:UInt8.self).baseAddress!,&transformed,bytes.count,0)
                return compression_encode_buffer(&buffer,buffer.count,&transformed,bytes.count,nil,COMPRESSION_LZ4)
            }
            stored += n > 0 ? min(n,bytes.count):bytes.count
            candidate += shuffled > 0 ? min(shuffled,bytes.count):bytes.count
            original += bytes.count
        }
        return stored > original*4/5 && candidate < stored*9/10
    }

    // Called only after Frame.parse has checked dimensions, unique tile IDs,
    // exact tile sizes, complete keyframes and trailing bytes. A single backing
    // buffer owns the restored tiles; workers write disjoint validated spans.
    static func restore(_ tiles:[TileUpdate])->[TileUpdate] {
        guard !tiles.isEmpty else {return []}
        var offsets:[Int]=[], count=0
        for tile in tiles {offsets.append(count);count += tile.bytes.count}
        var restored=Data(count:count)
        restored.withUnsafeMutableBytes { destination in
            DispatchQueue.concurrentPerform(iterations:min(4,tiles.count)) { worker in
                for i in stride(from:worker,to:tiles.count,by:min(4,tiles.count)) {
                    let bytes=tiles[i].bytes
                    bytes.withUnsafeBytes { source in
                        _ = retinalink_bc7_transform(source.bindMemory(to:UInt8.self).baseAddress!,destination.baseAddress!.advanced(by:offsets[i]).assumingMemoryBound(to:UInt8.self),bytes.count,1)
                    }
                }
            }
        }
        return tiles.enumerated().map {i,tile in TileUpdate(id:tile.id,bytes:restored[offsets[i]..<(offsets[i]+tile.bytes.count)])}
    }
}
