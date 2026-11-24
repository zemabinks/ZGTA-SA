// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import Darwin
import CZGTAInstaller

/// Synchronous worker API. The caller retains any Files security scope and
/// dispatches work off the UI thread. One operation at a time per instance.
/// Produces staged original bytes only, never a playable native installation.
final class NativeISOExtraction {
    struct Entry:Equatable {
        enum Source:Int32 {case cabinet=1,looseISO=2}
        let index:Int,path:String,group:String,bytes:UInt64,source:Source
    }
    struct Progress {let path:String;let completedBytes:UInt64,totalBytes:UInt64;let completedFiles:UInt32,totalFiles:UInt32}
    struct Statistics {let isoBytesRead:UInt64,outputBytesWritten:UInt64,maximumReadRequest:UInt64}
    enum Failure:LocalizedError {
        case invalid(String),cancelled
        var errorDescription:String? {switch self{case .invalid(let message):return message;case .cancelled:return "Raw resource extraction cancelled. The active installation was not changed."}}
    }
    final class Cancellation {
        private let lock=NSLock();private var stopped=false
        var isCancelled:Bool {lock.lock();defer{lock.unlock()};return stopped}
        func cancel(){lock.lock();stopped=true;lock.unlock()}
    }
    fileprivate final class Context {
        let cancellation:Cancellation
        var progress:((Progress)->Void)?
        init(_ cancellation:Cancellation){self.cancellation=cancellation}
    }
    private let handle:OpaquePointer,context:Context
    let entries:[Entry]
    let cancellation:Cancellation
    static func withCoordinatedRead<T>(of url: URL, _ read: (URL) throws -> T) throws -> T {
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        var error: NSError?
        var result: Result<T, Error>?
        NSFileCoordinator().coordinate(readingItemAt: url, options: .withoutChanges, error: &error) { file in
            result = Result { try read(file) }
        }
        if let result { return try result.get() }
        throw error ?? CocoaError(.fileReadUnknown)
    }

    init(source:URL,limits:zgta_installer_limits=zgta_installer_default_limits(),cancellation:Cancellation=Cancellation())throws{
        guard source.isFileURL else{throw Failure.invalid("Select a local original ISO file.")}
        self.cancellation=cancellation;let context=Context(cancellation);self.context=context
        var limits=limits,error=[CChar](repeating:0,count:512)
        let opened=source.resolvingSymlinksInPath().path.withCString{path in
            zgta_installer_open_iso(path,&limits,nativeISOIsCancelled,Unmanaged.passUnretained(context).toOpaque(),&error,error.count)
        }
        guard let opened else{if cancellation.isCancelled{throw Failure.cancelled};throw Failure.invalid(String(cString:error))}
        handle=opened
        var catalogue:[Entry]=[]
        for index in 0..<zgta_installer_entry_count(opened){
            var value=zgta_installer_entry()
            guard zgta_installer_get_entry(opened,index,&value)==1,let path=value.path,let group=value.group,let source=Entry.Source(rawValue:Int32(value.source)) else{
                zgta_installer_close(opened);throw Failure.invalid("Installer returned an invalid resource catalogue.")
            }
            catalogue.append(Entry(index:Int(index),path:String(cString:path),group:String(cString:group),bytes:value.bytes,source:source))
        }
        entries=catalogue
    }
    deinit{zgta_installer_close(handle)}
    var statistics:Statistics {
        let value=zgta_installer_stats(handle)
        return Statistics(isoBytesRead:value.iso_bytes_read,outputBytesWritten:value.output_bytes_written,maximumReadRequest:value.max_read_request)
    }
    /// Includes all recognized game-resource roots, including assets whose native
    /// converter is pending. It excludes installer/Windows/HOODLUM payloads.
    func gameResources()throws->[Entry]{
        let resources=entries.filter{NativeRawResourceSelection.isGameResourcePath($0.path)}
        var identities=Set<String>()
        for entry in resources where !identities.insert(entry.path.lowercased()).inserted {
            throw Failure.invalid("Ambiguous original resource destination: \(entry.path)")
        }
        guard !resources.isEmpty else{throw Failure.invalid("The ISO contains no recognized original game resources.")}
        return resources
    }
    func extractGameResources(to newStage:URL,progress:((Progress)->Void)?=nil)throws{
        try extract(indices:try gameResources().map(\.index),to:newStage,progress:progress)
    }
    func extract(indices:[Int],to newStage:URL,progress:((Progress)->Void)?=nil)throws{
        guard newStage.isFileURL,!indices.isEmpty,indices.count<=Int(UInt32.max),indices.allSatisfy({$0>=0 && $0<entries.count}) else{throw Failure.invalid("Choose valid catalogue entries and a new app-owned staging folder.")}
        // Resolve only the parent; never follow an existing final destination.
        // Foundation may normalize /private/var back to /var, while the C
        // descriptor API requires libc's canonical spelling on Apple platforms.
        let parent = newStage.deletingLastPathComponent().path
        guard let canonical = realpath(parent, nil) else { throw Failure.invalid("The app staging directory could not be resolved.") }
        defer { free(canonical) }
        let resolved = String(cString: canonical)
        guard resolved == parent || (parent.hasPrefix("/var/") && resolved == "/private" + parent) else {
            throw Failure.invalid("Staging requires an app-owned directory without symlinked ancestors.")
        }
        let destination = resolved + "/" + newStage.lastPathComponent
        let selected=indices.map(UInt32.init);context.progress=progress;defer{context.progress=nil}
        let status=destination.withCString{path in selected.withUnsafeBufferPointer{values in
            zgta_installer_extract(handle,values.baseAddress,UInt32(values.count),path,nativeISOExtractionProgress,Unmanaged.passUnretained(context).toOpaque())
        }}
        if status==ZGTA_INSTALLER_CANCELLED{throw Failure.cancelled}
        guard status==ZGTA_INSTALLER_OK else{throw Failure.invalid(String(cString:zgta_installer_error(handle)))}
    }
    func cancel(){cancellation.cancel();zgta_installer_cancel(handle)}
}
private func nativeISOIsCancelled(_ context:UnsafeMutableRawPointer?)->Int32{
    guard let context else{return 1}
    return Unmanaged<NativeISOExtraction.Context>.fromOpaque(context).takeUnretainedValue().cancellation.isCancelled ? 1:0
}
private func nativeISOExtractionProgress(_ context:UnsafeMutableRawPointer?,_ path:UnsafePointer<CChar>?,_ completed:UInt64,_ total:UInt64,_ files:UInt32,_ count:UInt32){
    guard let context,let path else{return}
    let box=Unmanaged<NativeISOExtraction.Context>.fromOpaque(context).takeUnretainedValue()
    box.progress?(.init(path:String(cString:path),completedBytes:completed,totalBytes:total,completedFiles:files,totalFiles:count))
}
