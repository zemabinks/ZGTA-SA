// SPDX-License-Identifier: Apache-2.0
// Swift adaptation of SA-MP-Pilot huffman.go aa8c7971d2f3c8762a9f20c9ef35b42d5927a768.
// Copyright2026 SA-MP Android. Apache LICENSE/NOTICE retained in native-samp.
// Modified: bounded Swift Reader integration and native Foundation text codecs.
import Foundation
import CoreFoundation

enum NativeSAMPTextCodec {
    enum Encoding:String,CaseIterable {case utf8,windows1252,windows1251,gbk
        var foundation:String.Encoding {
            switch self {
            case .utf8:return .utf8
            case .windows1252:return .windowsCP1252
            case .windows1251:return .windowsCP1251
            case .gbk:return String.Encoding(rawValue:CFStringConvertEncodingToNSStringEncoding(CFStringConvertWindowsCodepageToEncoding(936)))
            }
        }
    }
    static func decode(_ bytes:Data,encoding:Encoding = .windows1252)->String {
        let bytes=Data(bytes.prefix(while:{$0 != 0}))
        if let utf8=String(data:bytes,encoding:.utf8){return utf8}
        return String(data:bytes,encoding:encoding.foundation) ?? String(decoding:bytes,as:UTF8.self)
    }
    static func encode(_ text:String,encoding:Encoding = .windows1252,maxBytes:Int=255)throws->Data {
        guard !text.contains("\u{0000}"),let bytes=text.data(using:encoding.foundation,allowLossyConversion:false),bytes.count<=maxBytes else{throw NativeSAMPProtocol.Error.invalid}
        return bytes
    }
    static func stripColors(_ text:String)->String {
        text.replacingOccurrences(of:"\\{[0-9a-fA-F]{6}\\}",with:"",options:.regularExpression)
    }
    private struct Node {let weight:UInt32,value:UInt8?,left:Int?,right:Int?}
    private static let frequencies:[UInt32]=[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 722, 0, 0, 2, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 11084, 58, 63, 1, 0, 31, 0, 317, 64, 64, 44, 0, 695, 62, 980, 266, 69, 67, 56, 7, 73, 3, 14, 2, 69, 1, 167, 9, 1, 2, 25, 94, 0, 195, 139, 34, 96, 48, 103, 56, 125, 653, 21, 5, 23, 64, 85, 44, 34, 7, 92, 76, 147, 12, 14, 57, 15, 39, 15, 1, 1, 1, 2, 3, 0, 3611, 845, 1077, 1884, 5870, 841, 1057, 2501, 3212, 164, 531, 2019, 1330, 3056, 4037, 848, 47, 2586, 2919, 4771, 1707, 535, 1106, 152, 1243, 100, 0, 2, 0, 10]
    private static let tree:([Node],Int) = {
        var nodes=[Node](),pending=[Int]()
        func insert(_ node:Node){
            let id=nodes.count;nodes.append(node);var at=0
            while at<pending.count && nodes[pending[at]].weight<node.weight{at+=1}
            pending.insert(id,at:at)
        }
        for i in 0..<256{let weight=i<frequencies.count ? frequencies[i]:0;insert(Node(weight:max(1,weight),value:UInt8(i),left:nil,right:nil))}
        while pending.count>1 {
            let left=pending.removeFirst(),right=pending.removeFirst()
            insert(Node(weight:nodes[left].weight+nodes[right].weight,value:nil,left:left,right:right))
        }
        return (nodes,pending[0])
    }()
    static func compressed(_ reader:inout NativeSAMPProtocol.Reader,maxBytes:Int=4096)throws->Data {
        guard (0...65535).contains(maxBytes)else{throw NativeSAMPProtocol.Error.invalid}
        let count=Int(try reader.compressed(2));guard count<=reader.remaining else{throw NativeSAMPProtocol.Error.truncated}
        var node=tree.1,result=Data()
        for _ in 0..<count {
            let bit=try reader.bit()
            guard let next=bit ? tree.0[node].right:tree.0[node].left else{throw NativeSAMPProtocol.Error.invalid}
            node=next
            if let value=tree.0[node].value {
                guard result.count<maxBytes else{throw NativeSAMPProtocol.Error.invalid}
                result.append(value);node=tree.1
            }
        }
        // The protocol's padded suffix may finish within a code; it is not a
        // decoded extra character. This follows the actual C++/Pilot fixture.
        return result
    }
}
