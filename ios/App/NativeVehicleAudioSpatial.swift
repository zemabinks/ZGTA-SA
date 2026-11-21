import Foundation
import simd

/// Original module1061 remote selection and Web Audio's inverse/equalpower
/// spatial model. Coordinates are Rapier/Three Y-up throughout this helper.
enum NativeVehicleAudioSpatial {
    /// Scene sound emitters have explicit provenance. A compact car never
    /// needs a synthetic player or a player-roster entry to make sound.
    enum SourceIdentity:Hashable {
        case player(String)
        case traffic(UInt16)
        var token:String {
            switch self {
            case .player(let id):return "player:\(id)"
            case .traffic(let id):return "traffic:\(id)"
            }
        }
    }
    struct Source {
        let identity:SourceIdentity,model:Int
        let gtaPosition:SIMD3<Float>
        let heading:Double,pitch:Double,roll:Double,speed:Double,health:Double
        let horn:Bool,siren:Bool
        var id:String{identity.token}
    }
    struct Traffic {
        let id:UInt16,model:UInt16
        let gtaPosition:SIMD3<Float>
        let heading:Double,pitch:Double,speed:Double
        let flags:UInt8,built:Bool,shown:Bool
    }
    /// Near candidates use stable distance order; the separate far siren
    /// allowance follows actor insertion order. The common voice selector
    /// still applies supported-model/range checks and its overall five cap.
    static func trafficSources(_ traffic:[Traffic],listener:SIMD3<Float>)->[Source] {
        guard listener.x.isFinite,listener.y.isFinite,listener.z.isFinite else{return []}
        let available=traffic.enumerated().compactMap{index,car -> (Int,Traffic,Double)? in
            guard car.built,car.shown,car.gtaPosition.x.isFinite,car.gtaPosition.y.isFinite,car.gtaPosition.z.isFinite,
                  car.speed.isFinite,car.heading.isFinite,car.pitch.isFinite else{return nil}
            return(index,car,simd_distance(SIMD3<Double>(car.gtaPosition),SIMD3<Double>(listener)))
        }
        let near=available.filter{$0.2<45}.sorted{$0.2==$1.2 ? $0.0<$1.0:$0.2<$1.2}.prefix(4)
        let far=available.filter{$0.2>=45 && $0.2<150 && $0.1.flags&2 != 0}.prefix(2)
        func source(_ row:(Int,Traffic,Double),far:Bool)->Source {
            let car=row.1
            return .init(identity:.traffic(car.id),model:Int(car.model),gtaPosition:car.gtaPosition,
                heading:car.heading,pitch:car.pitch,roll:0,speed:car.speed,health:1000,
                horn:!far && car.flags&8 != 0,siren:car.flags&2 != 0)
        }
        return near.map{source($0,far:false)}+far.map{source($0,far:true)}
    }
    /// AudioParam.setTargetAtTime: each new target preserves the current curve
    /// value, then approaches the target with the supplied time constant.
    struct VectorParameter {
        private var start: SIMD3<Double>
        private var target: SIMD3<Double>
        private var began: Double
        let constant: Double
        init(_ value: SIMD3<Double>, constant: Double, time: Double = 0) {
            start = value; target = value; began = time; self.constant = constant
        }
        func value(at time: Double) -> SIMD3<Double> {
            target+(start-target)*exp(-max(0,time-began)/constant)
        }
        mutating func setTarget(_ value: SIMD3<Double>, at time: Double) {
            start = self.value(at:time); target = value; began = time
        }
    }
    enum Kind: String, Codable { case road, aircraft, boat, special, train }
    struct Catalogue {
        var road: Set<Int> = [], aircraft: Set<Int> = [], boats: Set<Int> = [], special: Set<Int> = [], trains: Set<Int> = []
        func kind(_ model: Int) -> Kind? {
            if aircraft.contains(model) { return .aircraft }
            if trains.contains(model) { return .train }
            if special.contains(model) { return .special }
            if boats.contains(model) { return .boat }
            return road.contains(model) ? .road:nil
        }
    }
    struct Candidate {
        let id: String
        let model: Int
        let position: SIMD3<Double>
        let speed: Double
    }
    struct Selected {
        let candidate: Candidate
        let kind: Kind
        let distance: Double
    }
    struct Panner: Equatable {
        let reference: Double
        let maximum: Double
        let rolloff: Double
        /// maxDistance is intentionally not a clamp for the inverse model.
        /// W3C Web Audio1.1 §DistanceModelType.inverse.
        func gain(distance: Double) -> Double {
            reference/(reference+rolloff*(max(distance,reference)-reference))
        }
    }
    static func select(_ candidates: [Candidate], listener: SIMD3<Double>, catalogue: Catalogue) -> [Selected] {
        candidates.enumerated().compactMap { index, candidate -> (Int, Selected)? in
            guard let kind = catalogue.kind(candidate.model) else { return nil }
            let distance = simd_distance(candidate.position,listener)
            let near = catalogue.road.contains(candidate.model) || catalogue.boats.contains(candidate.model) || catalogue.special.contains(candidate.model)
            let far = catalogue.aircraft.contains(candidate.model) || catalogue.trains.contains(candidate.model)
            guard distance < 110 && near || distance < 330 && far else { return nil }
            return (index,Selected(candidate:candidate,kind:kind,distance:distance))
        }.sorted { $0.1.distance == $1.1.distance ? $0.0 < $1.0 : $0.1.distance < $1.1.distance }
            .prefix(5).map { $0.1 }
    }
    static func panner(kind: Kind, special: String? = nil, far: Bool = false) -> Panner {
        switch kind {
        case .aircraft: return Panner(reference:far ? 21:14,maximum:330,rolloff:1.6)
        case .train: return Panner(reference:31.5,maximum:330,rolloff:1.6)
        case .boat: return Panner(reference:7,maximum:110,rolloff:0)
        case .special: return Panner(reference:7*(special == "hover" ? 3.5:special == "golf" ? 2:1),maximum:110,rolloff:1.6)
        case .road: return Panner(reference:7,maximum:110,rolloff:1.6)
        }
    }
    /// Original remote boat/RC top defaults to45 if no built handling is known.
    static func fallbackTop(_ top: Double?) -> Double { top ?? 45 }

