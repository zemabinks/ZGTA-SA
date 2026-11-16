import Foundation

struct NativeSAMPAddress:Equatable {
    let host:String,port:UInt16
    init?(_ raw:String){
        let raw=raw.trimmingCharacters(in:.whitespacesAndNewlines)
        let value=raw.contains("://") ? raw:"samp://"+raw
        guard let parts=URLComponents(string:value),let scheme=parts.scheme?.lowercased(),["samp","omp","openmp"].contains(scheme),
              let host=parts.host,!host.isEmpty,host.utf8.count<=253,!host.contains(":"),
              host.unicodeScalars.allSatisfy({CharacterSet.alphanumerics.contains($0)||$0=="."||$0=="-"}),
              parts.user==nil,parts.password==nil,parts.query==nil,parts.fragment==nil,
              parts.path.isEmpty || parts.path=="/",let port=UInt16(exactly:parts.port ?? 7777),port>0 else{return nil}
        self.host=host;self.port=port
    }
    var display:String{"\(host):\(port)"}
}

enum NativeSAMPIdentity {
    static func installation(defaults:UserDefaults = .standard)->String {
        let key="nativeSAMP.installation"
        if let id=defaults.string(forKey:key),(1...64).contains(id.utf8.count),id.utf8.allSatisfy({(48...57).contains($0)||(65...70).contains($0)}){return id}
        let source=String(UUID().uuidString.replacingOccurrences(of:"-",with:"").prefix(20)).uppercased()
        let id=try!NativeSAMPProtocol.installationID(source:Data(source.utf8));defaults.set(id,forKey:key);return id
    }
}
