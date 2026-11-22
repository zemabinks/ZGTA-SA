import Foundation
import simd
import CoreFoundation

/// A server-accepted hit is visual feedback, separate from health prediction.
/// Damage is never applied again by its receiver.
struct NativeIncomingHit {
    let weapon:Int,damage:Double,sourceID:String?,source:SIMD3<Float>?,piece:Int,quiet:Bool,wasAlive:Bool
    let authoritativeHealth:Int?
    let parried:Bool
    init(original hit:NativeOriginalWorldVitals.Hit,result:NativeOriginalWorldVitals.Result,health:Int,wasAlive:Bool){
        weapon=hit.weapon;damage=hit.damage;sourceID=hit.source
        source=hit.point.flatMap {p in let value=SIMD3<Float>(p);return [value.x,value.y,value.z].allSatisfy(\.isFinite) ? value:nil}
        piece=hit.piece.flatMap{(0...9).contains($0) ? $0:nil} ?? 3
        quiet=result.quiet;self.wasAlive=wasAlive;authoritativeHealth=health;parried=result.parried
    }
    init?(_ packet:[String:Any],fallbackSource:SIMD3<Float>?=nil,wasAlive:Bool=true) {
        guard let amount=packet["d"] as? NSNumber,CFGetTypeID(amount) != CFBooleanGetTypeID(),amount.doubleValue.isFinite,amount.doubleValue>0 else{return nil}
        let weapon=NativeHealthPrediction.integer(packet["w"]) ?? 0
        guard (0...255).contains(weapon),packet["w"]==nil || NativeHealthPrediction.integer(packet["w"]) != nil else{return nil}
        self.weapon=weapon;damage=amount.doubleValue
        parried=(packet["parried"] as? NSNumber).map{CFGetTypeID($0)==CFBooleanGetTypeID() && $0.boolValue} ?? false
        sourceID=(packet["from"] as? String).flatMap{$0.isEmpty || $0.utf8.count>64 ? nil:$0}
        var point:SIMD3<Float>?
        if let raw=packet["fromAt"] as? [NSNumber],raw.count==3,
           raw.allSatisfy({CFGetTypeID($0) != CFBooleanGetTypeID() && $0.doubleValue.isFinite && $0.floatValue.isFinite}) {
            point=SIMD3(raw[0].floatValue,raw[1].floatValue,raw[2].floatValue)
        }
        source=point ?? fallbackSource.flatMap{[$0.x,$0.y,$0.z].allSatisfy(\.isFinite) ? $0:nil}
        let part=NativeHealthPrediction.integer(packet["piece"]) ?? 3;piece=(0...9).contains(part) ? part:3
        quiet=packet["quiet"] as? Bool ?? false
        self.wasAlive=NativeHealthPrediction.integer(packet["beforeHealth"]).flatMap{(0...100).contains($0) ? $0>0:nil} ?? wasAlive
        let hp=NativeHealthPrediction.integer(packet["health"])
        authoritativeHealth=(packet["healthAck"] as? [String:Any]) != nil ? hp.flatMap{(0...100).contains($0) ? $0:nil}:nil
    }
}

/// Connection-scoped request/seat identity. A passenger never owns a vehicle
/// body; its only authority is the confirmed seat in that logical vehicle.
struct NativeVehicleSeatSession {
    struct Seat:Equatable {let vehicle:String;let index:Int}
    struct Entry:Equatable {let seat:Seat;let request:Int}
    struct Acknowledgement {let seat:Seat;let accepted:Bool;let revoked:Bool}
    private(set) var pending:Entry?
    private(set) var passenger:Seat?
    private var issued=0
    static func validID(_ id:String)->Bool{!id.isEmpty && id.utf8.count<=128 && !id.unicodeScalars.contains{CharacterSet.controlCharacters.contains($0)}}
    mutating func request(vehicle:String,seat:Int)->Entry? {
        guard Self.validID(vehicle),(0...15).contains(seat),passenger==nil,pending==nil,issued<9_007_199_254_740_991 else{return nil}
        issued+=1;let entry=Entry(seat:Seat(vehicle:vehicle,index:seat),request:issued);pending=entry;return entry
    }
    mutating func receive(vehicle:String,seat:Int,accepted:Bool,request:Int?)->Acknowledgement? {
        let target=Seat(vehicle:vehicle,index:seat)
        guard Self.validID(vehicle),(0...15).contains(seat)else{return nil}
        if let request {
            guard let entry=pending,entry.seat==target,entry.request==request else{return nil}
            pending=nil;if accepted && seat>0{passenger=target}
            return .init(seat:target,accepted:accepted,revoked:false)
        }
        // An unsolicited negative ACK can revoke exactly the current seat.
        if !accepted,passenger==target{passenger=nil;return .init(seat:target,accepted:false,revoked:true)}
        if !accepted,pending?.seat==target{pending=nil;return .init(seat:target,accepted:false,revoked:false)}
        // Earlier independent hosts do not echo driver request IDs. This
        // compatibility path does not silently grant uncorrelated passengers.
        if seat==0,let entry=pending,entry.seat==target{pending=nil;return .init(seat:target,accepted:accepted,revoked:false)}
        return nil
    }
    mutating func cancel()->Entry?{let old=pending;pending=nil;return old}
    mutating func leavePassenger()->Seat?{let old=passenger;passenger=nil;return old}
    mutating func remove(vehicle:String){if pending?.seat.vehicle==vehicle{pending=nil};if passenger?.vehicle==vehicle{passenger=nil}}
    // A TP changes placement on the SAME peer. Keep its request namespace so
    // a delayed entry ACK cannot alias a new request after occupancy cleanup.
    mutating func clearOccupancy(){pending=nil;passenger=nil}
    mutating func reset(){clearOccupancy();issued=0}
}

struct RemotePlayer {
    let id: String
    let name: String
    var position: SIMD3<Float>
    let code: String
    var heading: Float
    let pitch: Float
    let roll: Float
    let speed: Float
    let steer: Float
    let skin: Int
    let animation: String
    let animationStarted: Double
    let weapon: Int
    let vehicleID: String?
    var vehicleHealth = 1000
    var vehicleDamage = ""
    var lights = false
    var horn = 0
    var movementRatio:Float = 0
    var airborne = false
    var crouching = false
    var aim:Float?
    var action = 0
    var velocity = SIMD3<Float>.zero
    var angularVelocity = SIMD3<Float>.zero
    var shotCount = 0
    var paused = false
    var down = 0
    var scriptAnimation:String?
    var ridingVehicleID:String?
    var ridingSeat = 0
    var supportVehicleID:String?
    var supportOffset = SIMD3<Float>.zero
    var kit:[Float]?
    var packetReceivedAt:Double = 0
    var packetClockMilliseconds:Double = 0
    var latencyMilliseconds:Float = 0
    var life = 100
    var armour = 0
    var swimState:Int { let base=action&63;return (10...16).contains(base) ? base-9:0 }
    var burning:Bool {action&64 != 0}
}

struct RemoteVehicle {
    let id: String
    let name: String
    let code: String
    var position: SIMD3<Float>
    var heading: Float
    var pitch: Float = 0
    var roll: Float = 0
    var health: Int
    var damage = ""
    var work = 0
    var driverID:String?
    /// Original browser registered rows may originate from compact traffic.
    /// This is a numeric identity, independent of the arbitrary string ID.
    var trafficSourceID:UInt16?

    init?(row: [Any]) {
        guard row.count >= 7, let id = row[0] as? String,
              let name = row[1] as? String, let code = row[2] as? String,
              let x = (row[3] as? NSNumber)?.floatValue,
              let y = (row[4] as? NSNumber)?.floatValue,
              let z = (row[5] as? NSNumber)?.floatValue else { return nil }
        self.id = id
        self.name = name
        self.code = code
        position = SIMD3(x, y, z)
        heading = -((row[6] as? NSNumber)?.floatValue ?? 0)
        pitch = row.count > 7 ? (row[7] as? NSNumber)?.floatValue ?? 0 : 0
        roll = row.count > 8 ? -((row[8] as? NSNumber)?.floatValue ?? 0) : 0
        health = max(0, min(1000, (row.count > 9 ? row[9] as? NSNumber : nil)?.intValue ?? 1000))
        damage = row.count > 10 ? row[10] as? String ?? "" : ""
        work = row.count > 16 ? (row[16] as? NSNumber)?.intValue ?? 0 : 0
        driverID = row.count>11 ? (row[11] as? String).flatMap{NativeVehicleSeatSession.validID($0) ? $0:nil}:nil
        if row.count>14,let value=row[14]as?NSNumber,CFGetTypeID(value) != CFBooleanGetTypeID() {
            let n=value.doubleValue
            if n.isFinite,n.rounded(.towardZero)==n,(0...65535).contains(n){trafficSourceID=UInt16(n)}
        }
    }
}

/// Sequence local environmental damage separately from authoritative damage.
/// A delayed server hit/HTTP snapshot rebases pending losses instead of
/// restoring lost health or applying the same fall twice.
struct NativeHealthPrediction {
    struct Request {let sequence:Int;let connection:String;let kind:String;let damage:Int}
    private(set) var connection:String?
    private(set) var issued=0,processed=0,revision=0
    private var baseHealth=100,baseArmour=0
    private var losses:[Int:Int]=[:],impacts:[Int:Int]=[:]
    private var respawnSequence:Int?
    private var projected:(health:Int,armour:Int) {
        var hp=baseHealth,protected=baseArmour
        for sequence in Set(losses.keys).union(impacts.keys).sorted() {
            if let loss=losses[sequence] {hp=max(0,hp-loss)}
            else if let damage=impacts[sequence] {
                let absorbed=min(protected,damage);protected-=absorbed;hp=max(0,hp-(damage-absorbed))
            }
        }
        return (hp,protected)
    }
    var health:Int {projected.health}
    var armour:Int {projected.armour}
    var active:Bool {connection != nil}
    var pendingRespawn:Int? {respawnSequence}
    mutating func disconnect(){self=NativeHealthPrediction()}
    mutating func begin(connection:String,health:Int,armour:Int,revision:Int,processed:Int){
        disconnect();self.connection=connection;baseHealth=health;baseArmour=armour
        self.revision=revision;self.processed=processed;issued=processed
    }
    mutating func hurt(to value:Int)->Request? {
        guard let connection,issued<9_007_199_254_740_991,losses.count+impacts.count<128 else{return nil}
        let damage=health-max(0,min(health,value))
        guard damage>0 else{return nil}
        issued+=1;losses[issued]=damage
        return Request(sequence:issued,connection:connection,kind:"hurt",damage:damage)
    }
    mutating func impact(_ damage:Int)->Request? {
        guard let connection,health>0,(1...200).contains(damage),
              issued<9_007_199_254_740_991,losses.count+impacts.count<128 else{return nil}
        issued+=1;impacts[issued]=damage
        return Request(sequence:issued,connection:connection,kind:"impact",damage:damage)
    }
    mutating func respawn()->Request? {
        guard let connection,health==0,respawnSequence==nil,issued<9_007_199_254_740_991 else{return nil}
        issued+=1;respawnSequence=issued
        return Request(sequence:issued,connection:connection,kind:"respawn",damage:0)
    }
    mutating func apply(health:Int,armour:Int,connection:String,processed:Int,revision:Int)->Bool {
        guard self.connection==connection,(0...100).contains(health),(0...100).contains(armour),
              processed>=self.processed,processed<=issued,revision>=self.revision,
              revision != self.revision || (processed==self.processed && health==baseHealth && armour==baseArmour) else{return false}
        self.processed=processed;self.revision=revision;baseHealth=health;baseArmour=armour
        losses=losses.filter{$0.key>processed};impacts=impacts.filter{$0.key>processed}
        if let sequence=respawnSequence,sequence<=processed {respawnSequence=nil}
        return true
    }
    static func integer(_ value:Any?)->Int? {
        guard let n=value as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),n.doubleValue.isFinite,
              n.doubleValue>=0,n.doubleValue<=9_007_199_254_740_991,n.doubleValue.rounded(.down)==n.doubleValue else{return nil}
        return n.intValue
    }
}

/// Speaks the existing local server's WebSocket protocol without Discord.
/// Browser heading/roll are Three Y-yaw/Z-roll. GTA native controls use the
/// opposite signs for those two angles; convert once at this wire boundary.
struct NativeCouplingLink: Equatable {
    let parent: String
    let trailer: String
    let kind: String
}

