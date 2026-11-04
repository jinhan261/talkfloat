import Foundation
import SpeexDSP

/// Explicit playback-reference AEC, shared by local ASR and cloud microphone ASR.
/// Runs on the sender worker; no disk recording; the sender supplies a bounded 160 ms lookahead.
public final class ReferenceEchoCanceller:@unchecked Sendable {
    private let lock=NSLock()
    private let echo=speex_echo_state_init(320,8192)!
    private let pre=speex_preprocess_state_init(320,16000)!
    private var reference:[Int16]=[]
    private var referenceStart:Double?
    private var micEnd:Double?
    private var reduction=0.0
    private var probeCount=0
    private var delayMS=0.0, waveformScore=0.0,missingReference=0.0,linearReduction=0.0
    public var alignment:[String:Double]{lock.withLock{["delayMS":delayMS,"waveformScore":waveformScore,"missingReference":missingReference,"linearReductionDB":linearReduction]}}
    public init(){
        var rate:Int32=16000;speex_echo_ctl(echo,SPEEX_ECHO_SET_SAMPLING_RATE,&rate)
        speex_preprocess_ctl(pre,SPEEX_PREPROCESS_SET_ECHO_STATE,UnsafeMutableRawPointer(echo))
        for (option,value) in [(SPEEX_PREPROCESS_SET_AGC,0),(SPEEX_PREPROCESS_SET_DENOISE,1),(SPEEX_PREPROCESS_SET_NOISE_SUPPRESS,-15),(SPEEX_PREPROCESS_SET_ECHO_SUPPRESS,-45),(SPEEX_PREPROCESS_SET_ECHO_SUPPRESS_ACTIVE,-24)] {
            var v=Int32(value);speex_preprocess_ctl(pre,Int32(option),&v)
        }
    }
    deinit{speex_preprocess_state_destroy(pre);speex_echo_state_destroy(echo)}
    public var reductionDB:Double{lock.withLock{reduction}}
    public func observeSystem(_ data:Data,end:Double){lock.withLock{
        let start=end-Double(data.count)/32000
        if let origin=referenceStart,abs(origin+Double(reference.count)/16000-start)>0.2{
            reference.removeAll(keepingCapacity:true);referenceStart=nil;speex_echo_state_reset(echo)
        }
        if referenceStart==nil{referenceStart=start}
        data.withUnsafeBytes{bytes in for i in stride(from:0,to:bytes.count-1,by:2){reference.append(bytes.loadUnaligned(fromByteOffset:i,as:Int16.self))}}
        if reference.count>48000{let removed=reference.count-32000;reference.removeFirst(removed);referenceStart!+=Double(removed)/16000}
    }}
    public func process(_ packet:AudioPacket)->AudioPacket {lock.withLock{
        let duration=Double(packet.data.count)/32000
        if micEnd==nil || abs(packet.queuedAt-(micEnd!+duration))>0.25{micEnd=packet.queuedAt-duration;speex_echo_state_reset(echo)}
        let start=micEnd!;micEnd!+=duration
        var input:[Int16]=[];packet.data.withUnsafeBytes{b in for i in stride(from:0,to:b.count-1,by:2){input.append(b.loadUnaligned(fromByteOffset:i,as:Int16.self))}}
        probeCount+=1
        if probeCount%12==0{probeAlignment(input,start:start)}
        var result=input,play=Array(repeating:Int16(0),count:320),output=play
        var missing=0,linearEnergy=0.0
        for offset in stride(from:0,to:input.count-319,by:320){
            // The sender holds two 80 ms packets, allowing a playback reference
            // ahead of the mic delivery clock. System capture and hardware input have
            // different delivery latency; the causal filter learns the offset.
            let index=Int(((start+Double(offset)/16000+0.08-(referenceStart ?? start))*16000).rounded())
            for i in 0..<320{if reference.indices.contains(index+i){play[i]=reference[index+i]}else{play[i]=0;missing+=1}}
            input.withUnsafeBufferPointer{inBuffer in
                speex_echo_cancellation(echo,inBuffer.baseAddress!+offset,play,&output)
            }
            linearEnergy+=output.reduce(0.0){$0+Double($1)*Double($1)}
            speex_preprocess_run(pre,&output)
            result.replaceSubrange(offset..<offset+320,with:output)
        }
        let before=input.reduce(0.0){$0+Double($1)*Double($1)},after=result.reduce(0.0){$0+Double($1)*Double($1)}
        missingReference=Double(missing)/Double(max(1,input.count))
        linearReduction=10*log10(max(1,before)/max(1,linearEnergy))
        reduction=10*log10(max(1,before)/max(1,after))
        return AudioPacket(data:result.withUnsafeBytes{Data($0)},queuedAt:packet.queuedAt)
    }}
    private func probeAlignment(_ input:[Int16],start:Double) {
        guard input.count>=1280,let origin=referenceStart else{return}
        let energy=input.enumerated().filter{$0.offset%4==0}.reduce(0.0){$0+Double($1.element)*Double($1.element)}
        guard energy>100000 else{return}
        var best=0.0,bestDelay=0.0
        for lag in -70...350 {
            let index=Int(((start-Double(lag)/1000-origin)*16000).rounded())
            guard index>=0,index+input.count<=reference.count else{continue}
            var xy=0.0,xx=0.0
            for i in stride(from:0,to:input.count,by:4){let x=Double(reference[index+i]);xy+=x*Double(input[i]);xx+=x*x}
            let score=abs(xy)/sqrt(max(1,xx*energy))
            if score>best{best=score;bestDelay=Double(lag)}
        }
        waveformScore=best;delayMS=bestDelay
    }
}
