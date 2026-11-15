import Foundation

/// Original public 19863.WY swim clip weights, clocks and figure rotation.
final class NativeSwimAnimation {
    struct Input { var state: Int; var rate: Double = 1; var pace: Double = 1; var pitch: Double = 0 }
    struct Frame { var blends: [NativeSkeletalBlend]; var figurePitch: Double }
    private let duration: (String) -> Double?
    private var amount: Double = 0
    private var previous = 0
    private var pitch: Double = 0
    private var weights = Array(repeating: 0.0,count:8)
    private var times = Array(repeating: 0.0,count:8)
    private let names = ["tread","breast","crawl","glide","under","dive","jumpout","climb"]
    private let clips = ["swim/swim_tread","swim/swim_breast","swim/swim_crawl","swim/swim_glide","swim/swim_under","swim/swim_dive_under","swim/swim_jumpout","ped/climb_jump"]
    private let rates: [(Double,Double)] = [(8,4),(2,1),(2,1),(4,2),(4,2),(8,4),(8,4),(8,4)]
    var showing: Bool { amount > 0 }
    init(duration: @escaping (String) -> Double?) { self.duration = duration }
    func update(delta dt: Double,input: Input?,available: Bool = true) -> Frame {
        let state = input?.state ?? 0
        func fade(_ value:Double,_ on:Bool,_ rates:(Double,Double))->Double { min(1,max(0,value+(on ? rates.0 : -rates.1)*dt)) }
        amount = fade(amount,state != 0,(8,4))
        var selected: String? = [1:"tread",2:"breast",3:"crawl",4:"dive",5:"under",6:"glide",7:"jumpout"][state]
        if state != previous {
            if state == 4 { times[5] = 0 }
            if state == 7 { times[6] = 0;times[7] = 0 }
            if state == 5 && weights[4] <= 0 { times[4] = 0 }
            previous = state
        }
        if state == 7 && available,let length = duration(clips[6]),times[6] >= 0.25*length { selected = "climb" }
        let target = state == 5 || state == 6 ? input?.pitch ?? 0 : 0
        pitch += min(3*dt,max(-3*dt,target-pitch))
        guard amount > 0 else { weights = Array(repeating:0,count:8);pitch = 0;return Frame(blends:[],figurePitch:0) }
        var result: [NativeSkeletalBlend] = []
        for index in names.indices {
            weights[index] = index == 0 ? 1 : fade(weights[index],selected == names[index],rates[index])
            let clip = available ? clips[index] : index == 0 ? "ped/swim_tread" : ""
            guard !clip.isEmpty,let length = duration(clip),length > 0,weights[index] > 0 else { continue }
            let speed: Double = index == 1 ? max(0.3,min(1,input?.rate ?? 1)) : index == 2 || index == 4 ? input?.pace ?? 1 : 1
            times[index] += dt*speed
            let once = index >= 5
            let time = once ? min(times[index],length) : times[index].truncatingRemainder(dividingBy:length)
            result.append(NativeSkeletalBlend(operation:.replace,clip:clip,time:time,weight:weights[index]*amount))
        }
        return Frame(blends:result,figurePitch:pitch)
    }
}
