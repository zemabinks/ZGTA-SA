import Foundation
@main struct GameSourceSmoke {
    static func main()throws {
        var checks=0
        func check(_ value:Bool,_ message:String){checks+=1;precondition(value,message)}
        let folder=URL(fileURLWithPath:CommandLine.arguments[1])
        let cases=try JSONSerialization.jsonObject(with:Data(contentsOf:folder.appendingPathComponent("cases.json"))) as! [[String:Any]]
        for fixture in cases {
            let name=fixture["name"] as! String,url=folder.appendingPathComponent(name+".iso")
            do {
                let report=try NativeGameSourceInspector.inspectISO(url)
                check(fixture["reject"] as? Bool != true,"Malformed ISO accepted: \(name)")
                check(report.installShieldCandidate==(fixture["candidate"] as! Bool),"Candidate classification differed: \(name)")
                check(report.files.count==(fixture["files"] as! Int),"File count differed: \(name)")
                check(report.detail.contains("has not installed playable resources"),"Inspection implied installation")
            }catch {
                check(fixture["reject"] as? Bool == true,"Valid ISO rejected: \(name): \(error)")
            }
        }
        do {_ = try NativeGameSourceInspector.inspectISO(folder.appendingPathComponent("valid.iso"),cancelled:{true});preconditionFailure("Cancellation ignored")}
        catch NativeGameSourceInspector.InspectionError.cancelled {checks+=1}
        catch {preconditionFailure("Cancellation returned another error: \(error)")}
        if CommandLine.arguments.count>2 {
            let source=URL(fileURLWithPath:CommandLine.arguments[2])
            let report=try NativeGameSourceInspector.inspectISO(source)
            check(report.installShieldCandidate,"Owner ISO did not contain expected installer filename set")
            check(!report.files.isEmpty,"Owner ISO index empty")
            let output:[String:Any]=["scope":"Read-only actual owner ISO metadata inspection, not extraction/conversion/edition or gameplay verification","volume":report.volume,"fileCount":report.files.count,"installShieldFilenameCandidate":report.installShieldCandidate,"files":report.files.map{["path":$0.path,"bytes":$0.bytes]}]
            let data=try JSONSerialization.data(withJSONObject:output,options:[.prettyPrinted,.sortedKeys]);try data.write(to:folder.appendingPathComponent("owner-iso-report.json"))
            print("Owner ISO metadata: \(report.files.count) files, installer filename candidate; preparation remains required")
        }
        print("PASS native ISO9660 source inspection: \(checks) checks; bounded synthetic valid/malformed/cancel cases; no source writes")
    }
}
