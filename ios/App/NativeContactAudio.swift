import Foundation
import simd

/// Original19737.cv material impacts, scraping and water-contact mixer.
final class NativeContactAudio {
    typealias V=SIMD3<Double>
    struct Material:Decodable {let step:Int,scrape:Int,hit:[Int],furthest:Double,hard:Double}
    struct Configuration:Decodable {let materials:[Material],defaults:[String:Int],steps:[String:Int],samples:[Int],splashes:[Int]}
    struct Event {
        let kind:String,id:String,sample:String,position:V
        var rate=1.0,gain=1.0,start=0.0,delay=0.0,near=8.0,reach=160.0
    }
    private struct Crash {var since=0.0,scraping=false,told=0.0;var at:V;var sound=0,rate=0.0,decibels=0.0}
    private struct Wake {var at:V,decibels = -46.0,told=0.0}
    private let config:Configuration
    private let available:Set<Int>
    private var crashes:[String:Crash]=[:],crashOrder:[String]=[]
    private var previousSound:[Int:Int]=[:]
    private var wakes:[String:Wake]=[:],wakeOrder:[String]=[]
    private var waterSample=0
    init(configuration:Configuration){config=configuration;available=Set(configuration.samples)}
    private func material(_ id:Int)->Material {config.materials.indices.contains(id) ? config.materials[id]:config.materials[config.defaults["DEFAULT"] ?? 0]}
    private static func db(_ value:Double)->Double {pow(10,value/20)}
    private static func wetDB(_ value:Double)->Double {0.9*db(value+9)}
    func carMaterial(other:Int,normal:V,up:V)->Int {
        let soft=["GRASS","SAND","GRAVEL"].compactMap{config.steps[$0]}.contains(material(other).step)
        return soft && simd_dot(normal,up)>0.6 ? config.defaults["RUBBER"] ?? 67:config.defaults["CAR"] ?? 63
    }
    func crash(id:String,impact:Double,position:V,mine:Int?=nil,other:Int?=nil,slide:Double=0,
               random:()->Double={Double.random(in:0..<1)})->[Event] {
        guard impact>=0 else{return []}
        let mine=mine ?? config.defaults["CAR"] ?? 63,other=other ?? config.defaults["DEFAULT"] ?? 0
        if crashes[id]==nil || crashes[id]!.since>0.6 && !crashes[id]!.scraping {
            var events:[Event]=[]
            for (target,incoming) in [(other,mine),(mine,other)] {
                let targetMaterial=material(target),incomingMaterial=material(incoming)
                guard targetMaterial.hit.count>=2,targetMaterial.hit[0]>=0 else{continue}
                let onset=100-min(100,floor(incomingMaterial.hard*impact/100*500))
                guard onset<100 else{continue}
                let all=(targetMaterial.hit[0]...targetMaterial.hit[1]).filter{available.contains($0)}
                let excluding=all.count>1 ? all.filter{$0 != previousSound[target]}:all
                guard !excluding.isEmpty else{continue}
                let sample=excluding[min(excluding.count-1,Int(floor(random()*Double(excluding.count))))]
                let start=onset>targetMaterial.furthest ? targetMaterial.furthest/100:onset/100
                let level=onset>targetMaterial.furthest ? 20*log10((100-onset)/(100-targetMaterial.furthest)):0
                previousSound[target]=sample
                events.append(Event(kind:"once",id:id,sample:"39_\(sample)",position:position,rate:1+(2*random()-1)*0.02,
                                    gain:Self.db(level-3),start:start))
            }
            if !events.isEmpty {
                if crashes[id]==nil {crashOrder.append(id)}
                crashes[id]=Crash(at:position)
            }
            return events
        }
        let a=material(mine),b=material(other),both=[a.scrape,b.scrape]
        let sound=[0,3,2].first{both.contains($0)} ?? 1
        let amount=slide>0 ? min(3*sqrt(slide*a.hard*b.hard/10000),0.3):0
        let rate=max(amount,0.75),level=amount>0 ? 20*log10(min(amount/0.75,1)) : -100
        var record=crashes[id]!
        record.told=0;record.at=position
        if record.scraping {
            record.rate += max(-0.1,min(0.1,rate-record.rate))
            record.decibels += max(-1,min(1,level-record.decibels))
        } else {record.scraping=true;record.sound=sound;record.rate=0.8*rate;record.decibels=level}
        crashes[id]=record
        return [Event(kind:record.decibels > -60 ? "hold":"drop",id:"scrape:"+id,sample:"39_\(record.sound)",
                      position:position,rate:record.rate,gain:Self.db(record.decibels))]
    }
    func fell(id:String,position:V,speed:Double)->[Event] {
        let level=max(20*log10(max(min(0.6,speed/50),1e-6)),-18)
        return config.splashes.prefix(2).enumerated().map { index,sound in
            Event(kind:"once",id:id,sample:"39_\(sound)",position:position,rate:1.26,gain:Self.wetDB(-6+level),
                  delay:index==0 ? 0:0.166,near:7.5,reach:112.5)
        }
    }
    func waterStroke(id:String,position:V,dive:Bool=false,random:Double=Double.random(in:0..<1))->Event {
        defer{waterSample=(waterSample+1)%5}
        return Event(kind:"once",id:id,sample:"128_\(waterSample)",position:position,
                     rate:1+(2*random-1)*0.0588,gain:Self.wetDB(dive ? -3:-9),near:3,reach:45)
    }
    func wake(id:String,position:V) {
        if wakes[id]==nil {wakes[id]=Wake(at:position);wakeOrder.append(id)}
        else{wakes[id]!.at=position;wakes[id]!.told=0}
    }
    func update(delta:Double)->[Event] {
        var events:[Event]=[]
        for id in wakeOrder {
            guard var value=wakes[id] else{continue}
            value.told += delta
            let fresh=value.told<=0.1
            value.decibels=fresh ? min(-26,value.decibels+30*delta):value.decibels-30*delta
            if !fresh && value.decibels<=(-46) {
                events.append(Event(kind:"drop",id:id,sample:"",position:value.at));wakes.removeValue(forKey:id)
            } else {
                events.append(Event(kind:"hold",id:id,sample:"39_3",position:value.at,rate:0.75,gain:Self.wetDB(value.decibels),near:3,reach:45))
                wakes[id]=value
            }
        }
        wakeOrder.removeAll{wakes[$0]==nil}
        for id in crashOrder {
            guard var value=crashes[id] else{continue}
            value.since += delta;value.told += delta
            if value.scraping && value.told>0.1 {
                events.append(Event(kind:"drop",id:"scrape:"+id,sample:"",position:value.at));crashes.removeValue(forKey:id)
            } else if !value.scraping && value.since>0.6 {crashes.removeValue(forKey:id)}
            else {crashes[id]=value}
        }
        crashOrder.removeAll{crashes[$0]==nil}
        return events
    }
    func quiet()->[Event] {
        let events=crashOrder.compactMap{id in crashes[id].map{Event(kind:"drop",id:"scrape:"+id,sample:"",position:$0.at)}} +
            wakeOrder.compactMap{id in wakes[id].map{Event(kind:"drop",id:id,sample:"",position:$0.at)}}
        crashes.removeAll();crashOrder.removeAll();wakes.removeAll();wakeOrder.removeAll()
        return events
    }
}
