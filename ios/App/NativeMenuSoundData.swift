import Foundation

/// Standard RIFF Microsoft ADPCM data decoding for the supplied menu WAVs.
/// Apple AudioFile does not accept these source files on the analysis host.
/// Output remains the same recording as PCM16, with no synthesis/resampling.
enum NativeMenuSoundData {
    static func playableWave(_ data:Data)->Data? {
        let b=[UInt8](data)
        guard b.count>=44,b.count<=4_000_000,String(bytes:b[0..<4],encoding:.ascii)=="RIFF",
              String(bytes:b[8..<12],encoding:.ascii)=="WAVE" else{return nil}
        func u16(_ p:Int)->Int{Int(b[p])|Int(b[p+1])<<8}
        func u32(_ p:Int)->Int{u16(p)|u16(p+2)<<16}
        func i16(_ p:Int)->Int{Int(Int16(bitPattern:UInt16(u16(p))))}
        let riffEnd=8+u32(4)
        guard riffEnd>=44,riffEnd<=b.count else{return nil}
        var format:Range<Int>?,payload:Range<Int>?,fact:Int?,p=12
        while p+8<=riffEnd {
            let size=u32(p+4),start=p+8
            guard size>=0,size<=riffEnd-start else{return nil}
            let name=String(bytes:b[p..<p+4],encoding:.ascii)
            if name=="fmt " {format=start..<start+size}
            if name=="data" {payload=start..<start+size}
            if name=="fact",size>=4 {fact=u32(start)}
            p=start+size+size%2
        }
        guard let format,format.count>=16,let payload,!payload.isEmpty else{return nil}
        let f=format.lowerBound,kind=u16(f),channels=u16(f+2),rate=u32(f+4),align=u16(f+12)
        guard (1...2).contains(channels),(8000...192000).contains(rate) else{return nil}
        if kind==1,u16(f+14)==16,align==channels*2,payload.count%align==0{return data}
        guard kind==2,format.count>=22,u16(f+14)==4,align>=7*channels,
              payload.count%align==0 else{return nil}
        let samplesPerBlock=u16(f+18),coefficientCount=u16(f+20)
        guard (1...32).contains(coefficientCount),format.count>=22+coefficientCount*4,
              samplesPerBlock==2+(align-7*channels)*2/channels,
              payload.count/align*samplesPerBlock*channels<=2_000_000 else{return nil}
        let coefficients=(0..<coefficientCount).map{(i16(f+22+$0*4),i16(f+24+$0*4))}
        let adaptation=[230,230,230,230,307,409,512,614,768,614,512,409,307,230,230,230]
        var pcm:[Int16]=[];pcm.reserveCapacity(payload.count/align*samplesPerBlock*channels)
        for start in stride(from:payload.lowerBound,to:payload.upperBound,by:align) {
            var predictor=[Int](),delta=[Int](),first=[Int](),second=[Int]()
            for c in 0..<channels {
                let selected=Int(b[start+c]);guard selected<coefficients.count else{return nil}
                predictor.append(selected);delta.append(max(16,i16(start+channels+c*2)))
                first.append(i16(start+channels*3+c*2));second.append(i16(start+channels*5+c*2))
            }
            for c in 0..<channels {pcm.append(Int16(second[c]))}
            for c in 0..<channels {pcm.append(Int16(first[c]))}
            func nibble(_ code:Int,_ channel:Int)->Bool {
                let coeff=coefficients[predictor[channel]],signed=code>=8 ? code-16:code
                let prediction=(first[channel]*coeff.0+second[channel]*coeff.1)/256
                let (change,overA)=signed.multipliedReportingOverflow(by:delta[channel])
                let (sum,overB)=prediction.addingReportingOverflow(change)
                let (nextDelta,overC)=delta[channel].multipliedReportingOverflow(by:adaptation[code])
                guard !overA,!overB,!overC else{return false}
                let sample=min(32767,max(-32768,sum))
                second[channel]=first[channel];first[channel]=sample
                delta[channel]=max(16,nextDelta/256)
                pcm.append(Int16(sample))
                return true
            }
            for at in start+7*channels..<start+align {
                let byte=Int(b[at]);guard nibble(byte>>4,0),nibble(byte&15,channels==1 ? 0:1) else{return nil}
            }
        }
        if let fact {guard fact>0,fact<=pcm.count/channels else{return nil};pcm.removeLast(pcm.count-fact*channels)}
        guard !pcm.isEmpty,pcm.count<=2_000_000 else{return nil}
        var output=Data()
        func text(_ value:String){output.append(contentsOf:value.utf8)}
        func word(_ value:Int){var v=UInt16(value).littleEndian;withUnsafeBytes(of:&v){output.append(contentsOf:$0)}}
        func integer(_ value:Int){var v=UInt32(value).littleEndian;withUnsafeBytes(of:&v){output.append(contentsOf:$0)}}
        text("RIFF");integer(36+pcm.count*2);text("WAVEfmt ");integer(16);word(1);word(channels)
        integer(rate);integer(rate*channels*2);word(channels*2);word(16);text("data");integer(pcm.count*2)
        for sample in pcm {word(Int(UInt16(bitPattern:sample)))}
        return output
    }
}