/// Bounded topology validation only. Vehicle models, physical joints and
/// authority remain owned by the scene/server, not by fabricated row fields.
enum NativeCouplingTopology {
    static func validID(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 64 &&
        value == value.trimmingCharacters(in: .whitespacesAndNewlines) &&
        !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
    struct Snapshot { let revision: Int; let links: [NativeCouplingLink] }
    static func parse(_ value: [String: Any]) -> Snapshot? {
        guard let revision=NativeHealthPrediction.integer(value["revision"]),
              let rows=value["links"] as? [[String:Any]], rows.count<=256 else { return nil }
        var links:[NativeCouplingLink]=[], outgoing:[String:String]=[:], incoming=Set<String>()
        for row in rows {
            guard let parent=row["parent"] as? String, let trailer=row["trailer"] as? String,
                  let kind=row["kind"] as? String, validID(parent),validID(trailer),parent != trailer,
                  ["trailer","tow"].contains(kind),outgoing[parent]==nil,incoming.insert(trailer).inserted else { return nil }
            outgoing[parent]=trailer;links.append(.init(parent:parent,trailer:trailer,kind:kind))
        }
        for link in links where link.kind == "tow" {
            guard !incoming.contains(link.parent),outgoing[link.trailer]==nil else{return nil}
        }
        for parent in outgoing.keys {
            var seen=Set<String>(),current=parent,count=0
            while let next=outgoing[current] {
                guard seen.insert(current).inserted else { return nil }
                count+=1;guard count<=2 else { return nil };current=next
            }
        }
        links.sort { $0.parent < $1.parent }
        return Snapshot(revision:revision,links:links)
    }
}

/// Semantic game connection; each adapter owns its real wire protocol.
protocol NativeLegacyWorldConnection:AnyObject {
    var state:NativeConnectionRecovery.State{get}
    var onState:((NativeConnectionRecovery.State)->Void)?{get set}
    var onStatus:((String)->Void)?{get set}
    var onPlayers:(([RemotePlayer])->Void)?{get set}
    var onVehicles:(([RemoteVehicle])->Void)?{get set}
    var onEvent:(([String:Any])->Void)?{get set}
    func connect()
    func disconnect()
    func setActive(_ active:Bool)
    func tick(now:Double)
    @discardableResult func send(_ message:[String:Any])->Bool
}
/// Connection-scoped server placements are committed only after the owner has
/// synchronously applied their pose. A nonce/revision correlates position; it
/// neither grants a vehicle role nor substitutes for the health/ammo owners.
struct NativePlacementSession {
    struct Envelope:Equatable {
        let connection:String,revision:Int
        var wire:[String:Any]{["connection":connection,"revision":revision]}
    }
    struct Transaction:Equatable {
        let token:UUID,envelope:Envelope,position:SIMD3<Float>,heading:Float
    }
    enum Hello {case legacy,duplicate,place(Transaction),invalid}
    private(set) var negotiated=false
    private(set) var applied:Envelope?
    private var pending:Transaction?
    var isPlacing:Bool{pending != nil}
    var permitsPosition:Bool{!isPlacing && (!negotiated || applied != nil)}
    mutating func reset(){self=NativePlacementSession()}

    static func integer(_ value:Any?)->Int? {
        guard let n=value as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),
              n.doubleValue.isFinite,n.doubleValue>=0,n.doubleValue<=9_007_199_254_740_991,
              let result=Int(exactly:n.doubleValue)else{return nil}
        return result
    }
    private static func number(_ value:Any?)->Double? {
        guard let n=value as? NSNumber,CFGetTypeID(n) != CFBooleanGetTypeID(),n.doubleValue.isFinite else{return nil}
        return n.doubleValue
    }
    private static func validNonce(_ value:String)->Bool {
        (16...80).contains(value.utf8.count) && value.utf8.allSatisfy{
            (48...57).contains($0)||(65...90).contains($0)||(97...122).contains($0)||$0==45||$0==95
        }
    }
    private static func envelope(_ value:Any?,connection:String)->Envelope? {
        guard validNonce(connection),let object=value as? [String:Any],
              object["connection"] as? String==connection,let revision=integer(object["revision"])else{return nil}
        return Envelope(connection:connection,revision:revision)
    }
    private static func pose(_ values:[Any],degrees:Bool)->(SIMD3<Float>,Float)? {
        guard values.count==4 else{return nil}
        let numbers=values.compactMap{number($0)}
        guard numbers.count==4,numbers.prefix(3).allSatisfy({abs($0)<=1_000_000})else{return nil}
        let radians=degrees ? numbers[3] * .pi/180:numbers[3]
        guard radians.isFinite,abs(radians)<=1_000_000 else{return nil}
        let point=SIMD3<Float>(Float(numbers[0]),Float(numbers[1]),Float(numbers[2])),heading = -Float(radians)
        guard point.x.isFinite,point.y.isFinite,point.z.isFinite,heading.isFinite else{return nil}
        return(point,heading)
    }
    mutating func hello(_ message:[String:Any],connection:String,fresh:Bool)->Hello {
        // The server repeats its INITIAL hello on this socket. A later TP may
        // already have advanced the applied revision; duplicate hello cannot
        // downgrade the negotiated mode or rewind its original spot/revision.
        guard fresh else{return .duplicate}
        guard message["positionAck"] != nil else{reset();return .legacy}
        guard Self.integer(message["positionAck"])==1,
              let envelope=Self.envelope(message["placement"],connection:connection),envelope.revision==0,
              let values=message["spot"]as?[Any],let pose=Self.pose(values,degrees:false),
              let health=message["healthAck"]as?[String:Any],health["connection"]as?String==connection,
              Self.integer(health["processed"]) != nil,Self.integer(health["revision"]) != nil,
              Self.integer(health["respawned"]) != nil,
              let life=message["life"]as?[Any],life.count==2,
              let hp=Self.integer(life[0]),hp<=100,let armour=Self.integer(life[1]),armour<=100 else{return .invalid}
        let transaction=Transaction(token:UUID(),envelope:envelope,position:pose.0,heading:pose.1)
        negotiated=true;applied=nil;pending=transaction
        return .place(transaction)
    }
    mutating func teleport(_ message:[String:Any],connection:String)->Transaction? {
        guard negotiated,let current=applied ?? pending?.envelope,current.connection==connection,
              let envelope=Self.envelope(message["placement"],connection:connection),
              envelope.revision>max(current.revision,pending?.envelope.revision ?? current.revision),
              let x=message["x"],let y=message["y"],let z=message["z"],let h=message["h"],
              let pose=Self.pose([x,y,z,h],degrees:true)else{return nil}
        let transaction=Transaction(token:UUID(),envelope:envelope,position:pose.0,heading:pose.1)
        pending=transaction;return transaction
    }
    func owns(_ transaction:Transaction)->Bool{pending==transaction}
    @discardableResult mutating func commit(_ transaction:Transaction)->Bool {
        guard owns(transaction),negotiated else{return false}
        applied=transaction.envelope;pending=nil;return true
    }
    func stamping(_ object:[String:Any])->[String:Any]? {
        guard object["t"]as?String=="me"else{return object}
        guard permitsPosition else{return nil}
        guard negotiated else{return object}
        guard let applied else{return nil}
        var result=object;result["placement"]=applied.wire;return result
    }
}

final class NativeMultiplayerClient {
    enum Flavor {
        case selfHost
        case originalWorld(build: String, deviceID: String)
    }
    let flavor: Flavor
    let legacy:NativeLegacyWorldConnection?
    var usesClientOwnedWeapons:Bool{legacy != nil || usesOriginalWorldProtocol}
    var onLegacyEvent:(([String:Any])->Void)?
    var usesOriginalWorldProtocol: Bool { if case .originalWorld = flavor { return true }; return false }
    var onOriginalGuns: ((Any,Bool)->Void)?
    var onAuthenticationRequired: (()->Void)?
    var onOriginalShot: (([String:Any])->Void)?
    var onAcceptedStrike: (([String:Any])->Void)?
    var onOriginalRecord: ((UInt8,Data)->Void)?
    var onAmbientPedestrianConfiguration:((Double,String?)->Void)?
    var onAmbientPedestrianEvent:((NativeAmbientPedestrianProtocol.Event,Double,Double)->Void)?
    var onAmbientTrafficConfiguration:((Double,String?)->Void)?
    var onAmbientTrafficEvent:((NativeAmbientTrafficProtocol.Event,Double,Double)->Void)?
    private var ambientBinaryEnabled=false
    private var selfhostTrafficEnabled=false
    private var selfhostPedestriansEnabled=false
    var canRequestTrafficVehicle:Bool {usesOriginalWorldProtocol || selfhostTrafficEnabled}
    var onOriginalCommand: (([String:Any])->Void)?
    var onOriginalVehicleHit: (([String:Any])->Void)?
    var onOriginalHit: ((NativeOriginalWorldVitals.Hit)->Void)?
    var onOriginalHitResult: ((NativeOriginalWorldVitals.Result,NativeOriginalWorldVitals.Hit)->Void)?
    var onOriginalEvent: ((NativeOriginalWorldCommands.Event,[String:Any])->Void)?
    private let originalVitals=NativeOriginalWorldVitals()
    private(set) var originalFrozen=false
    private(set) var originalRespawnWasDead=false
    var originalHealth:Double{originalVitals.health}
    var originalArmour:Double{originalVitals.armour}
    var originalFatal:NativeOriginalWorldVitals.PendingFatal?{usesOriginalWorldProtocol ? originalVitals.pendingFatal:nil}
    private var legacyGameplay=NativeSAMPGameplayCommands.Authority()
    private var legacyVitals=NativeSAMPLocalVitals()
    var legacyHealth:Double{legacyVitals.health}
    var legacyArmour:Double{legacyVitals.armour}
    var legacyDeathReason:UInt8{legacyVitals.fatalCause?.weapon ?? 255}
    var legacyDeathKiller:UInt16{legacyVitals.fatalCause?.source ?? 65535}
    private var wireHealth:Int{usesOriginalWorldProtocol ? originalVitals.wireHealth:legacy != nil ? legacyVitals.wireHealth:health}
    private var wireArmour:Int{usesOriginalWorldProtocol ? originalVitals.wireArmour:legacy != nil ? legacyVitals.wireArmour:armour}
    var serverInputBlocked:Bool{(legacy != nil && legacyGameplay.inputBlocked) || (usesOriginalWorldProtocol && (originalFrozen || originalFatal != nil))}
    var originalInputBlocked:Bool{serverInputBlocked}
    var legacySpectating:Bool{legacy != nil && legacyGameplay.spectating}
    var sampGameplayGeneration:UInt64?{legacyGameplay.generation}
    private var originalCommandDepth=0
    private var originalLatestPosition: [String:Any]?
    private let originalStream = NativeOriginalWorldStream()
    private let originalKey = UUID().uuidString.replacingOccurrences(of:"-",with:"").lowercased()
    private var originalHeard: Int?
    private var originalDeathSent = false
    private var originalRespawnRequested: Double?
    typealias ConnectionState = NativeConnectionRecovery.State
    private let server: ServerAddress
    private let session: URLSession
    private let clock: () -> Double
    private let automaticRecoveryTimer: Bool
    private var recovery = NativeConnectionRecovery()
    private var recoveryTimer: DispatchSourceTimer?
    private var transportGeneration: UInt64 = 0
    private var lastPing: Double = -.infinity
    private(set) var state: ConnectionState = .stopped
    var isReady: Bool { if let legacy{return legacy.state == .ready};return recovery.state == .ready && socket != nil && (usesOriginalWorldProtocol || placementSession.permitsPosition) }
    var onConnectionState: ((ConnectionState) -> Void)?
    private var socket: URLSessionWebSocketTask?
    private(set) var players: [String: RemotePlayer] = [:]
    private(set) var vehicles: [String: RemoteVehicle] = [:]
    private var playerOrder:[String]=[],vehicleOrder:[String]=[]
    private var legacyRoster:[String:String]?
    private var legacyHasRoster=false
    var orderedPlayers:[RemotePlayer] {playerOrder.compactMap{players[$0]}}
    var orderedVehicles:[RemoteVehicle] {vehicleOrder.compactMap{vehicles[$0]}}
    private var remoteAnimationTimes: [String: (String, Double)] = [:]
    private var shots = 0
    private let shotSequence = NativeShotSequence()
    private let streamShotClaims = NativeStreamShotClaims()
    private var healthPrediction=NativeHealthPrediction()
    private var deliveredRespawnSequence=0
    private var deliveredHitRevision:Int?
    private var deliveredHitSequence:Int?
    private var resynchronizingInventory = false
    private var announcedInventoryConnection: String?
    private var placementSession=NativePlacementSession()
    var positionAcknowledgements:Bool{placementSession.negotiated}
    var isPlacing:Bool{placementSession.isPlacing}
    var appliedPlacementRevision:Int?{placementSession.applied?.revision}
    var placementConnection:String?{placementSession.applied?.connection}
    var inventoryConnection: String? { shotSequence.connection }
    var onInventoryConnection: ((String?) -> Void)?
    private(set) var localName = "LOCAL PLAYER"
    private(set) var localSkin=7
    func setLocalSkin(_ id:Int){if (0...311).contains(id){localSkin=id}}
    private(set) var cash = 0
    private(set) var health = 100
    private(set) var armour = 0
    private(set) var passive = false
    private(set) var serverTimeOffsetMilliseconds:Double = 0
    private var positionPackets = 0
    private var pendingSays: [String] = []
    private var lastChatSequence = 0
    private(set) var chatMessages: [String] = []
    var onStatus: ((String) -> Void)?
    var onPlayers: (([RemotePlayer]) -> Void)?
    var onPresence: ((Int, [String]) -> Void)?
    var onVehicles: (([RemoteVehicle]) -> Void)?
    /// Explicit despawn differs from omission in a streamed vehicle list.
    var onVehicleRemoved: ((String) -> Void)?
    var onEnter: ((String, Bool) -> Void)?
    var onPassengerEnter:((String,Int,Bool)->Void)?
    private var vehicleSeats=NativeVehicleSeatSession()
    var pendingVehicleEntry:NativeVehicleSeatSession.Entry?{vehicleSeats.pending}
    var passengerSeat:NativeVehicleSeatSession.Seat?{vehicleSeats.passenger}
    var onTeleport: ((SIMD3<Float>, Float?) -> Void)?
    var onEnvironment: ((Int?, Double?, Double?) -> Void)?
    var onInventory: (([String: Any]) -> Void)?
    var onProjectiles: (([[String: Any]]) -> Void)?
    var onBlast: ((Int, SIMD3<Float>) -> Void)?
    var onWeaponSound: ((Int) -> Void)?
    var onVitals: ((Int, Int) -> Void)?
    var onIncomingHit:((NativeIncomingHit)->Void)?
    var onRespawn: (() -> Void)?
    private(set) var couplingAcknowledgements=false
    private(set) var ordinaryShotGroupsEnabled=false
    private(set) var couplingRevision:Int?
    private(set) var couplingLinks:[NativeCouplingLink]=[]
    private var couplingIssued=0,couplingProcessed=0
    private var pendingCouplings:[Int:(Bool)->Void]=[:]
    var onCouplings: (([NativeCouplingLink],Int,String)->Void)?
    var onFlightGear: ((Bool,Bool) -> Void)?
    var onChat: (([String]) -> Void)?

