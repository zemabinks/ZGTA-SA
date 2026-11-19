// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CryptoKit

// Type-only dependencies absent from this transport target. The production
// format/Metal verifier is deliberately unavailable; no engine is substituted.
enum NativePreparedRuntimeVerifier {
    static let identity="unavailable-engine-verifier-in-loader-target"
    static func validate(_ m:NativeResourceManifest,_ r:@escaping(String)throws->URL)throws {throw TestFailure.failed("engine verifier unavailable")}
}
enum NativeSAMPStockAssetLoader {enum Failure:Error {case invalidURL,cancelled,encoding,redirect,http(Int),limit(String)}}
private enum TestFailure:Error {case failed(String)}
private final class Wire:URLProtocol {
    static let lock=NSLock();static var requests:[String]=[];static var data:[String:Data]=[:]
    override class func canInit(with request:URLRequest)->Bool {true}
    override class func canonicalRequest(for request:URLRequest)->URLRequest {request}
    override func startLoading(){
        let key=request.url!.path
        Self.lock.lock();Self.requests.append(key);let body=Self.data[key] ?? Data("authored-network-response".utf8);Self.lock.unlock()
        client?.urlProtocol(self,didReceive:HTTPURLResponse(url:request.url!,statusCode:200,httpVersion:nil,headerFields:["Content-Length":String(body.count)])!,cacheStoragePolicy:.notAllowed)
        client?.urlProtocol(self,didLoad:body);client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading(){}
    static var count:Int {lock.lock();defer{lock.unlock()};return requests.count}
}
@main private struct LoaderRegression {
    static var checks=0
    static func check(_ value:Bool,_ label:String)throws {checks+=1;if !value{throw TestFailure.failed(label)}}
    static func wait(_ condition:()->Bool)throws {
        let end=Date().addingTimeInterval(8)
        while !condition(),Date()<end{RunLoop.current.run(until:Date().addingTimeInterval(0.01))}
        try check(condition(),"bounded callback completed")
    }
    static func json(_ value:Any)throws->Data {try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys])}
    static func hash(_ data:Data)->String {SHA256.hash(data:data).map{String(format:"%02x",$0)}.joined()}
    static func fixture(_ base:URL)throws->(NativeResourceStore,[String:Data],NativeResourceManifest) {
        let f=FileManager.default;try f.createDirectory(at:base,withIntermediateDirectories:true)
        let color21=Array(repeating:Array(repeating:Array(repeating:0.0,count:21),count:8),count:23)
        let color12=Array(repeating:Array(repeating:Array(repeating:0.0,count:12),count:8),count:23)
        var constants:[String:Any]=[:]
        for key in ["y_","yN","yz","w$","wJ","wQ"]{constants[key]=[1.0]}
        constants["yS"]=Array(repeating:0.0,count:8)
        for key in ["yC","yE","yR"]{constants[key]=Array(repeating:0.0,count:9)}
        constants["yO"]=Array(repeating:[0.0,0.0,0.0],count:12);constants["wY"]=Array(repeating:[0.0,0.0,0.0],count:6)
        let hours=(0..<8).map{Double($0*3)}
        var data:[String:Data]=[:]
        for path in NativeResourceManifest.requiredPaths {
            data[path]=path.hasSuffix(".json") ? try json(["authoredTransportFixture":path]):Data("authored-transport-fixture".utf8)
        }
        // Bootstrap requires a world geometry/atlas pair. These are transport
        // markers under a synthetic validator, not engine-format fixtures.
        data["game/world/authored.bin"]=Data("authored-world-transport-body".utf8)
        data["game/world/authored.png"]=Data("authored-atlas-transport-body".utf8)
        let profiles=Dictionary(uniqueKeysWithValues:["car","bike","heli","plane"].map{($0,Array(repeating:1.0,count:15))})
        let distances=Dictionary(uniqueKeysWithValues:["car","bike","heli","plane"].map{($0,[1.0,2.0,3.0])})
        let sights=Dictionary(uniqueKeysWithValues:["scope","camera","rocket"].map{($0,["first":1.0,"least":1.0,"most":2.0])})
        data["game/native/camera.json"]=try json(["vehicleProfiles":profiles,"vehicleDistances":distances,"vehicleAngles":distances,"cinematic":["ground":[1,2,3,4],"air":[1,2,3,4]],"footDistances":[1,2,3],"footSights":sights,"footWeaponFov":[[1,2]],"weaponSights":[String:String]()] as [String:Any])
        data["game/native/atmosphere.json"]=try json(["hours":hours,"colors":color21,"wind":Array(repeating:1.0,count:23),"constants":constants,"sheets":Array(repeating:["spot":[0.0,0,0,0],"span":[0.0,0,0]],count:58),"highClouds":Array(repeating:["home":[0.0,0,0],"girth":[0.0,0,0],"density":0.0]as[String:Any],count:180)] as [String:Any])
        data["game/native/water-waves.json"]=try json(["regions":[[Double]](),"xFactors":Array(repeating:1.0,count:8),"yFactors":Array(repeating:1.0,count:8),"wind":Array(repeating:1.0,count:23),"components":Array(repeating:[1.0,0,0,0],count:3)] as [String:Any])
        data["game/native/environment.json"]=try json(["hours":hours,"colors":color12,"weatherNames":(0..<23).map{"authored-\($0)"},"sequences":Dictionary(uniqueKeysWithValues:["la","sf","lv","desert","country"].map{($0,[0,1])})] as [String:Any])
        // Only the bounded byte-transfer stage is under test, not stock JSON
        // catalogue decoding. These stock bytes are plainly synthetic markers.
        data["game/native/stock-models.json"]=try json(["authoredFixture":"stock-models"])
        let entries=data.map{NativeResourceManifest.Resource(path:$0.key,bytes:Int64($0.value.count),sha256:hash($0.value),required:true)}
        let interim=NativeResourceManifest(schema:1,profile:NativeResourceManifest.profileName,contentID:String(repeating:"0",count:64),resources:entries)
        let manifest=NativeResourceManifest(schema:1,profile:interim.profile,contentID:interim.identity,resources:entries)
        let folder=base.appendingPathComponent("package"),blobs=folder.appendingPathComponent("blobs")
        try f.createDirectory(at:blobs,withIntermediateDirectories:true)
        for (path,value)in data {try value.write(to:blobs.appendingPathComponent(entries.first{$0.path==path}!.sha256))}
        try JSONEncoder().encode(manifest).write(to:folder.appendingPathComponent(NativeResourceManifest.filename))
        let store=NativeResourceStore(root:base.appendingPathComponent("store"),validationIdentity:"synthetic-loader-transport-v1",runtimeValidator:{m,resolve in
            for path in NativeResourceManifest.requiredPaths {guard try Data(contentsOf:resolve(path))==data[path] else{throw TestFailure.failed("synthetic validator")}}
        })
        var imported:Result<NativeResourceStore.Snapshot,Error>?
        store.importPreparedFolder(folder,progress:{_ in},completion:{imported=$0})
        try wait{imported != nil};_ = try imported!.get();try store.setMode(.installed)
        return(store,data,manifest)
    }
    static func main()throws {
        guard CommandLine.arguments.count==2 else{throw TestFailure.failed("private output root required")}
        let root=URL(fileURLWithPath:CommandLine.arguments[1],isDirectory:true)
        let (store,data,manifest)=try fixture(root)
        let configuration=URLSessionConfiguration.ephemeral;configuration.protocolClasses=[Wire.self];configuration.httpCookieStorage=nil;configuration.urlCredentialStorage=nil
        let network=URLSession(configuration:configuration);defer{network.invalidateAndCancel()}
        Wire.data=Dictionary(uniqueKeysWithValues:data.map{("/"+$0.key,$0.value)})
        let session=NativeResourceSession(store:store,network:network)
        var localRequests:[String]=[],resourceErrors=0
        NativeResourceTransport.install({request,completion in
            localRequests.append(request.url!.path)
            return session.dataTask(with:request){d,r,e in if e != nil{resourceErrors+=1};completion(d,r,e)}
        },localFile:{try store.installedURL(for:$0)})
        NativeStockAssetAccess.installPreparedReader{try store.localResource(for:$0,maximumBytes:Int64($1))?.0}
        let server=ServerAddress("http://127.0.0.1:65534")!
        let camera=NativeGameCamera(persistViews:false),secondCamera=NativeGameCamera(persistViews:false)
        let atmosphere=NativeAtmosphere(),water=NativeWaterWaves(),weather=NativeRegionalWeather(),environment=NativeWorldEnvironment()
        var loaded=0
        camera.load(server:server){loaded+=1};secondCamera.load(server:server){loaded+=1}
        atmosphere.load(server:server){loaded+=1};water.load(server:server){loaded+=1};weather.load(server:server){loaded+=1};environment.load(server:server){loaded+=1}
        try wait{loaded==6};try check(Wire.count==0,"all six static loader invocations stay installed-local")
        try check(atmosphere.isLoaded && water.isLoaded && environment.isLoaded,"real authored loader tables accepted")
        try check(localRequests.filter{$0=="/game/native/camera.json"}.count==2,"both camera instances use resolver")
        try check(Set(localRequests)==Set(["/game/native/camera.json","/game/native/atmosphere.json","/game/native/water-waves.json","/game/native/environment.json"]),"all affected static paths use resolver")
        func metadata(_ path:String,maximum:Int=16*1024*1024)throws->Result<Data,Error> {
            var result:Result<Data,Error>?;let transfer=LegacyStockMetadataTransfer(url:server.path(path),maximumBytes:maximum){result=$0}
            transfer.start();try wait{result != nil};return result!
        }
        let known=try metadata("game/native/stock-models.json");try check(try known.get()==data["game/native/stock-models.json"],"stock metadata returns verified installed bytes")
        switch try metadata("game/native/stock-collision/catalog.json"){case .success:try check(false,"missing catalog must fail closed");case .failure:try check(true,"missing catalog fails closed")}
        switch try metadata("game/native/stock-models.json",maximum:2){case .success:try check(false,"metadata byte budget");case .failure:try check(true,"metadata byte budget enforced by actual Store")}
        try check(Wire.count==0,"known/missing/oversized installed metadata never uses network")
        var apiDone=false,apiOK=false
        session.dataTask(with:server.path("api/local/state")){d,_,e in apiOK=d==Data("authored-network-response".utf8)&&e==nil;apiDone=true}.resume()
        try wait{apiDone};try check(apiOK && Wire.count==1,"ordinary gameplay API stays on supplied network")
        try store.setMode(.development)
        // Imported folders have no bound development origin, so they must not
        // silently serve their cached copy as another development server.
        let before=Wire.count;var developmentDone=false
        session.dataTask(with:server.path("game/native/camera.json")){d,_,e in developmentDone=d==data["game/native/camera.json"]&&e==nil}.resume()
        try wait{developmentDone};try check(Wire.count==before+1,"unbound development origin retains normal streaming")
        try store.setMode(.installed)
        let cameraEntry=manifest.resources.first{$0.path=="game/native/camera.json"}!
        try Data(repeating:0,count:Int(cameraEntry.bytes)).write(to:root.appendingPathComponent("store/blobs/"+cameraEntry.sha256))
        let corruptBefore=Wire.count;var corruptDone=false
        session.dataTask(with:server.path("game/native/camera.json")){d,_,e in corruptDone=d==nil&&e != nil}.resume()
        try wait{corruptDone};try check(Wire.count==corruptBefore,"corrupt installed metadata does not stream replacement")
        try check(resourceErrors==0,"successful loader phase had no hidden resource failure")
        let report:[String:Any]=["status":"PASS","checks":checks,"source":"actual immutable loader/Store/Session and metadata-transfer source","installedLoaderCallbacks":loaded,"networkRequests":Wire.count,"limits":["Authored fixtures and explicitly synthetic runtime validator; not engine/playability acceptance.","No actual HTTP server/device/UI/App-data action. Network fallback uses URLProtocol injected into the actual ResourceSession.","Stock development HTTP sink is source-unchanged; this target certifies only its installed prepared-read boundary.","Original107 seven-denial request result remains separate; no109 rendered denial rerun is claimed."]]
        try json(report).write(to:root.appendingPathComponent("report.json"));print("NATIVE_RESOURCE_LOADERS_PASS checks=\(checks)")
    }
}
