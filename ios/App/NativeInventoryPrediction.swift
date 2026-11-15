import Foundation
import CoreFoundation

/// An acknowledgement is captured atomically with every server snapshot. The
/// authoritative baseline and unacknowledged local emissions remain separate;
/// revision alone cannot identify which predicted rounds the server handled.
final class NativeInventoryPrediction {
    struct Rounds: Equatable {var clip:Int;var reserve:Int}
    struct Snapshot {
        var connection:String
        var processedShot:Int
        var revision:Int
        var selected:Int
        var reloading:Bool
        var weapons:[Int:Rounds]
    }
    struct Pending:Equatable {var sequence:Int;var weapon:Int;var at:Double}
    enum Result:Equatable {case applied,wrongConnection,staleRevision,staleAcknowledgement,invalid}
    private(set) var connection:String?
    private(set) var revision = -1
    private(set) var processedShot = 0
    private(set) var selected = 0
    private(set) var reloading = false
    private(set) var synchronized = false
    private(set) var pending:[Pending] = []
    private(set) var authoritative:[Int:Rounds] = [:]
    private var highestPredicted = 0
    private var overflowed = false
    private var uncertain = false
    private var connectedAt: Double?
    private let clock:()->Double
    private let timeout:Double
    private let capacity:Int
    init(timeout:Double=2,capacity:Int=128,clock:@escaping()->Double={ProcessInfo.processInfo.systemUptime}) {
        self.timeout=max(0.5,timeout);self.capacity=max(4,capacity);self.clock=clock
    }
    func connected(_ id:String) {
        connection=id;connectedAt=clock();revision = -1;processedShot=0;selected=0;reloading=false;synchronized=false
        authoritative=[:];pending=[];highestPredicted=0;overflowed=false;uncertain=false
    }
    func disconnected() {
        connection=nil;connectedAt=nil;synchronized=false;pending=[];authoritative=[:]
        selected=0;reloading=false;revision = -1;processedShot=0;highestPredicted=0;overflowed=false;uncertain=false
    }
    func markUncertain() { uncertain = true }
    var needsResync:Bool {
        guard connection != nil else { return false }
        let now = clock()
        guard let connectedAt, now.isFinite, now >= connectedAt else { return true }
        guard synchronized else { return now - connectedAt > timeout }
        return uncertain || overflowed || !now.isFinite || pending.first.map{now < $0.at || now-$0.at>timeout} == true
    }
    func rounds(_ weapon:Int)->Rounds? {
        guard var value=authoritative[weapon] else{return nil}
        value.clip=max(0,value.clip-pending.lazy.filter{$0.weapon==weapon}.count)
        return value
    }
    @discardableResult func predict(weapon:Int,sequence:Int)->Bool {
        let now=clock()
        guard synchronized,!needsResync,!reloading,weapon==selected,weapon != 0,
              sequence>processedShot,sequence>highestPredicted,sequence<=NativeShotSequence.maximum,now.isFinite,
              (rounds(weapon)?.clip ?? 0)>0 else{return false}
        guard pending.count<capacity else{overflowed=true;return false}
        pending.append(.init(sequence:sequence,weapon:weapon,at:now));highestPredicted=sequence
        return true
    }
    @discardableResult func apply(_ snapshot:Snapshot)->Result {
        guard connection==snapshot.connection else{return .wrongConnection}
        guard snapshot.processedShot>=0,snapshot.processedShot<=NativeShotSequence.maximum,snapshot.revision>=0,
              snapshot.revision<=NativeShotSequence.maximum,snapshot.selected>=0,
              snapshot.weapons.allSatisfy({$0.key>0 && $0.value.clip>=0 && $0.value.clip<=9999 &&
                  $0.value.reserve>=0 && $0.value.reserve<=9999-$0.value.clip}),
              snapshot.selected==0 || snapshot.weapons[snapshot.selected] != nil else{return .invalid}
        guard snapshot.revision>=revision else{return .staleRevision}
        guard snapshot.processedShot>=processedShot else{return .staleAcknowledgement}
        authoritative=snapshot.weapons;revision=snapshot.revision;processedShot=snapshot.processedShot
        selected=snapshot.selected;reloading=snapshot.reloading;synchronized=true
        pending.removeAll{$0.sequence<=snapshot.processedShot}
        highestPredicted=max(highestPredicted,snapshot.processedShot)
        if pending.count<capacity{overflowed=false}
        return .applied
    }
}


/// Correlation only; it grants no authority. The server binds the nonce to the
/// authenticated WebSocket and applies/rejects each monotonic sequence once.
struct NativeShotTicket: Equatable {
    let connection: String
    let sequence: Int
    fileprivate init(connection: String, sequence: Int) { self.connection = connection; self.sequence = sequence }
}

/// Shared by the real WebSocket client and deterministic protocol tests.
final class NativeShotSequence {
    static let maximum = 9_007_199_254_740_991
    private(set) var connection: String?
    private(set) var reserved = 0
    private(set) var sent = 0
    func reset() { connection = nil; reserved = 0; sent = 0 }
    @discardableResult func negotiate(_ nonce: String) -> Bool {
        guard !nonce.isEmpty, nonce.utf8.count <= 256 else { return false }
        if let connection { return connection == nonce }
        connection = nonce; return true
    }
    func reserve() -> NativeShotTicket? {
        guard let connection, reserved < Self.maximum else { return nil }
        reserved += 1; return NativeShotTicket(connection: connection, sequence: reserved)
    }
    func observeAcknowledgement(_ sequence: Int) {
        guard sequence >= 0, sequence <= Self.maximum else { return }
        reserved = max(reserved, sequence); sent = max(sent, sequence)
    }
    func claim(_ ticket: NativeShotTicket) -> Bool {
        guard ticket.connection == connection, ticket.sequence > sent, ticket.sequence <= reserved else { return false }
        sent = ticket.sequence; return true
    }
}


struct NativeInventoryAcknowledgement {
    let connection: String
    let processedShot: Int
    init?(_ inventory: [String: Any]) {
        guard let ack = inventory["ack"] as? [String: Any],
              let connection = ack["connection"] as? String, !connection.isEmpty, connection.utf8.count <= 256,
              let value = ack["processedShot"] as? NSNumber, CFGetTypeID(value) != CFBooleanGetTypeID(),
              value.doubleValue.isFinite, value.doubleValue >= 0, value.doubleValue <= Double(NativeShotSequence.maximum),
              let sequence = Int(exactly: value.doubleValue) else { return nil }
        self.connection = connection; self.processedShot = sequence
    }
}
