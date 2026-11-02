import Foundation
import Accelerate

/// Bounded in-memory speech spectra. No PCM or recoverable audio is retained.
/// Per-band correlation is insensitive to device gain and steady room coloration.
final class PlaybackCorrelation {
    struct Bin {let time:Double;let bands:[Double]}
    private var system:[Bin]=[]
    private var microphone:[Bin]=[]
    private let transform=vDSP_DFT_zop_CreateSetup(nil,512,.FORWARD)!
    private let window=(0..<320).map{Float(0.5-0.5*cos(2 * .pi*Double($0)/319))}
    private let ranges=[5..<10,10..<16,16..<26,26..<38,38..<58,58..<83,83..<115,115..<160]
    private(set) var latestScore=0.0
    deinit{vDSP_DFT_DestroySetup(transform)}
    func observeSystem(_ data:Data,end:Double){let values=features(data,end:end);append(values,to:&system)}
    func observeMicrophone(_ data:Data,end:Double)->Double {
        let values=features(data,end:end);append(values,to:&microphone)
        let mic=Array(microphone.suffix(56))
        guard mic.count>=40,system.count>=40,let first=system.first else{latestScore=0;return 0}
        var best=0.0
        for lag in -50...70 {
            var sumX=Array(repeating:0.0,count:8),sumY=sumX,xx=sumX,yy=sumX,xy=sumX,n=0.0
            for m in mic {
                let time=m.time-Double(lag)*0.01
                let index=Int(((time-first.time)/0.02).rounded())
                guard system.indices.contains(index),abs(system[index].time-time)<0.021 else{continue}
                let reference=system[index]
                for b in 0..<8 {
                    let x=reference.bands[b],y=m.bands[b]
                    sumX[b]+=x;sumY[b]+=y;xx[b]+=x*x;yy[b]+=y*y;xy[b]+=x*y
                }
                n+=1
            }
            guard n>=40 else{continue}
            var scores:[Double]=[]
            for b in 0..<8 {
                let vx=xx[b]-sumX[b]*sumX[b]/n,vy=yy[b]-sumY[b]*sumY[b]/n
                guard vx/n>0.04,vy/n>0.04 else{continue}
                scores.append((xy[b]-sumX[b]*sumY[b]/n)/sqrt(vx*vy))
            }
            // Several speech bands must agree; a single tone is insufficient.
            guard scores.count>=4 else{continue}
            let strongest=scores.sorted().suffix(min(6,scores.count))
            best=max(best,strongest.reduce(0,+)/Double(strongest.count))
        }
        latestScore=min(1,max(0,best));return latestScore
    }
    private func features(_ data:Data,end:Double)->[Bin] {
        let duration=Double(data.count)/32000
        var result:[Bin]=[]
        var real=Array(repeating:Float(0),count:512),imag=real,outReal=real,outImag=real
        data.withUnsafeBytes{bytes in
            for offset in stride(from:0,to:bytes.count-639,by:640){
                for i in 0..<320{real[i]=Float(bytes.loadUnaligned(fromByteOffset:offset+i*2,as:Int16.self))/32768*window[i]}
                vDSP_DFT_Execute(transform,real,imag,&outReal,&outImag)
                let bands=ranges.map { range -> Double in
                    var energy=0.0
                    for i in range{energy+=Double(outReal[i]*outReal[i]+outImag[i]*outImag[i])}
                    return log(max(1e-10,energy/Double(range.count)))
                }
                result.append(Bin(time:end-duration+Double(offset+640)/32000,bands:bands))
            }
        }
        return result
    }
    private func append(_ values:[Bin],to bins:inout [Bin]) {
        if let last=bins.last,let first=values.first,abs(first.time-last.time-0.02)>0.15{bins.removeAll(keepingCapacity:true)}
        bins.append(contentsOf:values)
        if bins.count>250{bins.removeFirst(bins.count-200)}
    }
}
