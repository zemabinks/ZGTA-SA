// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Explicit snapshot of this app's own first-party LAN join cookie. Callers
/// must obtain sessionCookies from their configured app session, never browser,
/// WKWebsiteDataStore, original-game login or Discord cookie sources.
/// This value cannot authorize a different origin or an unrelated resource.
struct NativeStockAssetAccess {
    private static let preparedLock=NSLock()
    private static var preparedReader:((URL,Int)throws->Data?)?
    static func installPreparedReader(_ reader:@escaping(URL,Int)throws->Data?){preparedLock.lock();preparedReader=reader;preparedLock.unlock()}
    static func preparedData(for url:URL,maximumBytes:Int)throws->Data?{
        preparedLock.lock();let reader=preparedReader;preparedLock.unlock()
        return try reader?(url,maximumBytes)
    }
    private struct Origin:Equatable {
        let scheme,host:String
        let port:Int
        init?(_ url:URL) {
            guard let value=URLComponents(url:url,resolvingAgainstBaseURL:false),
                  let scheme=value.scheme?.lowercased(),["http","https"].contains(scheme),
                  let raw=value.host,!raw.isEmpty,value.user==nil,value.password==nil,
                  value.query==nil,value.fragment==nil else{return nil}
            let port=value.port ?? (scheme == "https" ? 443:80)
            guard (1...65535).contains(port) else{return nil}
            self.scheme=scheme;self.host=Self.host(raw);self.port=port
        }
        static func host(_ value:String)->String {
            let result=value.lowercased()
            return result.hasPrefix("[") && result.hasSuffix("]") ? String(result.dropFirst().dropLast()):result
        }
    }
    private struct Cookie {
        let value,path:String
        let expires:Date?
        let secure:Bool
        let ports:Set<Int>?
    }
    private let origin:Origin,cookies:[Cookie]
    init?(assetOrigin:URL,sessionCookies:[HTTPCookie]) {
        guard let origin=Origin(assetOrigin) else{return nil}
        self.origin=origin
        var accepted:[Cookie]=[]
        // Only this name is even inspected; unrelated session values are not
        // retained or forwarded. The server's join token is exactly64 hex bytes.
        for item in sessionCookies where item.name == "zgta_access" {
            guard item.value.utf8.count==64,item.value.utf8.allSatisfy({(48...57).contains($0)||(97...102).contains($0)}) else{continue}
            let domain=item.domain.hasPrefix(".") ? String(item.domain.dropFirst()):item.domain
            // Deliberately narrower than broad Domain-cookie suffix matching:
            // a parent/subdomain cookie cannot become asset-host authority.
            guard Origin.host(domain)==origin.host,item.path.hasPrefix("/"),item.path.utf8.count<=1024 else{continue}
            if let source=item.properties?[.originURL] {
                let url=(source as? URL) ?? (source as? String).flatMap(URL.init(string:))
                guard let url,Origin(url)==origin else{continue}
            }
            if let expires=item.expiresDate,!expires.timeIntervalSinceReferenceDate.isFinite {continue}
            // Foundation returns [] for portList even when no Port attribute
            // exists. Only an explicit attribute restricts this exact origin.
            let ports:Set<Int>?
            if item.properties?[.port] != nil {
                guard let list=item.portList,!list.isEmpty else{continue}
                let values=Set(list.map{Int(truncating:$0)})
                guard values.allSatisfy({(1...65535).contains($0)}) else{continue}
                ports=values
            } else {ports=nil}
            accepted.append(Cookie(value:item.value,path:item.path,expires:item.expiresDate,secure:item.isSecure,ports:ports))
        }
        self.cookies=accepted
    }
    func cookieHeader(for requestURL:URL,at now:Date=Date())->String? {
        guard now.timeIntervalSinceReferenceDate.isFinite,Origin(requestURL)==origin,
              let components=URLComponents(url:requestURL,resolvingAgainstBaseURL:false),
              Self.stockPath(components.percentEncodedPath) else{return nil}
        let path=components.percentEncodedPath
        let values=Set(cookies.filter { cookie in
            if cookie.secure && origin.scheme != "https" {return false}
            if let expires=cookie.expires,expires<=now {return false}
            if let ports=cookie.ports,!ports.contains(origin.port) {return false}
            return path==cookie.path || (path.hasPrefix(cookie.path) &&
                (cookie.path.hasSuffix("/") || path.dropFirst(cookie.path.count).first == "/"))
        }.map{$0.value})
        // Two different eligible values are an ambiguous login snapshot. Do not
        // choose whichever a cookie-store enumeration happened to return first.
        guard values.count==1,let value=values.first else{return nil}
        return "zgta_access="+value
    }
    private static func stockPath(_ value:String)->Bool {
        let cjPrefix="/game/native/cj-normal-vest-denim-v1/"
        if value.hasPrefix(cjPrefix) {
            return ["profile.json","player.dff","vest.dff","head.dff","hands.dff","jeans.dff","sneaker.dff",
                "player_torso.txd","vest.txd","player_face.txd","jeansdenim.txd","sneakerbincblk.txd","clothes.dat"].contains(String(value.dropFirst(cjPrefix.count)))
        }
        if ["/game/native/stock-models.json","/game/native/stock-collision/catalog.json","/game/native/stock-collision/index.json"].contains(value) {return true}
        let prefix:String,suffix:String
        if value.hasPrefix("/game/native/stock-img/") {
            prefix="/game/native/stock-img/"
            guard value.hasSuffix(".dff") || value.hasSuffix(".txd") else{return false}
            suffix=String(value.suffix(4))
        } else if value.hasPrefix("/game/native/stock-collision/") {
            prefix="/game/native/stock-collision/";suffix=".col"
            guard value.hasSuffix(suffix) else{return false}
        } else{return false}
        let digest=value.dropFirst(prefix.count).dropLast(suffix.count)
        return digest.utf8.count==64 && digest.utf8.allSatisfy{(48...57).contains($0)||(97...102).contains($0)}
    }
}
