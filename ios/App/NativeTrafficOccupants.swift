// SPDX-License-Identifier: AGPL-3.0-only
import Foundation
import CoreFoundation

/// Deterministic compact-traffic seat selection, separate from human roster
/// rows, asset readiness, animation owners and authoritative damage.
enum NativeTrafficOccupants {
    struct Catalog:Decodable {
        let schema:Int
        let fallback:[Int]
        let overrides:[String:Int]
        let hiddenModels:[UInt16]
        init(data:Data)throws {
            guard data.count<=65536 else{throw Failure.catalog}
            let value=try JSONDecoder().decode(Self.self,from:data)
            guard value.schema==1,!value.fallback.isEmpty,value.fallback.count<=512,
                  value.fallback.allSatisfy(Self.validSkin),value.overrides.count<=512,
                  value.overrides.allSatisfy({Self.validModelKey($0.key) && Self.validSkin($0.value)}),
                  value.hiddenModels.count<=512 else{throw Failure.catalog}
            self=value
        }
        private static func validSkin(_ id:Int)->Bool{(0...65535).contains(id)}
        private static func validModelKey(_ value:String)->Bool {
            guard let id=UInt16(value)else{return false};return String(id)==value
        }
    }
    enum Failure:Error {case catalog}
    struct Gang {
        let skins:[Int?],cars:[UInt16]
        init?(skins:[Int?],cars:[UInt16]) {
            guard !skins.isEmpty,skins.count<=512,cars.count<=512,
                  skins.allSatisfy({$0.map{(0...65535).contains($0)} ?? true})else{return nil}
            self.skins=skins;self.cars=cars
        }
    }
    /// Keep the negotiated row order. Malformed updates revoke the old crew
    /// selection rather than allow an obsolete configuration to keep binding.
    static func gangs(rows:Any?)->[Gang]? {
        guard let rows=rows as?[[Any]],rows.count<=128 else{return nil}
        func integer(_ value:Any)->Int? {
            guard let number=value as?NSNumber,CFGetTypeID(number) != CFBooleanGetTypeID()else{return nil}
            let n=number.doubleValue
            return n.isFinite && n.rounded(.towardZero)==n && (0...65535).contains(n) ? Int(n):nil
        }
        var result:[Gang]=[]
        for row in rows {
            guard row.count>=4,let rawSkins=row[2]as?[Any],let rawCars=row[3]as?[Any],
                  rawSkins.count<=512,rawCars.count<=512 else{return nil}
            var skins:[Int?]=[]
            for value in rawSkins {
                if value is NSNull{skins.append(nil)}
                else if let id=integer(value){skins.append(id)}
                else{return nil}
            }
            // JS strict numeric model matching ignores strings, booleans and
            // nonintegral entries; none can match a compact16bit model ID.
            let cars=rawCars.compactMap(integer)
            if skins.isEmpty{continue}
            guard let gang=Gang(skins:skins,cars:cars.map{UInt16($0)})else{return nil}
            result.append(gang)
        }
        return result
    }
    struct Vehicle {
        let id:UInt16,generation:UInt64,model:UInt16
        let flags:UInt8,count:UInt8?,deadSeats:UInt8
        let distance:Double,built:Bool,thrown:Bool
        let seatSides:[Int]
    }
    struct Seat:Equatable {
        let id:UInt16,generation:UInt64,model:UInt16,index:Int,skin:Int,dead:Bool
        var targetID:String{"c\(id).\(index)"}
    }
    /// Preserve rank before flag/thrown filtering: an excluded nearer car
    /// still occupies its original update-budget position. Missing assets do
    /// not synthesize actors; the renderer must bind the selected skin itself.
    static func seats(vehicles:[Vehicle],catalog:Catalog,gangs:[Gang])->[Seat] {
        let ranked=vehicles.enumerated().filter{$0.element.built && $0.element.distance.isFinite &&
            $0.element.distance>=0 && $0.element.distance<45}.sorted {
                $0.element.distance==$1.element.distance ? $0.offset<$1.offset:$0.element.distance<$1.element.distance
            }
        var result:[Seat]=[]
        for entry in ranked.prefix(6) {
            let car=entry.element
            guard car.flags&32==0,!car.thrown,!catalog.hiddenModels.contains(car.model),!car.seatSides.isEmpty else{continue}
            func crew(_ seat:Int)->Int? {
                guard let gang=gangs.first(where:{$0.cars.contains(car.model)})else{return nil}
                return gang.skins[(Int(car.id)+7*seat)%gang.skins.count]
            }
            let primary=car.flags&128 != 0 ? crew(0):nil
            let driver=primary ?? catalog.overrides[String(car.model)] ?? catalog.fallback[Int(car.id)%catalog.fallback.count]
            let varies=primary.map{$0 != 0} ?? false
            let count=Int(car.count ?? (varies ? 3:1))
            for seat in 0..<min(3,car.seatSides.count) {
                if seat==1 && count<=1{continue}
                if seat==2 && (count<=2 || car.seatSides[2] != -1){continue}
                let skin=seat>0 && varies ? crew(seat) ?? driver:driver
                result.append(.init(id:car.id,generation:car.generation,model:car.model,index:seat,skin:skin,
                    dead:car.deadSeats & UInt8(1<<seat) != 0))
            }
        }
        return result
    }
}
