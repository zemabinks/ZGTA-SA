// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

var checks=0
func require(_ value:Bool,_ label:String) { checks+=1;precondition(value,"stock access: "+label) }
let origin=URL(string:"http://assets.example:8876")!
let target=URL(string:"http://assets.example:8876/game/native/stock-models.json")!
let now=Date(),token=String(repeating:"a",count:64)
func cookie(_ name:String="zgta_access",value:String=token,domain:String="assets.example",path:String="/",
            expires:Date?=nil,secure:Bool=false,port:String?=nil,source:URL?=nil)->HTTPCookie {
    var properties:[HTTPCookiePropertyKey:Any]=[.name:name,.value:value,.domain:domain,.path:path]
    if let expires {properties[.expires]=expires}
    if secure {properties[.secure]="TRUE"}
    if let port {properties[.port]=port}
    if let source {properties[.originURL]=source}
    return HTTPCookie(properties:properties)!
}
func header(_ cookies:[HTTPCookie],url:URL=target,base:URL=origin,at:Date=now)->String? {
    NativeStockAssetAccess(assetOrigin:base,sessionCookies:cookies)?.cookieHeader(for:url,at:at)
}
let valid=cookie(expires:now.addingTimeInterval(60))
require(header([valid])=="zgta_access="+token,"one own app access token")
require(header([cookie("zgta_local",value:"private-profile"),cookie("discord_session",value:"private-discord"),valid])=="zgta_access="+token,"only exact cookie name forwarded")
require(header([cookie("zgta_local",value:"private-profile"),cookie("discord_session",value:"private-discord")])==nil,"unrelated values cannot authorize")
for url in ["http://another.example:8876/game/native/stock-models.json","http://assets.example:8877/game/native/stock-models.json",
            "https://assets.example:8876/game/native/stock-models.json","http://user:secret@assets.example:8876/game/native/stock-models.json",
            "http://assets.example:8876/game/native/stock-models.json?alias=1","http://assets.example:8876/game/native/stock-models.json#fragment",
            "file:///game/native/stock-models.json","/game/native/stock-models.json"] {
    require(header([valid],url:URL(string:url)!)==nil,"request origin/credentials/query exactness")
}
for path in ["/api/local/status","/game/world/index.json","/game/native/stock-collision/private.json",
             "/game/native/stock-img/other.dff","/game/native/stock-img/"+String(repeating:"G",count:64)+".dff",
             "/%67ame/native/stock-models.json","/game/native/stock-collision/../stock-models.json"] {
    require(header([valid],url:URL(string:"http://assets.example:8876"+path)!)==nil,"unrelated/aliased path cannot receive access")
}
for path in ["/game/native/stock-collision/catalog.json","/game/native/stock-collision/index.json",
             "/game/native/stock-img/"+token+".dff","/game/native/stock-img/"+token+".txd","/game/native/stock-collision/"+token+".col"] {
    require(header([valid],url:URL(string:"http://assets.example:8876"+path)!) != nil,"exact stock path accepts explicit policy")
}
require(header([cookie(domain:"play.samp.directory")])==nil,"original game cookie never forwarded")
require(header([cookie(domain:"sub.assets.example")])==nil,"subdomain mismatch")
require(header([cookie(domain:".example")])==nil,"parent-domain cookie not promoted")
require(header([cookie(domain:".ASSETS.EXAMPLE")]) != nil,"exact host leading-dot domain")
require(header([cookie(path:"/api")])==nil,"cookie path mismatch")
require(header([cookie(path:"/game/native/stock")])==nil,"cookie path boundary")
require(header([cookie(path:"/game/native")]) != nil,"cookie directory path boundary")
require(header([cookie(expires:now.addingTimeInterval(-1))])==nil,"expired snapshot")
require(header([valid],at:now.addingTimeInterval(61))==nil,"expiry rechecked at each request")
require(header([cookie(secure:true)])==nil,"Secure token cannot travel over HTTP")
let https=URL(string:"https://assets.example")!
require(header([cookie(secure:true)],url:URL(string:"https://assets.example:443/game/native/stock-models.json")!,base:https) != nil,"Secure HTTPS default port equivalent")
require(header([cookie(port:"8877")])==nil,"cookie port restriction")
require(header([cookie(port:"8876")]) != nil,"matching cookie port restriction")
// Foundation does not retain OriginURL in cookie.properties. The explicit
// app-session snapshot origin is the provenance policy; request ports above
// are still checked independently, without guessing missing cookie metadata.
require(header([valid,cookie(value:String(repeating:"b",count:64))])==nil,"conflicting eligible tokens fail closed")
require(header([valid,cookie(path:"/game/native")])=="zgta_access="+token,"same value emitted once")
for value in ["",String(repeating:"a",count:63),String(repeating:"A",count:64),token+"; zgta_local=private"] {
    require(header([cookie(value:value)])==nil,"invalid token cannot become a header")
}
require(NativeStockAssetAccess(assetOrigin:URL(string:"file:///private")!,sessionCookies:[valid])==nil,"nonHTTP policy rejected")
require(NativeStockAssetAccess(assetOrigin:URL(string:"http://user@assets.example:8876")!,sessionCookies:[valid])==nil,"credential origin rejected")
print("{\"status\":\"PASS\",\"checks\":\(checks)}")