    init(server: ServerAddress, session: URLSession = .shared,
         clock: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime },
         automaticRecoveryTimer: Bool = true, flavor: Flavor = .selfHost, legacy:NativeLegacyWorldConnection?=nil) {
        self.flavor = flavor;self.legacy=legacy
        self.server = server; self.session = session; self.clock = clock
        self.automaticRecoveryTimer = automaticRecoveryTimer
        if let legacy{installLegacy(legacy)}
    }
    deinit { recoveryTimer?.cancel(); socket?.cancel(with: .normalClosure, reason: nil) }

    func connect() {
        if let legacy{legacy.connect();return}
        resynchronizingInventory = false
        startRecoveryTimer()
        run(recovery.start(now: clock()))
    }
    func disconnect() {
        if let legacy{legacy.disconnect();closeSocket();return}
        recovery.stop(); resynchronizingInventory = false
        recoveryTimer?.cancel(); recoveryTimer = nil
        closeSocket(); publishState()
    }
    func setApplicationActive(_ active: Bool) {
        if let legacy{legacy.setActive(active);return}
        recovery.setActive(active, now: clock())
        if active { lastPing = -.infinity; tickConnection(now: clock()) }
    }
    func tickConnection(now: Double) {
        if let legacy{legacy.tick(now:now);return}
        run(recovery.tick(now: now))
        if usesOriginalWorldProtocol, let began=originalRespawnRequested, now-began>6 {
            originalRespawnRequested=nil;onStatus?("ORIGINAL SERVER DID NOT CONFIRM RESPAWN — TRY AGAIN")
        }
        if usesOriginalWorldProtocol {originalWho()}
        if recovery.active, socket != nil, now.isFinite, now-lastPing >= 2 {
            lastPing = now
            send(["t": "ping", "c": now * 1000], allowBeforeReady: true)
        }
    }
    private func startRecoveryTimer() {
        guard automaticRecoveryTimer, recoveryTimer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + 0.25, repeating: 0.25)
        timer.setEventHandler { [weak self] in
            guard let self else { return }; self.tickConnection(now: self.clock())
        }
        recoveryTimer = timer; timer.resume()
    }
    private func installLegacy(_ legacy:NativeLegacyWorldConnection){
        legacy.onState = { [weak self] next in
            guard let self else{return};if next != .ready{self.closeSocket()}
            guard self.state != next else{return};self.state=next;self.onConnectionState?(next)
        }
        legacy.onStatus = { [weak self] in self?.onStatus?($0) }
        legacy.onPlayers = { [weak self] rows in
            guard let self else{return};self.players=Dictionary(uniqueKeysWithValues:rows.map{($0.id,$0)})
            self.playerOrder=rows.map(\.id);self.onPlayers?(rows)
            if !self.legacyHasRoster{self.onPresence?(rows.count+1,rows.map(\.name)+[self.localName])}
        }
        legacy.onVehicles = { [weak self] rows in
            guard let self else{return};let removed=Set(self.vehicleOrder).subtracting(rows.map(\.id))
            self.vehicles=Dictionary(uniqueKeysWithValues:rows.map{($0.id,$0)});self.vehicleOrder=rows.map(\.id)
            for id in removed{self.onVehicleRemoved?(id)};self.onVehicles?(rows)
        }
        legacy.onEvent = { [weak self] message in
            guard let self else{return}
            switch message["t"]as?String {
            case "sampGameplay":
                guard let event=message["event"]as?NativeSAMPGameplayCommands.Event,self.legacyGameplay.apply(event)else{return}
                if event.command == .reset {self.legacyVitals.reset();self.publishLegacyVitals()}
            case "rosterReset":self.legacyHasRoster=true;self.legacyRoster=nil
            case "roster":
                if let names=message["players"]as?[String:String]{self.legacyHasRoster=true;self.legacyRoster=names;self.onPresence?(names.count,names.keys.sorted().compactMap{names[$0]})}
            case "chat":if let line=message["text"]as?String{self.chatMessages.append(line);self.chatMessages=Array(self.chatMessages.suffix(50));self.onChat?(self.chatMessages)}
            case "position":if let p=message["point"]as?SIMD3<Float>{self.onTeleport?(p,message["heading"]as?Float)}
            case "environment":self.onEnvironment?(message["weather"]as?Int,message["shift"]as?Double,message["hold"]as?Double)
            case "vitals":
                if self.legacyVitals.seed(health:(message["health"]as?NSNumber)?.doubleValue,armour:(message["armour"]as?NSNumber)?.doubleValue){self.publishLegacyVitals()}
            case "enter":
                if (message["seat"]as?Int ?? 0)==0,let id=message["id"]as?String{self.onEnter?(id,true)}
                else{self.onStatus?("PASSENGER SEATS REQUIRE THE NATIVE PASSENGER CONTROLLER")}
            case "spawn":self.legacyVitals.reset();self.publishLegacyVitals()
            default:break
            }
            self.onLegacyEvent?(message)
        }
    }
    private func publishState() {
        guard state != recovery.state else { return }
        state = recovery.state; onConnectionState?(state)
        if state == .ready { onStatus?("ONLINE AS \(localName.uppercased())") }
    }
    private func run(_ action: NativeConnectionRecovery.Action?) {
        publishState()
        switch action {
        case .open(let generation): openSocket(generation: generation)
        case .timeout(let generation): failTransport(generation: generation, reason: "CONNECTION TIMED OUT — RECONNECTING")
        case nil: break
        }
    }
    private func openSocket(generation: UInt64) {
        guard recovery.desired, recovery.hasTransport, recovery.generation == generation else { return }
        closeSocket()
        guard recovery.desired, recovery.hasTransport, recovery.generation == generation else { return }
        transportGeneration = generation; lastPing = -.infinity
        let url: URL, hello: [String:Any]
        switch flavor {
        case .selfHost:
            guard var parts = URLComponents(url: server.path("api/world/live"), resolvingAgainstBaseURL: false) else {
                failTransport(generation:generation,reason:"INVALID MULTIPLAYER ADDRESS");return
            }
            parts.scheme=server.url.scheme=="https" ? "wss":"ws"
            guard let value=parts.url else { failTransport(generation:generation,reason:"INVALID MULTIPLAYER ADDRESS");return }
            url=value;hello=["t":"hi","nativeInventory":true,"inventoryAck":1,"healthAck":1,"couplingAck":1,"positionAck":1,"npcProtocol":38,"trafficProtocol":38,"ordinaryShots":1]
        case .originalWorld(let build,let deviceID):
            do {
                let originalURL=try NativeOriginalWorldProtocol.liveURL(deviceID:deviceID)
                hello=try NativeOriginalWorldProtocol.hello(build:build)
                if ["127.0.0.1","localhost","::1"].contains(server.url.host?.lowercased() ?? "") {
                    // A loopback-only protocol fixture is explicitly supported;
                    // arbitrary third-party origins cannot receive this flavor.
                    var parts=URLComponents(url:originalURL,resolvingAgainstBaseURL:false)!
                    parts.host=server.url.host;parts.port=server.url.port
                    parts.scheme=server.url.scheme=="https" ? "wss":"ws";url=parts.url!
                } else { _=try NativeOriginalWorldProtocol.origin(server.url);url=originalURL }
            } catch { stopOriginal(reason:"INVALID ORIGINAL SERVER CONFIGURATION");return }
        }
        var request=URLRequest(url:url)
        if usesOriginalWorldProtocol {
            var origin=URLComponents(url:server.url,resolvingAgainstBaseURL:false)!
            origin.path="";origin.query=nil;origin.fragment=nil
            request.setValue(origin.string,forHTTPHeaderField:"Origin")
        }
        let task=session.webSocketTask(with:request)
        socket=task;task.resume();send(hello,allowBeforeReady:true);receive()
    }
    private func closeSocket() {
        let old = socket; socket = nil
        old?.cancel(with: .normalClosure, reason: nil)
        placementSession.reset()
        shotSequence.reset(); streamShotClaims.reset(); announcedInventoryConnection = nil
        originalStream.clear();originalHeard=nil;originalDeathSent=false;originalRespawnRequested=nil;originalLatestPosition=nil
        ambientBinaryEnabled=false;selfhostTrafficEnabled=false;selfhostPedestriansEnabled=false;onAmbientPedestrianConfiguration?(0,nil)
        onAmbientTrafficConfiguration?(0,nil)
        originalVitals.cancelPendingFatal();originalFrozen=false;originalRespawnWasDead=false
        healthPrediction.disconnect()
        deliveredRespawnSequence=0
        deliveredHitRevision=nil;deliveredHitSequence=nil
        couplingAcknowledgements=false;couplingRevision=nil;couplingLinks=[]
        ordinaryShotGroupsEnabled=false
        couplingIssued=0;couplingProcessed=0;pendingCouplings.removeAll()
        vehicleSeats.reset()
        onInventoryConnection?(nil)
        // A fresh peer has a fresh row/clock/shot namespace. Never carry a
        // previous driver, remote actor, projectile or queued command into it.
        players.removeAll(); vehicles.removeAll(); playerOrder.removeAll(); vehicleOrder.removeAll()
        remoteAnimationTimes.removeAll(); pendingSays.removeAll(); shots = 0; positionPackets = 0
        lastChatSequence = 0; chatMessages.removeAll(); serverTimeOffsetMilliseconds = 0
        onPlayers?([]); onVehicles?([]); onProjectiles?([]); onPresence?(0, []); onChat?([])
    }
    private func failTransport(generation: UInt64, reason: String) {
        guard recovery.failed(generation: generation, now: clock()) else { return }
        resynchronizingInventory = false
        closeSocket(); publishState(); onStatus?("MULTIPLAYER: \(reason)")
    }

    /// Uncertain writes are settled by a new authoritative peer, never replayed.
    func requestInventoryResync() {
        if let legacy{legacy.disconnect();legacy.connect();return}
        guard recovery.desired, !resynchronizingInventory else { return }
        resynchronizingInventory = true
        let action = recovery.restart(now: clock())
        closeSocket(); run(action)
    }
    func reserveShot() -> NativeShotTicket? {
        guard isReady, socket != nil, health > 0, !passive else { return nil }
        return shotSequence.reserve()
    }

    func sendPosition(_ position: SIMD3<Float>, heading: Float, moving: Bool, running: Bool,
                      vehicle: RemoteVehicle? = nil, speed: Float = 0,
                      steer: Float = 0, pitch: Float = 0, roll: Float = 0,
                      vehicleHealth: Int = 1000,
                      vehicleDamage: String = "",lights: Bool = false,horn: Bool = false,siren:Bool=false,
                      airborne: Bool = false, weapon: Int = 0, firing: Bool = false,
                      animation: String? = nil, crouching: Bool = false,
                      swimState: Int = 0,swimPitch: Float = 0,swimRatio: Float = 0,
                      movement:Double? = nil,aim:Double? = nil,action:Int = 0,
                      velocity:SIMD3<Float> = .zero,angularVelocity:SIMD3<Float> = .zero,
                      kit:[Double]? = nil,vehicleWork:Int? = nil,paused:Bool = false,
                      support:(id:String,offset:SIMD3<Float>)? = nil,down:Int=0,
                      legacyRotation:SIMD4<Float>?=nil,legacyKeys:UInt16=0,
                      legacyAxes:SIMD2<Int16> = .zero,legacySpecialKeys:UInt8=0) {
        guard isReady else { return }
        func rounded(_ value:Double)->Double {value.isFinite ? floor(value*100+0.5)/100:0}
        let motion:[String:Any] = ["vx":rounded(Double(velocity.x)),"vy":rounded(Double(velocity.y)),"vz":rounded(Double(velocity.z)),
            "wx":rounded(Double(angularVelocity.x)),"wy":rounded(Double(angularVelocity.y)),"wz":rounded(Double(angularVelocity.z)),
            "clock":Date().timeIntervalSince1970*1000,"paused":paused]
        if let vehicle {
            var packet: [String: Any] = ["t": "me", "driving": true, "car": vehicle.code,
                  "vehicle": vehicle.id, "skin": localSkin, "weapon":weapon,
                  "x": Double(position.x), "y": Double(position.y), "z": Double(position.z),
                  "heading": -Double(heading), "pitch": Double(pitch), "roll": -Double(roll),
                  "speed": Double(speed), "steer": -Double(steer),
                  "health": vehicleHealth, "life": wireHealth,
                  "armour": wireArmour]
            packet["damage"] = vehicleDamage;packet["lights"] = lights;packet["horn"] = horn
            packet["act"]=action
            if let vehicleWork {packet["w"]=max(0,min(2500,vehicleWork))}
            if siren {packet["horn"]=(horn ? 1:0)+2}
            packet.merge(motion){_,new in new};if let kit {packet["kit"]=kit}
            if legacy != nil {
                packet["keys"]=Int(legacyKeys);packet["lr"]=Int(legacyAxes.x);packet["ud"]=Int(legacyAxes.y);packet["specialKeys"]=Int(legacySpecialKeys)
                packet["deathReason"]=Int(legacyDeathReason);packet["deathKiller"]=Int(legacyDeathKiller)
                if let q=legacyRotation{packet["rotation"]=[q.x,q.y,q.z,q.w]}
            }
            if usesOriginalWorldProtocol {originalLatestPosition=packet}
            addPendingChat(to: &packet)
            send(packet)
            return
        }
        var packet: [String: Any] = ["t": "me", "walking": true, "skin": localSkin,
              "x": Double(position.x), "y": Double(position.y), "z": Double(position.z),
              "heading": -Double(heading), "health": wireHealth,
              "armour": wireArmour,
              "weapon": weapon,
              "shots": shots,
              "crouch": crouching,
              "air": airborne,"act":action,
              "move":rounded(movement ?? (moving ? running ? 3:2:0)),
              "aim":aim.map{rounded($0)} ?? NSNull(),
              "anim":animation.flatMap{$0.isEmpty ? nil:NativePedestrianMotion.wireAnimation(for:$0)} ?? NSNull()]
        packet.merge(motion){_,new in new}
        if legacy != nil {packet["keys"]=Int(legacyKeys);packet["lr"]=Int(legacyAxes.x);packet["ud"]=Int(legacyAxes.y);packet["specialKeys"]=Int(legacySpecialKeys);packet["deathReason"]=Int(legacyDeathReason);packet["deathKiller"]=Int(legacyDeathKiller)}
        packet["down"]=(1...6).contains(down) ? down:0
        if let support,!support.id.isEmpty,support.id.utf8.count<=64,
           [support.offset.x,support.offset.y,support.offset.z].allSatisfy({$0.isFinite && abs($0)<=100}) {
            packet["on"]=["v":support.id,"x":rounded(Double(support.offset.x)),"y":rounded(Double(support.offset.y)),"z":rounded(Double(support.offset.z))]
        }else{packet["on"]=NSNull()}
        if (50...62).contains(action&63),health>0 {
            packet["pitch"]=rounded(Double(pitch));packet["roll"]=rounded(Double(roll))
            if (50...58).contains(action&63) || (61...62).contains(action&63) {
                packet["move"]=0;packet["air"]=false;packet["crouch"]=false
            }
            if (50...58).contains(action&63) {packet["aim"]=NSNull()}
        }
        if (1...7).contains(swimState),health > 0 {
            packet["act"] = 9+swimState;packet["move"] = rounded(Double(swimRatio))
            packet["air"] = false;packet["crouch"] = false;packet["weapon"] = 0
            packet["aim"] = NSNull();packet["pitch"] = rounded(Double(swimPitch))
        }
        if usesOriginalWorldProtocol {originalLatestPosition=packet}
        addPendingChat(to: &packet)
        send(packet)
        positionPackets += 1
        if positionPackets % 10 == 0 { send(["t": "board"]) }
    }

    func sendChat(_ line: String) {
        if let legacy{_=legacy.send(["t":"chat","text":line]);return}
        guard isReady else { onStatus?("OFFLINE — MESSAGE NOT SENT"); return }
        let trimmed = String(line.trimmingCharacters(in: .whitespacesAndNewlines).prefix(240))
        guard !trimmed.isEmpty else { return }
        pendingSays.append(trimmed)
    }
    @discardableResult func sendSpectatorPosition(point:SIMD3<Float>,keys:UInt16=0,axes:SIMD2<Int16> = .zero)->Bool {
        guard let legacy,legacySpectating,[point.x,point.y,point.z].allSatisfy(\.isFinite)else{return false}
        return legacy.send(["t":"spectator","point":[point.x,point.y,point.z],"keys":Int(keys),"lr":Int(axes.x),"ud":Int(axes.y)])
    }

    /// A queued request has one connection-scoped identity. A failed transport
    /// is uncertain: close/reconnect drops it rather than replaying an action
    /// the server may already have accepted. Invalid requests allocate nothing.
    @discardableResult func requestCoupling(parent:String,trailer:String?,kind:String,
        completion:@escaping(Bool)->Void)->Bool {
        guard isReady,couplingAcknowledgements,couplingRevision != nil,
              let connection=inventoryConnection,let task=socket,
              NativeCouplingTopology.validID(parent),
              trailer.map({NativeCouplingTopology.validID($0) && $0 != parent}) ?? true,
              ["trailer","tow"].contains(kind),pendingCouplings.count<128,
              couplingIssued<NativeShotSequence.maximum else{return false}
        let sequence=couplingIssued+1,generation=transportGeneration
        let packet:[String:Any]=["t":"hitch","v":parent,"tr":trailer.map{$0 as Any} ?? NSNull(),"kind":kind,"c":connection,"s":sequence]
        guard let data=try? JSONSerialization.data(withJSONObject:packet),let text=String(data:data,encoding:.utf8) else{return false}
        couplingIssued=sequence;pendingCouplings[sequence]=completion
        task.send(.string(text)) { [weak self] error in
            guard let error else{return}
            DispatchQueue.main.async {
                guard let self,self.socket === task,self.transportGeneration==generation,self.inventoryConnection==connection else{return}
                self.failTransport(generation:generation,reason:error.localizedDescription)
            }
        }
        return true
    }

    private func receiveCouplings(_ message:[String:Any],generation:UInt64) {
        guard couplingAcknowledgements,let task=socket,transportGeneration==generation,
              let connection=inventoryConnection,announcedInventoryConnection==connection,
              let value=message["state"] as? [String:Any],let snapshot=NativeCouplingTopology.parse(value) else{return}
        if let revision=couplingRevision {
            guard snapshot.revision>=revision,
                  snapshot.revision != revision || snapshot.links==couplingLinks else{return}
        }
        var sequence:Int?,accepted=false,processed=couplingProcessed
        if let raw=message["ack"] {
            guard let ack=raw as? [String:Any],ack["connection"] as? String==connection,
                  let next=NativeHealthPrediction.integer(ack["sequence"]),next>0,next<=couplingIssued,
                  let floor=NativeHealthPrediction.integer(ack["processed"]),floor>=next,
                  floor>=couplingProcessed,floor<=couplingIssued,
                  let boolean=ack["accepted"] as? NSNumber,CFGetTypeID(boolean)==CFBooleanGetTypeID() else{return}
            sequence=next;accepted=boolean.boolValue;processed=floor
        }
        let changed=couplingRevision==nil || snapshot.revision != couplingRevision
        couplingRevision=snapshot.revision;couplingLinks=snapshot.links;couplingProcessed=processed
        let completion=sequence.flatMap{pendingCouplings.removeValue(forKey:$0)}
        recovery.received(generation:generation,now:clock())
        if changed {onCouplings?(snapshot.links,snapshot.revision,connection)}
        guard socket === task,transportGeneration==generation,inventoryConnection==connection,couplingAcknowledgements else{return}
        completion?(accepted)
    }

    private func addPendingChat(to packet: inout [String: Any]) {
        if usesOriginalWorldProtocol {
            packet["key"]=originalKey
            packet["clock"]=Date().timeIntervalSince1970*1000+serverTimeOffsetMilliseconds
            if let originalHeard { packet["heard"]=originalHeard }
        }
        if !pendingSays.isEmpty { packet["say"] = pendingSays.removeFirst() }
    }

    private func receiveChat(_ rows: [[Any]]) {
        var changed = false
        for row in rows {
            guard row.count >= 3,
                  let sequence = row[0] as? Int, sequence > lastChatSequence,
                  let name = row[1] as? String,
                  let line = row[2] as? String else { continue }
            lastChatSequence = sequence
            chatMessages.append("\(name): \(line)")
            changed = true
        }
        if changed {
            chatMessages = Array(chatMessages.suffix(50))
            onChat?(chatMessages)
        }
    }

    @discardableResult func requestEnter(_ vehicle: RemoteVehicle,seat:Int=0)->Bool {
        guard isReady,(0...15).contains(seat)else{return false}
        if seat>0,(legacy != nil || usesOriginalWorldProtocol){onStatus?("PASSENGER CONTROL IS NOT AVAILABLE ON THIS SERVER ADAPTER YET");return false}
        if let legacy{let accepted=legacy.send(["t":"enter","v":vehicle.id]);onEnter?(vehicle.id,accepted);return accepted}
        if usesOriginalWorldProtocol{send(["t":"enter","v":vehicle.id]);return true}
        guard let entry=vehicleSeats.request(vehicle:vehicle.id,seat:seat)else{return false}
        var packet:[String:Any]=["t":"enter","v":vehicle.id,"seat":seat,"request":entry.request]
        if seat>0{packet["passenger"]=true};send(packet);return true
    }
    func cancelVehicleEntry(){
        guard let entry=vehicleSeats.cancel()else{return}
        send(["t":"exit","v":entry.seat.vehicle,"seat":entry.seat.index])
    }
    func sendPassengerPosition(_ position:SIMD3<Float>,heading:Float,action:Int,velocity:SIMD3<Float>,paused:Bool){
        guard isReady,let seat=vehicleSeats.passenger,[position.x,position.y,position.z,heading,velocity.x,velocity.y,velocity.z].allSatisfy(\.isFinite)else{return}
        var packet:[String:Any]=["t":"me","walking":true,"driving":false,"skin":localSkin,
            "riding":seat.vehicle,"seat":seat.index,"x":position.x,"y":position.y,"z":position.z,"heading":-heading,
            "health":wireHealth,"armour":wireArmour,"weapon":0,"move":0,"air":false,"crouch":false,"act":action,
            "vx":velocity.x,"vy":velocity.y,"vz":velocity.z,"paused":paused,"clock":Date().timeIntervalSince1970*1000]
        addPendingChat(to:&packet);send(packet)
    }
    func sendPassengerExit(_ feet:SIMD3<Float>,heading:Float){
        guard let seat=vehicleSeats.leavePassenger()else{return}
        send(["t":"exit","v":seat.vehicle,"seat":seat.index])
        sendPosition(feet,heading:heading,moving:false,running:false)
    }
    private func receiveVehicleEntry(_ message:[String:Any]){
        guard let id=message["v"]as?String,let accepted=message["ok"]as?Bool else{return}
        if usesOriginalWorldProtocol{onEnter?(id,accepted);return}
        let seat=NativeHealthPrediction.integer(message["seat"]) ?? 0
        let request=NativeHealthPrediction.integer(message["request"])
        guard (message["request"]==nil || request != nil),(message["seat"]==nil || NativeHealthPrediction.integer(message["seat"]) != nil),
              let result=vehicleSeats.receive(vehicle:id,seat:seat,accepted:accepted,request:request)else{return}
        if result.seat.index==0{onEnter?(id,result.accepted)}else{onPassengerEnter?(id,result.seat.index,result.accepted)}
    }
    func sendVehicleMove(_ id:String, state:[String:Any]) {
        var packet=state
        packet["t"]="vmove";packet["v"]=id
        send(packet)
    }
    func usedParachute() {if usesClientOwnedWeapons{return};send(["t":"usedParachute"])}
    func detonateSatchels() {
        if usesClientOwnedWeapons {onStatus?("LOCAL PLANTED-CHARGE DETONATION IS NOT AVAILABLE ON THIS CONNECTION YET");return}
        send(["t":"detonate"])
    }

    /// Public strike counter animates remote misses as well as damaging hits.
    /// It is independent of gun ammunition sequences and victim selection.
    @discardableResult func recordMeleeStrike(weapon: Int) -> Bool {
        if legacy != nil{guard isReady,health>0,!passive,(0...15).contains(weapon)else{return false};shots+=1;return true}
        guard isReady,socket != nil,health>0,!passive,(0...15).contains(weapon),(usesOriginalWorldProtocol || inventoryConnection != nil) else{return false}
        shots += 1
        return true
    }

    @discardableResult func sendMeleeHit(to player: String, weapon: Int = 0) -> Bool {
        if let legacy{return legacy.send(["t":"melee","to":player,"weapon":weapon])}
        if usesOriginalWorldProtocol {
            guard isReady,socket != nil,health>0,!passive,(0...15).contains(weapon),!player.isEmpty else{return false}
            return sendOriginal(["t":"hit","to":player,"n":1])
        }
        guard isReady,socket != nil, health > 0, !passive, (0...15).contains(weapon),
              let connection = inventoryConnection else { return false }
        send(["t": "hit", "to": player, "w": weapon, "c": connection])
        return true
    }

    @discardableResult func sendPistolShot(from origin: SIMD3<Float>, to hit: SIMD3<Float>,
                        player: String?, ticket: NativeShotTicket? = nil) -> Bool {
        sendWeaponShot(weapon: 22, from: origin, to: hit, player: player, ticket: ticket)
    }

    @discardableResult func sendOrdinaryShotBatch(weapon:Int,claims:[NativeLocalShots.Claim],ticket:NativeShotTicket?)->Bool {
        guard let packets=NativeLocalShotPackets.original(weapon:weapon,claims:claims)else{return false}
        if usesOriginalWorldProtocol {
            guard isReady,socket != nil,health>0,!passive else{return false}
            var sent=false
            for packet in packets {
                guard sendOriginal(packet)else{break};sent=true
            }
            if sent{shots+=1}
            return sent
        }
        if ordinaryShotGroupsEnabled,legacy==nil {
            guard isReady,let task=socket,health>0,!passive,let ticket,
                  ticket.connection==inventoryConnection,let first=packets.first,
                  let origin=first["o"],let end=first["h"],shotSequence.claim(ticket) else{return false}
            let groups=packets.map{packet -> [String:Any] in
                var group=packet;group["t"]=nil;group["w"]=nil;return group
            }
            let message:[String:Any]=["t":"shot","w":weapon,"s":ticket.sequence,"c":ticket.connection,
                                      "o":origin,"h":end,"rays":groups]
            guard let data=try? JSONSerialization.data(withJSONObject:message),let text=String(data:data,encoding:.utf8)else{
                requestInventoryResync();return false
            }
            shots+=1
            task.send(.string(text)){[weak self]error in
                DispatchQueue.main.async{
                    guard let self,self.socket === task,self.inventoryConnection==ticket.connection else{return}
                    if let error{self.failTransport(generation:self.transportGeneration,reason:error.localizedDescription)}
                }
            }
            // The negotiated server settles all target groups with this one
            // emission. A follow-up legacy hit would duplicate its authority.
            return true
        }
        // Existing SA-MP and older self-host adapters retain one compatible
        // target claim per emission until they negotiate grouped authority.
        guard let first=claims.first else{return false}
        return sendWeaponShot(weapon:weapon,from:SIMD3<Float>(first.origin),to:SIMD3<Float>(first.end),
            player:first.kind==1 ? first.target?.id:nil,ticket:ticket,
            hitType:first.kind,pellets:first.pellets,piece:first.target?.piece)
    }

    @discardableResult func sendWeaponShot(weapon: Int, from origin: SIMD3<Float>, to hit: SIMD3<Float>,
                        player: String?, ticket: NativeShotTicket? = nil,streamPlayers:[String]=[],
                        hitType:Int?=nil,pellets:Int=1,piece:Int?=nil) -> Bool {
        if let legacy{var packet:[String:Any]=["t":"shot","w":weapon,"o":[origin.x,origin.y,origin.z],"h":[hit.x,hit.y,hit.z]];if let player{packet["target"]=player};return legacy.send(packet)}
        if usesOriginalWorldProtocol {
            guard isReady,socket != nil,health>0,!passive,(16...43).contains(weapon),
                  [origin.x,origin.y,origin.z,hit.x,hit.y,hit.z].allSatisfy(\.isFinite) else{return false}
            let hitType=hitType ?? (player==nil ? 0:1)
            guard (0...4).contains(hitType),(1...100).contains(pellets) else{return false}
            var packet:[String:Any]=["t":"shot","w":weapon,
                "o":[Double(origin.x),Double(origin.y),Double(origin.z)],
                "h":[Double(hit.x),Double(hit.y),Double(hit.z)],"ht":hitType]
            if let player {packet["id"]=player}
            if pellets>1 {packet["n"]=pellets}
            if let piece,(1...9).contains(piece) {packet["bp"]=piece}
            guard sendOriginal(packet) else{return false};shots+=1;return true
        }
        guard isReady,let task = socket, health > 0, !passive, let ticket,
              ticket.connection == inventoryConnection, shotSequence.claim(ticket) else { return false }
        let effectTargets=NativeStreamShotClaims.normalized(streamPlayers)
        shots += 1
        var shot: [String: Any] = ["t": "shot", "w": weapon, "s": ticket.sequence, "c": ticket.connection,
                                   "o": [Double(origin.x), Double(origin.y), Double(origin.z)],
                                   "h": [Double(hit.x), Double(hit.y), Double(hit.z)]]
        if let hitType,(0...4).contains(hitType){shot["ht"]=hitType}
        if hitType==1,let player{shot["id"]=player}
        if let piece,(1...9).contains(piece){shot["bp"]=piece}
        guard let data = try? JSONSerialization.data(withJSONObject: shot), let text = String(data: data, encoding: .utf8) else {
            requestInventoryResync(); return false
        }
        task.send(.string(text)) { [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.socket === task, self.inventoryConnection == ticket.connection else { return }
                if let error { self.failTransport(generation: self.transportGeneration, reason: error.localizedDescription); return }
                if NativeStreamShotTargets.weapons.contains(weapon) {
                    let targets=self.streamShotClaims.take(weapon:weapon,connection:ticket.connection,players:effectTargets,
                        milliseconds:ProcessInfo.processInfo.systemUptime*1000)
                    for target in targets {self.send(["t":"hit","to":target,"w":weapon,"s":ticket.sequence,"c":ticket.connection])}
                } else if let player { self.send(["t": "hit", "to": player, "w": weapon, "s": ticket.sequence, "c": ticket.connection]) }
            }
        }
        return true
    }

    func respawn() {
        if let legacy{_=legacy.send(["t":"respawn"]);return}
        if usesOriginalWorldProtocol {
            guard isReady,originalRespawnRequested==nil else{return}
            if sendOriginal(["t":"escape","c":"respawn"]) {originalRespawnRequested=clock()};return
        }
        guard health == 0 else { return }
        if healthPrediction.active {
            guard isReady,let request=healthPrediction.respawn() else{return}
            sendHealthRequest(request);return
        }
        health = 100
        armour = 0
        onVitals?(health, armour)
        onRespawn?()
    }

    func syncVitals(from state: [String: Any]) {
        guard !usesOriginalWorldProtocol,legacy == nil else{return}
        if healthPrediction.active {_=applyAcknowledgedVitals(state);return}
        guard let current = state["health"] as? NSNumber,
              let protected = state["armour"] as? NSNumber else { return }
        let nextHealth = max(0, min(100, current.intValue))
        let nextArmour = max(0, min(100, protected.intValue))
        guard health != nextHealth || armour != nextArmour else { return }
        health = nextHealth
        armour = nextArmour
        onVitals?(health, armour)
    }

    func reportLocalHealth(_ value:Int) {
        if legacy != nil {
            if value<=0{_=reportLegacyFatal(weapon:255)}
            else if isReady,!legacySpectating,!legacyVitals.dead,Double(value)<legacyVitals.health{
                // An absolute compatibility setter does not identify a weapon
                // or a damage event. Actual fall/drown use reportLegacyDamage.
                if legacyVitals.seed(health:Double(value)){publishLegacyVitals()}
            }
            return
        }
        if usesOriginalWorldProtocol {
            if value<=0{killOriginalPlayer()}else if Double(value)<originalVitals.health{_=applyOriginalDamage(.init(damage:originalVitals.health-Double(value),weapon:54,quiet:true))};return
        }
        if healthPrediction.active {
            guard isReady,let request=healthPrediction.hurt(to:value) else{return}
            health=healthPrediction.health;armour=healthPrediction.armour;onVitals?(health,armour)
            sendHealthRequest(request);return
        }
        health=max(0,min(health,value));onVitals?(health,armour)
        if usesOriginalWorldProtocol,health==0 {reportOriginalDeath()}
    }

    func reportImpactDamage(_ value:Int) {
        if legacy != nil{_=reportLegacyDamage(Double(max(0,min(200,value))),weapon:54);return}
        if usesOriginalWorldProtocol{_=applyOriginalDamage(.init(damage:Double(max(0,min(200,value))),weapon:0,quiet:true));return}
        let damage=max(0,min(200,value));guard damage>0,health>0 else{return}
        if healthPrediction.active {
            guard isReady,let request=healthPrediction.impact(damage) else{return}
            health=healthPrediction.health;armour=healthPrediction.armour;onVitals?(health,armour)
            sendHealthRequest(request);return
        }
        let absorbed=min(armour,damage);armour-=absorbed;health=max(0,health-(damage-absorbed))
        onVitals?(health,armour)
        if usesOriginalWorldProtocol,health==0 {reportOriginalDeath()}
    }

    private func publishLegacyVitals(){health=legacyVitals.displayHealth;armour=legacyVitals.displayArmour;onVitals?(health,armour)}
    /// Applies a real locally observed hit once. A successful return means the
    /// local vital owner accepted it; RPC115 has no server health ACK/replay.
    @discardableResult func reportLegacyDamage(_ amount:Double,weapon:Int,source:UInt16=65535,body:Int=3)->Bool {
        guard let legacy,isReady,!legacySpectating,
              let damage=legacyVitals.hurt(amount,weapon:weapon,source:source,body:body)else{return false}
        _=legacy.send(["t":"takingDamage","amount":damage.amount,"weapon":damage.weapon,"source":Int(damage.source),"body":damage.body])
        publishLegacyVitals();return true
    }
    @discardableResult func reportLegacyFatal(weapon:Int,source:UInt16=65535)->Bool{
        guard legacy != nil,isReady,!legacySpectating,legacyVitals.kill(weapon:weapon,source:source)else{return false}
        publishLegacyVitals();return true
    }

    private func sendHealthRequest(_ request:NativeHealthPrediction.Request) {
        send(["t":"selfHealth","c":request.connection,"s":request.sequence,
              "kind":request.kind,"damage":request.damage])
    }
    @discardableResult private func applyAcknowledgedVitals(_ state:[String:Any])->Bool {
        let pendingRespawn=healthPrediction.pendingRespawn
        let epoch=transportGeneration
        guard let ack=state["healthAck"] as? [String:Any],let connection=ack["connection"] as? String,
              let processed=NativeHealthPrediction.integer(ack["processed"]),
              let revision=NativeHealthPrediction.integer(ack["revision"]),
              let hp=NativeHealthPrediction.integer(state["health"]),let armour=NativeHealthPrediction.integer(state["armour"]),
              healthPrediction.apply(health:hp,armour:armour,connection:connection,processed:processed,revision:revision) else{return false}
        health=healthPrediction.health;self.armour=healthPrediction.armour;onVitals?(health,self.armour)
        if let sequence=pendingRespawn,processed>=sequence,health>0,isReady,transportGeneration==epoch,
           healthPrediction.connection==connection,
           NativeHealthPrediction.integer(ack["respawned"])==sequence,sequence>deliveredRespawnSequence {
            deliveredRespawnSequence=sequence;onRespawn?()
        }
        return true
    }
    private func hitStatus(_ message:[String:Any])->String {
        if health==0{return "DEFEATED — RESPAWN TO CONTINUE"}
        return (message["parried"] as? Bool)==true ? "MELEE HIT BLOCKED":"HIT — \(health) HEALTH REMAINING"
    }
    private func deliverIncomingHit(_ message:[String:Any],wasAlive:Bool) {
        guard isReady else{return}
        let source=(message["from"] as? String).flatMap{players[$0]?.position}
        guard let hit=NativeIncomingHit(message,fallbackSource:source,wasAlive:wasAlive) else{return}
        if healthPrediction.active {
            if let raw=message["hitAck"] {
                guard let ack=raw as? [String:Any],let connection=ack["connection"] as? String,
                      connection==healthPrediction.connection,
                      let sequence=NativeHealthPrediction.integer(ack["sequence"]),sequence>0,
                      deliveredHitSequence.map({sequence>$0}) ?? true else{return}
                deliveredHitSequence=sequence
            } else {
                // Compatibility with earlier independent servers. Once a
                // sequence is observed, an unsequenced replay cannot downgrade it.
                guard deliveredHitSequence==nil,let ack=message["healthAck"] as? [String:Any],
                      let revision=NativeHealthPrediction.integer(ack["revision"]),
                      deliveredHitRevision.map({revision>$0}) ?? true else{return}
                deliveredHitRevision=revision
            }
        }
        onIncomingHit?(hit)
    }

    func sendExit(_ feet: SIMD3<Float>, parked position: SIMD3<Float>, heading: Float, pitch: Float, roll: Float,
                  vehicle: RemoteVehicle, vehicleHealth: Int,vehicleDamage: String = "",vehicleWork:Int?=nil,
                  footHeading:Float?=nil,legacyRotation:SIMD4<Float>?=nil) {
        guard isReady else { return }
        // A completed exit can face away from the parked chassis. Keep that
        // actor pose independent of both the body and the resumed camera.
        let facing=footHeading.flatMap{$0.isFinite ? $0:nil} ?? heading
        var parked=vehicle;parked.position=position;parked.heading=heading;parked.pitch=pitch;parked.roll=roll
        if vehicles[vehicle.id]==nil {vehicleOrder.append(vehicle.id)}
        parked.health=vehicleHealth;parked.damage=vehicleDamage
        if let vehicleWork {parked.work=max(0,min(2500,vehicleWork))}
        vehicles[vehicle.id]=parked
        onVehicles?(orderedVehicles)
        var parkedState:[String:Any]=["x":Double(position.x),"y":Double(position.y),"z":Double(position.z),
            "heading":-Double(heading),"pitch":Double(pitch),"roll":-Double(roll),"health":vehicleHealth,"damage":vehicleDamage]
        if let vehicleWork {parkedState["w"]=max(0,min(2500,vehicleWork))}
        if let legacy {
            var release:[String:Any]=["t":"exit","v":vehicle.id,"parked":parkedState,"life":wireHealth,"armour":wireArmour]
            if let q=legacyRotation{release["rotation"]=[q.x,q.y,q.z,q.w]}
            _=legacy.send(release)
            _=legacy.send(["t":"me","walking":true,"x":feet.x,"y":feet.y,"z":feet.z,"heading":-facing,"health":wireHealth,"armour":wireArmour,"deathReason":Int(legacyDeathReason),"deathKiller":Int(legacyDeathKiller)]);return
        }
        if usesOriginalWorldProtocol {
            var release:[String:Any]=["t":"exit","v":vehicle.id,"x":Double(position.x),"y":Double(position.y),"z":Double(position.z),
                "h":-Double(heading),"p":Double(pitch),"r":-Double(roll),"hp":vehicleHealth,"d":vehicleDamage]
            if let vehicleWork {release["w"]=max(0,min(2500,vehicleWork))}
            send(release)
            var actor:[String:Any]=["t":"me","walking":true,"skin":localSkin,"x":Double(feet.x),"y":Double(feet.y),"z":Double(feet.z),
                "heading":-Double(facing),"health":health,"armour":armour]
            addPendingChat(to:&actor);send(actor);return
        }
        send(["t": "me", "walking": true, "skin": localSkin,
              "vehicle": vehicle.id, "car": vehicle.code,
              "x": Double(feet.x), "y": Double(feet.y), "z": Double(feet.z),
              "heading": -Double(facing), "health": health, "armour": armour,
              "parked":parkedState])
    }

    private func stopOriginal(reason:String,authentication:Bool=false) {
        guard usesOriginalWorldProtocol else{return}
        recovery.stop();recoveryTimer?.cancel();recoveryTimer=nil
        closeSocket();publishState();onStatus?(reason)
        if authentication {onAuthenticationRequired?()}
    }
    @discardableResult private func sendOriginal(_ object:[String:Any],beforeReady:Bool=false)->Bool {
        guard usesOriginalWorldProtocol,let task=socket,(beforeReady || isReady),
              JSONSerialization.isValidJSONObject(object),
              let data=try? JSONSerialization.data(withJSONObject:object),let text=String(data:data,encoding:.utf8) else{return false}
        let generation=transportGeneration
        task.send(.string(text)){[weak self]error in
            guard let error else{return}
            DispatchQueue.main.async {
                guard let self,self.socket === task,self.transportGeneration==generation else{return}
                self.failTransport(generation:generation,reason:error.localizedDescription)
            }
        }
        return true
    }
    @discardableResult func sendOriginalGuns(_ rows:[[Int]])->Bool {
        guard NativeOriginalWorldProtocol.validGuns(rows) else{return false}
        return sendOriginal(["t":"guns","w":rows])
    }
    @discardableResult func sendOriginalCommand(_ packet:[String:Any])->Bool {
        guard packet["t"] as? String != "hi",packet["t"] as? String != "me" else{return false}
        return sendOriginal(packet)
    }
    /// A request only materializes the shared car. The existing registered
    /// vehicle reservation and entry ACK still own permission to drive it.
    @discardableResult func requestTrafficVehicle(_ id:UInt16)->Bool {
        guard canRequestTrafficVehicle,isReady,!serverInputBlocked,health>0 else{return false}
        let packet:[String:Any]=["t":"tcar","id":Int(id),"why":"door"]
        if usesOriginalWorldProtocol{return sendOriginalCommand(packet)}
        send(packet);return true
    }
    private func publishOriginalVitals(){
        health=originalVitals.displayHealth;armour=originalVitals.displayArmour;onVitals?(health,armour)
    }
    @discardableResult func applyOriginalDamage(_ hit:NativeOriginalWorldVitals.Hit,
        context:NativeOriginalWorldVitals.Context = .init())->NativeOriginalWorldVitals.Result {
        guard usesOriginalWorldProtocol,isReady else{return .init()}
        let epoch=transportGeneration,alive = !originalVitals.dead,result=originalVitals.hurt(hit,context:context)
        if result.applied{publishOriginalVitals()}
        guard isReady,transportGeneration==epoch else{return result}
        onOriginalHitResult?(result,hit)
        guard isReady,transportGeneration==epoch else{return result}
        if result.applied || result.parried {
            onIncomingHit?(NativeIncomingHit(original:hit,result:result,health:health,wasAlive:alive))
        }
        if result.killed,isReady,transportGeneration==epoch{reportOriginalDeath(by:hit.source,weapon:hit.weapon)}
        return result
    }
    func setOriginalHealth(_ value:Double){guard usesOriginalWorldProtocol else{return};if originalVitals.setHealth(value){publishOriginalVitals()}}
    func setOriginalArmour(_ value:Double){guard usesOriginalWorldProtocol else{return};if originalVitals.setArmour(value){publishOriginalVitals()}}
    func killOriginalPlayer(){
        guard usesOriginalWorldProtocol,!originalVitals.dead else{return}
        originalVitals.kill();publishOriginalVitals();reportOriginalDeath()
    }
    @discardableResult func deferOriginalFatal(_ hit:NativeOriginalWorldVitals.Hit,drivingCar:Bool,speed:Double)->Bool {
        guard usesOriginalWorldProtocol,isReady else{return false}
        return originalVitals.deferMovingCarFatal(hit,nowMilliseconds:clock()*1000,drivingCar:drivingCar,speed:speed) != nil
    }
    @discardableResult func deferOriginalSelfKill(drivingCar:Bool,speed:Double)->Bool {
        guard usesOriginalWorldProtocol,isReady else{return false}
        return originalVitals.deferMovingCarSelfKill(nowMilliseconds:clock()*1000,drivingCar:drivingCar,speed:speed) != nil
    }
    @discardableResult func deferOriginalImmediateFatal(_ hit:NativeOriginalWorldVitals.Hit)->Bool {
        guard usesOriginalWorldProtocol,isReady else{return false}
        return originalVitals.deferNativeExitFatal(hit,nowMilliseconds:clock()*1000) != nil
    }
    @discardableResult func deferOriginalImmediateSelfKill()->Bool {
        guard usesOriginalWorldProtocol,isReady else{return false}
        return originalVitals.deferNativeExitSelfKill(nowMilliseconds:clock()*1000) != nil
    }
    func cancelOriginalFatal(){guard usesOriginalWorldProtocol else{return};originalVitals.cancelPendingFatal()}
    func clearOriginalChat(){guard usesOriginalWorldProtocol else{return};chatMessages.removeAll();onChat?([])}
    func readyOriginalFatal(driving:Bool,wrecked:Bool)->NativeOriginalWorldVitals.PendingFatal? {
        guard usesOriginalWorldProtocol,isReady else{return nil}
        return originalVitals.readyFatal(nowMilliseconds:clock()*1000,driving:driving,wrecked:wrecked)
    }
    @discardableResult func commitOriginalFatal(_ token:UInt64)->Bool {
        guard usesOriginalWorldProtocol,isReady,let cause=originalVitals.consumeFatal(token:token)else{return false}
        switch cause{case .selfKill:killOriginalPlayer();case .hit(let hit):_=applyOriginalDamage(hit)};return true
    }
    func respawnOriginalPlayer(){
        guard usesOriginalWorldProtocol else{return}
        originalRespawnWasDead=originalVitals.dead;originalVitals.respawn()
        originalDeathSent=false;originalRespawnRequested=nil;publishOriginalVitals();onRespawn?()
    }
    private func reportOriginalDeath(by:String?=nil,weapon:Int?=nil) {
        guard usesOriginalWorldProtocol,isReady,!originalDeathSent else{return}
        if var position=originalLatestPosition {
            if position["driving"] as? Bool == true {position["life"]=0}else{position["health"]=0}
            addPendingChat(to:&position);send(position)
        }
        var packet:[String:Any]=["t":"died"]
        if let by,!by.isEmpty {packet["by"]=by}
        if let weapon,(0...255).contains(weapon) {packet["w"]=weapon}
        if sendOriginal(packet) {originalDeathSent=true}
    }
    private func originalWho() {
        guard usesOriginalWorldProtocol,isReady else{return}
        let ids=originalStream.wanted(now:clock()*1000)
        if !ids.isEmpty {_=sendOriginal(["t":"who","ids":ids])}
    }
    private func receiveOriginalBinary(_ data:Data,generation:UInt64) {
        guard usesOriginalWorldProtocol,transportGeneration==generation,socket != nil else{return}
        for event in originalStream.read(data,now:clock()*1000) {
            guard transportGeneration==generation,socket != nil else{return}
            switch event {
            case .players(let rows):updateRows(rows)
            case .shot(let shot):
                onOriginalShot?(shot)
            case .extensionRecord(let tag,let payload):
                let now=Date().timeIntervalSince1970*1000+serverTimeOffsetMilliseconds
                if let event=try? NativeAmbientPedestrianProtocol.decode(tag:tag,payload:payload,nowServerMilliseconds:now) {
                    onAmbientPedestrianEvent?(event,now,clock())
                }
                guard transportGeneration==generation,socket != nil else{return}
                if let event=try? NativeAmbientTrafficProtocol.decode(tag:tag,payload:payload,nowServerMilliseconds:now) {
                    onAmbientTrafficEvent?(event,now,clock())
                }
                guard transportGeneration==generation,socket != nil else{return}
                onOriginalRecord?(tag,payload)
            }
        }
        recovery.received(generation:generation,now:clock());originalWho()
    }
    /// The original service owns authentication, inventory totals and escape
    /// approval. Nothing in this branch fabricates an independent-server ACK.
    private func handleOriginal(_ message:[String:Any],generation:UInt64)->Bool {
        guard usesOriginalWorldProtocol else{return false}
        guard originalCommandDepth<8 else{return true}
        originalCommandDepth+=1;defer{originalCommandDepth-=1}
        switch message["t"] as? String {
        case "login":stopOriginal(reason:"SIGN IN TO THE ORIGINAL SERVER TO CONNECT",authentication:true);return true
        case "hello":
            guard NativeOriginalWorldProtocol.acceptsProtocol(message["protocol"]) else {
                stopOriginal(reason:"ORIGINAL SERVER PROTOCOL IS UNSUPPORTED — CLIENT UPDATE REQUIRED");return true
            }
            if let time=(message["time"] as? NSNumber)?.doubleValue,time.isFinite {
                serverTimeOffsetMilliseconds=time-Date().timeIntervalSince1970*1000
                originalStream.clock(serverMilliseconds:time,localMilliseconds:clock()*1000)
            }
            ambientBinaryEnabled=true
            onAmbientPedestrianConfiguration?((message["peds"]as?NSNumber)?.doubleValue ?? 0,message["paths"]as?String)
            guard transportGeneration==generation,socket != nil else{return true}
            onAmbientTrafficConfiguration?((message["traffic"]as?NSNumber)?.doubleValue ?? 0,message["roads"]as?String)
            guard transportGeneration==generation,socket != nil else{return true}
            originalFrozen=false
            if let life=message["life"] as? [Any],life.count==2,
               let hp=NativeOriginalWorldCommands.number(life[0]),let ap=NativeOriginalWorldCommands.number(life[1]) {
                _=originalVitals.begin(health:hp,armour:ap,wasted:NativeOriginalWorldCommands.boolean(message["wasted"]) == true)
                publishOriginalVitals()
            }
            guard transportGeneration==generation,socket != nil else{return true}
            if let spot=message["spot"] as? [NSNumber],spot.count==4,spot.allSatisfy({$0.floatValue.isFinite}) {
                onTeleport?(SIMD3(spot[0].floatValue,spot[1].floatValue,spot[2].floatValue),-spot[3].floatValue)
            }
            guard transportGeneration==generation,socket != nil else{return true}
            let day=message["day"] as? [String:Any]
            onEnvironment?((message["weather"] as? NSNumber)?.intValue,(day?["shift"] as? NSNumber)?.doubleValue,(day?["hold"] as? NSNumber)?.doubleValue)
            guard transportGeneration==generation,socket != nil else{return true}
            recovery.received(.hello,generation:generation,now:clock());publishState()
            _=sendOriginal(["t":"board"],beforeReady:true);return true
        case "guns":
            guard NativeOriginalWorldProtocol.validGuns(message["w"]),let rows=message["w"] else{return true}
            let back=message["back"] as? Bool == true
            onOriginalGuns?(rows,back)
            guard transportGeneration==generation,socket != nil else{return true}
            if !back {recovery.received(.inventory,generation:generation,now:clock());publishState()}
            return true
        case "all":
            if let value=message["protocol"],!NativeOriginalWorldProtocol.acceptsProtocol(value) {
                stopOriginal(reason:"ORIGINAL SERVER PROTOCOL CHANGED — CLIENT UPDATE REQUIRED");return true
            }
            if let orders=message["orders"] as? [[String:Any]] {
                for order in orders.prefix(128) {handle(order,generation:generation);if transportGeneration != generation || socket==nil{return true}}
            }
            if let level=message["traffic"]as?NSNumber {
                onAmbientTrafficConfiguration?(level.doubleValue,message["roads"]as?String)
                guard transportGeneration==generation,socket != nil else{return true}
            }
            if let name=message["you"] as? String,!name.isEmpty {localName=name}
            if let amount=message["cash"] as? NSNumber,amount.doubleValue.isFinite {cash=amount.intValue}
            if let heard=NativeHealthPrediction.integer(message["heard"]) {originalHeard=max(originalHeard ?? 0,heard)}
            if let lines=message["chat"] as? [[Any]] {receiveChat(lines)}
            if let rows=message["cars"] as? [[Any]] {updateRows(rows)}
            else if let near=message["near"] as? [[Any]] {
                updateRows(originalStream.near(near,serverTime:(message["time"] as? NSNumber)?.doubleValue,now:clock()*1000))
            }
            if let rows=message["vehicles"] as? [[Any]] {
                vehicles.removeAll();vehicleOrder.removeAll()
                for row in rows {if let vehicle=RemoteVehicle(row:row) {if vehicles[vehicle.id]==nil{vehicleOrder.append(vehicle.id)};vehicles[vehicle.id]=vehicle}}
                onVehicles?(orderedVehicles)
            }
            guard transportGeneration==generation,socket != nil else{return true}
            if message["you"] as? String != nil,(message["cars"] is [[Any]] || message["near"] is [[Any]]) {
                recovery.received(.world,generation:generation,now:clock());publishState()
            } else {recovery.received(generation:generation,now:clock())}
            originalWho();onOriginalCommand?(message);return true
        case "peds","traffic":
            if ambientBinaryEnabled,let level=message["level"]as?NSNumber {
                if message["t"]as?String=="traffic"{onAmbientTrafficConfiguration?(level.doubleValue,message["roads"]as?String)}
                else{onAmbientPedestrianConfiguration?(level.doubleValue,message["paths"]as?String)}
            }
            return true
        case "shot":
            onOriginalShot?(message);return true
        case "hit":
            if NativeOriginalWorldCommands.truthy(message["car"]) {onOriginalVehicleHit?(message);return true}
            guard isReady,originalFatal==nil,let amount=NativeOriginalWorldCommands.number(message["d"]),amount>0 else{return true}
            var point:SIMD3<Double>?
            if let p=message["p"]as?[Any],p.count==3,
               let x=NativeOriginalWorldCommands.number(p[0]),let y=NativeOriginalWorldCommands.number(p[1]),let z=NativeOriginalWorldCommands.number(p[2]){point=SIMD3(x,y,z)}
            let hit=NativeOriginalWorldVitals.Hit(damage:amount,weapon:NativeOriginalWorldCommands.integer(message["w"]) ?? 0,
                source:message["from"]as?String,point:point,piece:NativeOriginalWorldCommands.integer(message["bp"]))
            if let handler=onOriginalHit{handler(hit)}else{_=applyOriginalDamage(hit)}
            return true
        case "vhit":onOriginalVehicleHit?(message);return true
        case "escape":
            guard message["c"] as? String == "respawn",originalRespawnRequested != nil else {onOriginalCommand?(message);return true}
            originalRespawnRequested=nil
            if NativeOriginalWorldCommands.truthy(message["go"]) {
                respawnOriginalPlayer()
            } else {onStatus?("ORIGINAL SERVER DECLINED RESPAWN")}
            onOriginalCommand?(message);return true
        case "wake":
            if let at=message["at"] as? [NSNumber],at.count==4,at.allSatisfy({$0.floatValue.isFinite}) {
                respawnOriginalPlayer()
                onTeleport?(SIMD3(at[0].floatValue,at[1].floatValue,at[2].floatValue+0.2),-at[3].floatValue)
            }
            return true
        case "staff","fix","flip","slap","dress","tp","day","weather","passive","shield","name","style","dose","cash","collect":
            for event in NativeOriginalWorldCommands.decode(message){
                switch event {
                case .staff(let staff):if let freeze=staff.freeze{originalFrozen=freeze}
                case .cash(let amount):cash=amount<=Double(Int.min) ? Int.min:amount>=Double(Int.max) ? Int.max:Int(amount)
                case .name(let name):if !name.isEmpty{localName=name}
                case .passive(let on,_):passive=on
                default:break
                }
                onOriginalEvent?(event,message)
                guard transportGeneration==generation,socket != nil else{return true}
            }
            onOriginalCommand?(message);return true
        case "inventory","couplings","vitals","flightgear":return true
        case "kick":stopOriginal(reason:(message["reason"] as? String) ?? "ORIGINAL SERVER CLOSED THIS SESSION");return true
        default:
            let handled:Set<String>=["pong","projectiles","projectile","weather","day","cars","gone","chat","board","note","passive","flightgear","vitals","veh","spawned","vgone","enter","tp"]
            if let type=message["t"] as? String,!handled.contains(type) {onOriginalCommand?(message);return true}
            return false
        }
    }

    private func send(_ object: [String: Any], allowBeforeReady: Bool = false) {
        if let legacy{if isReady || allowBeforeReady{_=legacy.send(object)};return}
        guard isReady || allowBeforeReady else { return }
        // This is the sole self-host me serialization boundary, including
        // normal foot/driver, passenger and explicit exit producers. Cleanup
        // callbacks cannot send an old pose while a placement is in progress.
        let packet:[String:Any]
        if usesOriginalWorldProtocol {packet=object}
        else {
            guard object["t"]as?String != "me" || isReady,
                  let stamped=placementSession.stamping(object)else{return}
            packet=stamped
        }
        guard let task = socket, let data = try? JSONSerialization.data(withJSONObject: packet),
              let text = String(data: data, encoding: .utf8) else { return }
        task.send(.string(text)) { [weak self] error in
            guard let error else { return }
            DispatchQueue.main.async {
                guard let self, self.socket === task else { return }
                self.failTransport(generation: self.transportGeneration, reason: error.localizedDescription)
            }
        }
    }

    private func receive() {
        guard let task = socket else { return }
        let generation = transportGeneration
        task.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self, self.socket === task, self.transportGeneration == generation else { return }
                switch result {
                case .failure(let error):
                    self.failTransport(generation: self.transportGeneration, reason: error.localizedDescription)
                case .success(let message):
                    let data: Data
                    switch message {
                    case .string(let text): data = Data(text.utf8)
                    case .data(let bytes): data = bytes
                    @unknown default: return
                    }
                    if let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] { self.handle(object, generation: generation) }
                    else if self.usesOriginalWorldProtocol {self.receiveOriginalBinary(data,generation:generation)}
                    else if self.ambientBinaryEnabled {
                        let now=Date().timeIntervalSince1970*1000+self.serverTimeOffsetMilliseconds
                        if self.selfhostPedestriansEnabled,let events=try? NativeAmbientPedestrianProtocol.decodeMessage(data,nowServerMilliseconds:now) {
                            for event in events {
                                guard self.socket === task,self.transportGeneration==generation else{break}
                                self.onAmbientPedestrianEvent?(event,now,self.clock())
                            }
                        }
                        guard self.socket === task,self.transportGeneration==generation else{return}
                        if let events=try? NativeAmbientTrafficProtocol.decodeMessage(data,nowServerMilliseconds:now) {
                            for event in events {
                                guard self.socket === task,self.transportGeneration==generation else{break}
                                self.onAmbientTrafficEvent?(event,now,self.clock())
                            }
                        }
                    }
                    guard self.socket === task, self.transportGeneration == generation else { return }
                    self.receive()
                }
            }
        }
    }

    private func handle(_ message: [String: Any], generation: UInt64) {
        guard transportGeneration==generation,socket != nil else{return}
        if usesOriginalWorldProtocol,handleOriginal(message,generation:generation) {return}
        switch message["t"] as? String {
        case "peds":
            if usesOriginalWorldProtocol || selfhostPedestriansEnabled,let level=message["level"]as?NSNumber {
                onAmbientPedestrianConfiguration?(level.doubleValue,message["paths"]as?String)
            }
        case "traffic":
            if ambientBinaryEnabled,let level=message["level"]as?NSNumber {
                onAmbientTrafficConfiguration?(level.doubleValue,message["roads"]as?String)
            }
        case "gangs":
            if ambientBinaryEnabled{onOriginalCommand?(message)}
        case "pong":
            if let echoed = (message["c"] as? NSNumber)?.doubleValue, echoed.isFinite,
               let time = (message["s"] as? NSNumber)?.doubleValue, time.isFinite {
                recovery.received(generation: generation, now: clock())
            }
        case "projectiles":
            if let rows = message["rows"] as? [[String: Any]] { onProjectiles?(rows) }
        case "projectile":
            if let event = message["event"] as? [String:Any], event["type"] as? String == "blast",
               let weapon = event["weapon"] as? Int, let position = event["position"] as? [NSNumber], position.count == 3 {
                onBlast?(weapon,SIMD3(position[0].floatValue,position[1].floatValue,position[2].floatValue))
            }
        case "shot":
            // The independent server forwards the same normalized ray and
            // snapshot firing counter. Let its observer use the same marker
            // owner as the original-world adapter, with no duplicate sound.
            if let onOriginalShot {onOriginalShot(message)}
            else if let weapon = message["w"] as? Int {onWeaponSound?(weapon)}
        case "struck":
            guard isReady,ordinaryShotGroupsEnabled,message["c"]as?String==inventoryConnection,
                  let sequence=NativePlacementSession.integer(message["s"]),sequence>0 else{return}
            onAcceptedStrike?(message)
        case "inventory":
            if let state = message["state"] as? [String: Any], let ack = NativeInventoryAcknowledgement(state),
               ack.connection == inventoryConnection, NativeConnectionRecovery.validInventory(state) {
                shotSequence.observeAcknowledgement(ack.processedShot)
                resynchronizingInventory = false; onInventory?(state)
                recovery.received(.inventory, generation: generation, now: clock()); publishState()
            }
        case "couplings":
            receiveCouplings(message,generation:generation)
        case "hello":
            guard NativePlacementSession.integer(message["inventoryAck"])==1,
                  let nonce=message["inventoryConnection"]as?String,let task=socket else{
                onStatus?("THIS SERVER NEEDS NATIVE INVENTORY ACKNOWLEDGEMENTS TO ENABLE FIRING");return
            }
            if let announced=announcedInventoryConnection,announced != nonce {
                failTransport(generation:generation,reason:"CONNECTION NAMESPACE CHANGED — RECONNECTING");return
            }
            guard shotSequence.negotiate(nonce)else{
                failTransport(generation:generation,reason:"INVALID CONNECTION NAMESPACE — RECONNECTING");return
            }
            let freshHello=announcedInventoryConnection != nonce
            let placement=placementSession.hello(message,connection:nonce,fresh:freshHello)
            if case .invalid=placement {
                failTransport(generation:generation,reason:"INVALID AUTHORITATIVE PLACEMENT — RECONNECTING");return
            }
            if freshHello {
                couplingAcknowledgements=NativeHealthPrediction.integer(message["couplingAck"])==1
                ordinaryShotGroupsEnabled=NativeHealthPrediction.integer(message["ordinaryShots"])==1
                announcedInventoryConnection=nonce;onInventoryConnection?(nonce)
            }
            guard transportGeneration==generation,socket === task,inventoryConnection==nonce else{return}
            if let time=(message["time"]as?NSNumber)?.doubleValue,time.isFinite {serverTimeOffsetMilliseconds=time-Date().timeIntervalSince1970*1000}
            selfhostTrafficEnabled=NativePlacementSession.integer(message["trafficProtocol"])==38
            selfhostPedestriansEnabled=NativePlacementSession.integer(message["npcProtocol"])==38
            ambientBinaryEnabled=selfhostPedestriansEnabled || selfhostTrafficEnabled
            // Duplicate hello packets can revoke a channel. Publish zero to
            // its scene owner as well as retiring the decoder/command flag.
            onAmbientPedestrianConfiguration?(selfhostPedestriansEnabled ? (message["peds"]as?NSNumber)?.doubleValue ?? 0:0,
                                              selfhostPedestriansEnabled ? message["paths"]as?String:nil)
            guard transportGeneration==generation,socket === task,inventoryConnection==nonce else{return}
            onAmbientTrafficConfiguration?(ambientBinaryEnabled ? (message["traffic"]as?NSNumber)?.doubleValue ?? 0:0,
                                          ambientBinaryEnabled ? message["roads"]as?String:nil)
            guard transportGeneration==generation,socket === task,inventoryConnection==nonce else{return}
            if case .place(let transaction)=placement {
                guard applyPlacement(transaction,generation:generation,task:task)else{return}
            }else if freshHello,let spot=message["spot"]as?[NSNumber],spot.count>=3 {
                onTeleport?(SIMD3(spot[0].floatValue,spot[1].floatValue,spot[2].floatValue),
                            spot.count>3 ? -spot[3].floatValue:nil)
            }
            guard transportGeneration==generation,socket != nil else{return}
            let day = message["day"] as? [String: Any]
            onEnvironment?((message["weather"] as? NSNumber)?.intValue,
                           (day?["shift"] as? NSNumber)?.doubleValue,
                           (day?["hold"] as? NSNumber)?.doubleValue)
            guard transportGeneration==generation,socket != nil else{return}
            if let life = message["life"] as? [NSNumber], life.count >= 2 {
                let hp=max(0,min(100,life[0].intValue)),protected=max(0,min(100,life[1].intValue))
                var published=false
                if let ack=message["healthAck"] as? [String:Any],
                   let connection=ack["connection"] as? String,connection==inventoryConnection,
                   let processed=NativeHealthPrediction.integer(ack["processed"]),
                   let revision=NativeHealthPrediction.integer(ack["revision"]) {
                    if healthPrediction.connection==connection {
                        published=applyAcknowledgedVitals(["health":hp,"armour":protected,"healthAck":ack])
                        guard transportGeneration==generation,socket != nil else{return}
                    } else {
                        healthPrediction.begin(connection:connection,health:hp,armour:protected,revision:revision,processed:processed)
                        deliveredRespawnSequence=processed
                        deliveredHitRevision=nil;deliveredHitSequence=nil
                    }
                    health=healthPrediction.health;armour=healthPrediction.armour
                } else if healthPrediction.connection != nonce {
                    healthPrediction.disconnect();health=hp;armour=protected
                }
                if !published {onVitals?(health, armour)}
            }
            guard transportGeneration==generation,socket != nil else{return}
            recovery.received(.hello, generation: generation, now: clock()); publishState()
            send(["t": "board"], allowBeforeReady: true)
        case "weather":
            onEnvironment?((message["weather"] as? NSNumber)?.intValue ?? (message["w"] as? NSNumber)?.intValue, nil, nil)
        case "day":
            onEnvironment?(nil, (message["shift"] as? NSNumber)?.doubleValue,
                           (message["hold"] as? NSNumber)?.doubleValue)
        case "all":
            guard let name = message["you"] as? String, !name.isEmpty,
                  message["cars"] is [[Any]], message["vehicles"] is [[Any]],
                  message["chat"] is [[Any]], let amount = (message["cash"] as? NSNumber)?.doubleValue,
                  amount.isFinite else { return }
            if ambientBinaryEnabled,let level=message["traffic"]as?NSNumber {
                onAmbientTrafficConfiguration?(level.doubleValue,message["roads"]as?String)
                guard transportGeneration==generation,socket != nil else{return}
            }
            localName = (message["you"] as? String) ?? localName
            cash = (message["cash"] as? Int) ?? cash
            if let rows = message["chat"] as? [[Any]] { receiveChat(rows) }
            updateRows(message["cars"])
            if let rows = message["vehicles"] as? [[Any]] {
                vehicles.removeAll();vehicleOrder.removeAll()
                for row in rows {
                    guard let vehicle=RemoteVehicle(row:row) else{continue}
                    if vehicles[vehicle.id]==nil {vehicleOrder.append(vehicle.id)}
                    vehicles[vehicle.id]=vehicle
                }
                onVehicles?(orderedVehicles)
            }
            recovery.received(.world, generation: generation, now: clock()); publishState()
        case "cars": updateRows(message["c"])
        case "gone":
            if let id = message["id"] as? String {
                if usesOriginalWorldProtocol {originalStream.gone(id)}
                players.removeValue(forKey:id); remoteAnimationTimes.removeValue(forKey:id)
                playerOrder.removeAll{$0==id};onPlayers?(orderedPlayers)
            }
        case "chat":
            if let rows = message["lines"] as? [[Any]] { receiveChat(rows) }
        case "board":
            let rows = (message["rows"] as? [[Any]]) ?? []
            let names = rows.compactMap { row -> String? in
                guard row.count > 1 else { return nil }
                return row[1] as? String
            }
            onPresence?((message["players"] as? Int) ?? rows.count, names)
        case "note":
            if let note = message["text"] as? String {
                onStatus?(note.uppercased())
                if note.hasPrefix("[Group]") {
                    chatMessages.append(note)
                    chatMessages = Array(chatMessages.suffix(50))
                    onChat?(chatMessages)
                }
            }
        case "passive":
            passive = message["on"] as? Bool == true
        case "flightgear":
            onFlightGear?(message["parachute"] as? Bool == true,message["jetpack"] as? Bool == true)
        case "vitals":
            if healthPrediction.active {_=applyAcknowledgedVitals(message);break}
            if let value = message["health"] as? Int { health = max(0, min(100,value)) }
            if let value = message["armour"] as? Int { armour = max(0,min(100,value)) }
            onVitals?(health, armour)
        case "hit":
            let hitEpoch=transportGeneration
            let wasAlive=health>0
            if healthPrediction.active {
                if applyAcknowledgedVitals(message),isReady {
                    deliverIncomingHit(message,wasAlive:wasAlive)
                    if isReady,transportGeneration==hitEpoch {onStatus?(health == 0 ? "DEFEATED — RESPAWN TO CONTINUE":hitStatus(message))}
                }
                break
            }
            let damage = max(0, (message["d"] as? NSNumber)?.intValue ?? 0)
            let absorbed = min(armour, damage)
            armour -= absorbed
            health = max(0, health - (damage - absorbed))
            onVitals?(health, armour)
            if isReady,transportGeneration==hitEpoch {
                deliverIncomingHit(message,wasAlive:wasAlive)
                if isReady,transportGeneration==hitEpoch {onStatus?(health == 0 ? "DEFEATED — RESPAWN TO CONTINUE" :"HIT — \(health) HEALTH REMAINING")}
            }
        case "veh", "spawned":
            if let row = message["v"] as? [Any], let vehicle = RemoteVehicle(row: row) {
                if vehicles[vehicle.id]==nil {vehicleOrder.append(vehicle.id)}
                vehicles[vehicle.id] = vehicle
                onVehicles?(orderedVehicles)
                // This is an explicit original-server seating command, not an
                // independent-server inventory/seat acknowledgement.
                if usesOriginalWorldProtocol,message["t"]as?String=="spawned",
                   let flag=message["in"]as?NSNumber,CFGetTypeID(flag)==CFBooleanGetTypeID(),flag.boolValue,
                   transportGeneration==generation,socket != nil {
                    onEnter?(vehicle.id,true)
                }
            }
        case "vgone":
            if let id = message["id"] as? String {
                vehicleSeats.remove(vehicle:id)
                vehicles.removeValue(forKey: id)
                vehicleOrder.removeAll{$0==id}
                onVehicleRemoved?(id)
                onVehicles?(orderedVehicles)
            }
        case "enter":
            receiveVehicleEntry(message)
        case "tp":
            if positionAcknowledgements {
                guard let connection=inventoryConnection,let task=socket,
                      let transaction=placementSession.teleport(message,connection:connection)else{return}
                _=applyPlacement(transaction,generation:generation,task:task)
            }else if let x=(message["x"]as?NSNumber)?.floatValue,
                     let y=(message["y"]as?NSNumber)?.floatValue,
                     let z=(message["z"]as?NSNumber)?.floatValue {
                onTeleport?(SIMD3(x,y,z),(message["h"]as?NSNumber).map{-$0.floatValue * .pi/180})
            }
        default: break
        }
    }

    private func applyPlacement(_ transaction:NativePlacementSession.Transaction,
                                generation:UInt64,task:URLSessionWebSocketTask)->Bool {
        guard socket === task,transportGeneration==generation,
              inventoryConnection==transaction.envelope.connection,placementSession.owns(transaction)else{return false}
        guard let apply=onTeleport else{
            failTransport(generation:generation,reason:"NO AUTHORITATIVE PLACEMENT OWNER — RECONNECTING");return false
        }
        // The server revoked occupancy. Drop local seat/boarding correlation
        // before the owner cleans up driver/passenger UI and physical state.
        vehicleSeats.clearOccupancy()
        apply(transaction.position,transaction.heading)
        guard socket === task,transportGeneration==generation,
              inventoryConnection==transaction.envelope.connection else{return false}
        return placementSession.commit(transaction)
    }

    private func updateRows(_ value: Any?) {
        guard let rows = value as? [[Any]] else { return }
        var updated: [String: RemotePlayer] = [:]
        var incomingOrder:[String]=[]
        for row in rows where row.count >= 6 {
            guard let id = row[0] as? String,
                  let name = row[1] as? String,
                  let x = (row[3] as? NSNumber)?.floatValue,
                  let y = (row[4] as? NSNumber)?.floatValue,
                  let z = (row[5] as? NSNumber)?.floatValue else { continue }
            if updated[id]==nil {incomingOrder.append(id)}
            let code = row[2] as? String ?? "s7"
            let driving = !code.hasPrefix("s")
            let vehicleID = driving && row.count > 35 ? row[35] as? String : nil
            let riding:(String,Int)? = {
                guard !driving,row.count>34,let value=row[34] as? [Any],value.count==2,
                      let id=value[0] as? String,NativeVehicleSeatSession.validID(id),
                      let seat=NativeHealthPrediction.integer(value[1]),(1...15).contains(seat)else{return nil}
                return (id,seat)
            }()
            let wireAnimation = row.count > 41 ? row[41] as? String ?? "" : ""
            let mappedAnimation = NativePedestrianMotion.clip(forWire: wireAnimation,
                weapon: row.count > 27 ? (row[27] as? NSNumber)?.intValue ?? 0 : 0,
                health: row.count > 18 && !driving ? (row[18] as? NSNumber)?.intValue ?? 100 : 100)
            let animation = !wireAnimation.isEmpty && ["idle_stance","gun_stand"].contains(mappedAnimation) ? wireAnimation : mappedAnimation
            let action = row.count > 32 ? ((row[32] as? NSNumber)?.intValue ?? 0) & 63 : 0
            let swimClips = ["swim_tread","swim_breast","swim_crawl","swim_dive_under","swim_under","swim_glide","swim_jumpout"]
            let visibleAnimation = (10...16).contains(action) ? "swim/"+swimClips[action-10]+([13,16].contains(action) ? "/n/1" : "/l/1") : animation
            let signature = visibleAnimation + ":" + (row.count > 29 ? String(describing: row[29]) : "0")
            if remoteAnimationTimes[id]?.0 != signature {
                remoteAnimationTimes[id] = (signature, ProcessInfo.processInfo.systemUptime)
            }
            updated[id] = RemotePlayer(id: id, name: name, position: SIMD3(x, y, z),
                                       code: code,
                                       heading: row.count > 6 ? -((row[6] as? NSNumber)?.floatValue ?? 0) : 0,
                                       pitch: row.count > 7 ? (row[7] as? NSNumber)?.floatValue ?? 0 : 0,
                                       roll: row.count > 8 ? -((row[8] as? NSNumber)?.floatValue ?? 0) : 0,
                                       speed: row.count > 9 ? (row[9] as? NSNumber)?.floatValue ?? 0 : 0,
                                       steer: row.count > 10 ? (row[10] as? NSNumber)?.floatValue ?? 0 : 0,
                                       skin: driving && row.count > 31 ? (row[31] as? NSNumber)?.intValue ?? 7 : Int(code.dropFirst()) ?? 7,
                                       animation: visibleAnimation,
                                       animationStarted: remoteAnimationTimes[id]?.1 ?? ProcessInfo.processInfo.systemUptime,
                                       weapon: row.count > 27 ? (row[27] as? NSNumber)?.intValue ?? 0 : 0,
                                       vehicleID: vehicleID,
                                       vehicleHealth: driving && row.count > 18 ? (row[18] as? NSNumber)?.intValue ?? 1000 : 1000,
                                       vehicleDamage: driving && row.count > 19 ? row[19] as? String ?? "" : "",
                                       lights: driving && row.count > 12 && (row[12] as? NSNumber)?.boolValue == true,
                                       horn: driving && row.count > 17 ? (row[17] as? NSNumber)?.intValue ?? 0 : 0,
                                       movementRatio:row.count>24 ? (row[24] as? NSNumber)?.floatValue ?? 0:0,
                                       airborne:row.count>25 && (row[25] as? NSNumber)?.boolValue == true,
                                       crouching:row.count>26 && (row[26] as? NSNumber)?.boolValue == true,
                                       aim:row.count>28 ? (row[28] as? NSNumber)?.floatValue:nil,
                                       action:row.count>32 ? (row[32] as? NSNumber)?.intValue ?? 0:0,
                                       velocity:SIMD3((row.count>13 ? (row[13] as? NSNumber)?.floatValue:nil) ?? 0,(row.count>14 ? (row[14] as? NSNumber)?.floatValue:nil) ?? 0,(row.count>15 ? (row[15] as? NSNumber)?.floatValue:nil) ?? 0),
                                       angularVelocity:SIMD3((row.count>20 ? (row[20] as? NSNumber)?.floatValue:nil) ?? 0,(row.count>21 ? (row[21] as? NSNumber)?.floatValue:nil) ?? 0,(row.count>22 ? (row[22] as? NSNumber)?.floatValue:nil) ?? 0),
                                       shotCount:row.count>29 ? (row[29] as? NSNumber)?.intValue ?? 0:0,
                                       paused:row.count>36 && (row[36] as? NSNumber)?.boolValue == true,
                                       down:row.count>38 ? (row[38] as? NSNumber)?.intValue ?? 0:0,
                                       scriptAnimation:wireAnimation.isEmpty ? nil:wireAnimation,
                                       ridingVehicleID:riding?.0,
                                       ridingSeat:riding?.1 ?? 0,
                                       supportVehicleID:row.count>39 ? (row[39] as? [Any])?.first as? String:nil,
                                       supportOffset:row.count>39 ? (row[39] as? [Any]).flatMap {v in guard v.count>=4,let x=(v[1] as? NSNumber)?.floatValue,let y=(v[2] as? NSNumber)?.floatValue,let z=(v[3] as? NSNumber)?.floatValue else{return nil};return SIMD3(x,y,z)} ?? .zero:.zero,
                                       kit:row.count>42 ? (row[42] as? [NSNumber])?.map(\.floatValue):nil,
                                       packetReceivedAt:ProcessInfo.processInfo.systemUptime,
                                       packetClockMilliseconds:row.count>16 ? (row[16] as? NSNumber)?.doubleValue ?? 0:0,
                                       latencyMilliseconds:row.count>23 ? (row[23] as? NSNumber)?.floatValue ?? 0:0,
                                       life:driving ? (row.count>43 ? (row[43] as? NSNumber)?.intValue ?? 100:100):(row.count>18 ? (row[18] as? NSNumber)?.intValue ?? 100:100),
                                       armour:row.count>30 ? (row[30] as? NSNumber)?.intValue ?? 0:0)
            if let vehicleID, var vehicle = vehicles[vehicleID] {
                vehicle.position = SIMD3(x, y, z)
                vehicle.heading = row.count > 6 ? -((row[6] as? NSNumber)?.floatValue ?? 0) : 0
                vehicle.pitch = row.count > 7 ? (row[7] as? NSNumber)?.floatValue ?? 0 : 0
                vehicle.roll = row.count > 8 ? -((row[8] as? NSNumber)?.floatValue ?? 0) : 0
                vehicle.health = row.count > 18 ? (row[18] as? NSNumber)?.intValue ?? vehicle.health : vehicle.health
                vehicle.damage = row.count > 19 ? row[19] as? String ?? vehicle.damage : vehicle.damage
                vehicles[vehicleID] = vehicle
            } else if !driving, row.count > 35,
                      let parkedID = row[35] as? String,
                      let parked = row[33] as? [Any], parked.count >= 5,
                      var vehicle = vehicles[parkedID],
                      let parkedX = (parked[1] as? NSNumber)?.floatValue,
                      let parkedY = (parked[2] as? NSNumber)?.floatValue,
                      let parkedZ = (parked[3] as? NSNumber)?.floatValue {
                vehicle.position = SIMD3(parkedX, parkedY, parkedZ)
                vehicle.heading = (parked[4] as? NSNumber).map { -$0.floatValue } ?? vehicle.heading
                if parked.count > 6 {
                    vehicle.pitch = (parked[5] as? NSNumber)?.floatValue ?? 0
                    vehicle.roll = -((parked[6] as? NSNumber)?.floatValue ?? 0)
                }
                if parked.count > 7 { vehicle.health = (parked[7] as? NSNumber)?.intValue ?? vehicle.health }
                if parked.count > 8 { vehicle.damage = parked[8] as? String ?? vehicle.damage }
                vehicles[parkedID] = vehicle
            }
        }
        players = updated
        playerOrder.removeAll{updated[$0]==nil}
        let retained=Set(playerOrder)
        playerOrder += incomingOrder.filter{!retained.contains($0)}
        remoteAnimationTimes = remoteAnimationTimes.filter { updated[$0.key] != nil }
        onPlayers?(orderedPlayers)
        onVehicles?(orderedVehicles)
    }
}
