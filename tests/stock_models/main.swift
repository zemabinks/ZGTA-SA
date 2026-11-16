// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CryptoKit
typealias Stock=NativeSAMPStockModels
var checks=0
func check(_ value:@autoclosure()throws->Bool,_ message:String){checks+=1;do{if try !value(){fatalError("stock models: \(message)")}}catch{fatalError("stock models \(message): \(error)")}}
func fails(_ message:String,_ body:()throws->Void){do{try body();fatalError("expected stock failure \(message)")}catch{checks+=1}}
let synthetic=try Stock.decode(Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])))
let remote=URL(string:"http://127.0.0.1:8080/")!
let object=try synthetic.resolve(id:1000,assetBaseURL:remote)
check(object.model.model=="test_panel" && object.model.txd=="child" && object.allFilesAvailable,"exact object model and dictionary")
check(object.dff?.url.absoluteString=="http://127.0.0.1:8080/game/test_panel.dff","explicit asset URL prefix")
check(object.dictionaries.map(\.name)==["child","parent"] && object.textureSearch.map(\.name)==["child","parent"],"explicit TXD parent chain")
let vehicle=try synthetic.resolve(id:400,assetBaseURL:remote)
check(vehicle.model.model=="test_car" && vehicle.model.txd=="testdict","mixed whitespace/comma IDE row")
check(vehicle.dictionaries.map(\.name)==["testdict","vehicle"] && vehicle.textureSearch.map(\.name)==["vehicle","testdict"],"documented supporting generic-vehicle rule")
check(synthetic.model(1777)==nil,"inactive IDE is not guessed into catalog")
let missing=try synthetic.resolve(id:1001,assetBaseURL:remote)
check(missing.missingDFF=="missing_piece.dff" && missing.missingTXDs==["missing_dict.txd"] && !missing.allFilesAvailable,"explicit missing assets")
check(try synthetic.dictionary(named:"CHILD",assetBaseURL:remote).name=="child","RW dictionary case folding")
fails("unknown model"){_ = try synthetic.resolve(id:19379,assetBaseURL:remote)}
fails("credentialed base"){_ = try synthetic.resolve(id:1000,assetBaseURL:URL(string:"https://user:secret@example.com/")!)}
let malformed=try JSONDecoder().decode([String].self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2])))
for path in malformed{fails("malformed metadata"){_ = try Stock.decode(Data(contentsOf:URL(fileURLWithPath:path)))}}
var small=Stock.Limits();small.metadataBytes=1
fails("metadata bytes"){_ = try Stock.decode(Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])),limits:small)}
small=Stock.Limits();small.models=1
fails("model budget"){_ = try Stock.decode(Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])),limits:small)}
small=Stock.Limits();small.parentDepth=1
fails("parent depth"){_ = try Stock.decode(Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[1])),limits:small)}

let owned=try Stock.decode(Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[3])))
let local=URL(fileURLWithPath:CommandLine.arguments[4],isDirectory:true)
var verified=0
for id:Int32 in [331,371,400,411]{
 let value=try owned.resolve(id:id,assetBaseURL:local)
 check(value.dff != nil && value.allFilesAvailable,"actual owner raw mapping \(id)")
 for file in [value.dff!]+value.dictionaries.compactMap(\.file){
  let data=try Data(contentsOf:file.url)
  check(data.count==file.metadata.bytes,"actual owner file size")
  check(SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()==file.metadata.sha256,"actual owner file SHA256")
  verified+=1
 }
}
let gate=try owned.resolve(id:966,assetBaseURL:local)
check(gate.model.model=="bar_gatebar01" && gate.missingDFF=="bar_gatebar01.dff","actual missing retail gate named exactly")
check(owned.model(19379)==nil && owned.model(19353)==nil,"SA-MP supplemental IDs not fabricated from retail")
let report:[String:Any]=["status":"PASS","checks":checks,"retailModels":owned.count,"actualFilesVerified":verified,"scope":"exact metadata/local file resolution only; no native import/render claim"]
print(String(decoding:try JSONSerialization.data(withJSONObject:report,options:[.sortedKeys]),as:UTF8.self))
