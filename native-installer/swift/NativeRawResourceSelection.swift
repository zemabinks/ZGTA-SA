// SPDX-License-Identifier: AGPL-3.0-only
import Foundation

/// Selection is deliberately about original raw resources, not native readiness.
/// Unknown converter coverage does not cause a raw asset to be discarded.
enum NativeRawResourceSelection {
    static func isGameResourcePath(_ path:String)->Bool {
        let parts=path.split(separator:"/",omittingEmptySubsequences:false)
        guard parts.count>=2,parts.allSatisfy({!$0.isEmpty && $0 != "." && $0 != ".."}),
              !path.contains("\\"),!path.contains(":"),
              ["anim","data","models","text","audio","movies"].contains(parts[0].lowercased()) else{return false}
        let ext=(String(parts.last!) as NSString).pathExtension.lowercased()
        return !["exe","dll","com","bat","cmd","msi","msp","sys","cab","hdr","scr","ps1","vbs","lnk","asi","ocx","cpl","drv"].contains(ext)
    }
}
