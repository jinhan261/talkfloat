import Foundation
import SayloriCore
@main struct Check {
 static func main() async {
    if CommandLine.arguments.count==4,CommandLine.arguments[1]=="--audit-echo"{
        do{
            let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
            var record=try decoder.decode(MeetingRecord.self,from:Data(contentsOf:URL(fileURLWithPath:CommandLine.arguments[2])))
            var clocks:[String:Double]=[:]
            let log=try String(contentsOfFile:CommandLine.arguments[3],encoding:.utf8)
            for line in log.split(separator:"\n"){
                guard let data=line.data(using:.utf8),let e=try JSONSerialization.jsonObject(with:data) as? [String:Any],e["kind"] as? String == "audio-send",let id=e["session"] as? String,clocks[id]==nil,let time=e["time"] as? Double,let end=e["audioEndMS"] as? Double else{continue}
                clocks[id]=time-end/1000-(e["queueMS"] as? Double ?? 0)/1000
            }
            for i in record.segments.indices{if record.segments[i].audioEpoch==nil{record.segments[i].audioEpoch=clocks[record.segments[i].sessionID]}}
            let start=ProcessInfo.processInfo.systemUptime
            let matches=SystemEchoMatcher.matches(in:record.segments)
            let mic=record.segments.filter{$0.audioOrigin == .microphone}
            let result:[String:Any]=["total":record.segments.count,"mic":mic.count,"matched":matches.count,"matchingMS":(ProcessInfo.processInfo.systemUptime-start)*1000,"unmatched":mic.filter{matches[$0.id]==nil}.map{["source":$0.source,"startMS":$0.startMS,"endMS":$0.endMS] as [String:Any]}]
            print(String(data:try JSONSerialization.data(withJSONObject:result,options:[.prettyPrinted,.sortedKeys]),encoding:.utf8)!)
        }catch{print(error.localizedDescription);exit(1)}
        return
    }
    print("TalkFloat native diagnostics")
    print("Audio processes: \(CoreAudioTap.processIDs().count)")
    print("Stored credentials: \((try? Keychain.load())?.isValid == true ? "configured":"not configured")")
    if CommandLine.arguments.contains("--connection"),let credentials=try? Keychain.load(){
        let client=ASTClient()
        do{try await client.connect(credentials);print("AST SessionStarted: OK");print("Graceful finish: \(await client.finish())")}
        catch{print("AST error: \(error.localizedDescription)");exit(1)}
    }
 }
}
