import Foundation
import CZGTAInstaller
@main struct InstallerLinkProbe {
    static func main(){
        let limits=zgta_installer_default_limits()
        print("Linked bounded extractor: \(limits.max_entries)")
        print(NativeRawResourceSelection.isGameResourcePath("audio/STREAMS/AA"))
    }
}
