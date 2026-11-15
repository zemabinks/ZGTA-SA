import Foundation
import simd

/// Original module1061 remote selection and Web Audio's inverse/equalpower
/// spatial model. Coordinates are Rapier/Three Y-up throughout this helper.
enum NativeVehicleAudioSpatial {
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
