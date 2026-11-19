// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Only explicit, bounded world-index entries may request an HD image. Sparse
/// or absent files do not change the required base world/collision contract.
struct NativeWorldSharpManifest {
    enum Invalid:Error {case data,profile,cell}
    struct Entry:Equatable {let name:String,layers:Int,sharpLayers:Int}
    private struct Document:Decodable {
        struct Cell:Decodable {let cell:Int,layers:Int,sharp:Int}
        struct Detail:Decodable {let cell:Int,columns:Int,sharp:Int,sharpColumns:Int,cells:[Cell]}
        struct Inside:Decodable {let cells:[Cell]}
        let detail:Detail,inside:Inside?
    }
    let entries:[String:Entry]
    init(data:Data)throws {
        guard data.count<=2*1024*1024,let document=try? JSONDecoder().decode(Document.self,from:data)else{throw Invalid.data}
        let detail=document.detail
        guard detail.cell==128,detail.columns==16,detail.sharp==256,detail.sharpColumns==8,
              !detail.cells.isEmpty,detail.cells.count<=256,(document.inside?.cells.count ?? 0)<=256 else{throw Invalid.profile}
        var entries:[String:Entry]=[:]
        for (prefix,rows) in [("c",detail.cells),("i",document.inside?.cells ?? [])] {
            for row in rows {
                let name=prefix+String(row.cell)
                guard (0..<256).contains(row.cell),(1...4096).contains(row.layers),
                      (0...NativeWorldSharpLayout.maximumLayers).contains(row.sharp),row.sharp<=row.layers,
                      entries[name]==nil else{throw Invalid.cell}
                entries[name]=Entry(name:name,layers:row.layers,sharpLayers:row.sharp)
            }
        }
        self.entries=entries
    }
}
