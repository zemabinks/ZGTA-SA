// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

@main struct StockIMGManifestRegression {
    static func main() throws {
        var checks=0,ownerModels=0
        func require(_ value:Bool) { checks+=1;precondition(value,"virtual stock manifest regression") }
        let base=URL(string:"http://127.0.0.1:7793")!
        let generated=try NativeSAMPStockModels.decode(Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
        require(generated.count == 2)
        let missing=try generated.resolve(id:1000,assetBaseURL:base)
        require(missing.missingDFF == nil && missing.missingTXDs == ["child.txd"])
        let available=try generated.resolve(id:1001,assetBaseURL:base)
        require(available.allFilesAvailable && available.dff!.url.path.hasPrefix("/game/native/stock-img/"))
        require(available.dff!.url.lastPathComponent == available.dff!.metadata.sha256+".dff")
        if CommandLine.arguments.count>2,CommandLine.arguments[2] != "-" {
            let owner=try NativeSAMPStockModels.decode(Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2])))
            ownerModels=owner.count;require(owner.count>14_000)
            for id:Int32 in [966,980,1225,1231] {
                let value=try owner.resolve(id:id,assetBaseURL:base)
                require(value.allFilesAvailable)
                require(value.dff!.url.path.hasPrefix("/game/native/stock-img/"))
            }
            for name in ["barrier","changeme","kbmiscfrn1","lawest1"] {
                require(try owner.dictionary(named:name,assetBaseURL:base).file == nil)
            }
            require(owner.model(19379) == nil)
        }
        print("{\"status\":\"PASS\",\"checks\":\(checks),\"ownerModels\":\(ownerModels)}")
    }
}