    static func azimuth(source: SIMD3<Double>, listener: SIMD3<Double>, forward: SIMD3<Double>) -> Double {
        func normalized(_ value: SIMD3<Double>) -> SIMD3<Double> {
            let length = simd_length(value); return length > 0 ? value/length:.zero
        }
        let relative = normalized(source-listener)
        if simd_length_squared(relative) == 0 { return 0 }
        let right = simd_cross(forward,SIMD3<Double>(0,1,0))
        if simd_length_squared(right) == 0 { return 0 }
        let rightNormal = normalized(right), forwardNormal = normalized(forward)
        let up = simd_cross(rightNormal,forwardNormal)
        let projected = normalized(relative-up*simd_dot(relative,up))
        var angle = 180*acos(max(-1,min(1,simd_dot(projected,rightNormal))))/Double.pi
        if simd_dot(projected,forwardNormal) < 0 { angle = 360-angle }
        return angle >= 0 && angle <= 270 ? 90-angle:450-angle
    }
    /// Matrix columns describe source L/R contributions to output L/R. Mono
    /// uses the first column only; callers must retain the source channel count.
    static func matrix(azimuth: Double, mono: Bool) -> SIMD4<Double> {
        var angle = max(-180,min(180,azimuth))
        if angle < -90 { angle = -180-angle }
        else if angle > 90 { angle = 180-angle }
        let share = mono ? (angle+90)/180 : angle <= 0 ? (angle+90)/90:angle/90
        let left = cos(share*Double.pi/2), right = sin(share*Double.pi/2)
        if mono { return SIMD4(left,0,right,0) }
        return angle <= 0 ? SIMD4(1,left,0,right):SIMD4(left,0,right,1)
    }
}
