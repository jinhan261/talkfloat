import Foundation

public enum TranslationMode:String,Codable,CaseIterable,Sendable {
    case local, doubao
    public var title:String{self == .local ? "本地免费":"豆包云端"}
    public var requiresCredentials:Bool{self == .doubao}
    public var detail:String{self == .local ? "在这台 Mac 翻译，不上传声音":"声音发送至豆包，按服务用量计费"}
}

/// Stable source finals must survive newer partial hypotheses. A failed/slow
/// translator stops explicitly rather than silently dropping archive sentences.
public struct LocalTranslationQueue:Sendable {
    private var finals:[CaptionSegment]=[]
    private var draft:CaptionSegment?
    public init(){}
    public var count:Int{finals.count+(draft == nil ? 0:1)}
    public mutating func enqueue(_ item:CaptionSegment)throws {
        if item.sourceFinal {
            if draft?.id==item.id{draft=nil}
            if let i=finals.firstIndex(where:{$0.id==item.id}){finals[i]=item}
            else{
                guard finals.count<32 else{throw SayError.message("本地翻译处理积压，已停止该路收听；已收到的文字仍会保存。")}
                finals.append(item)
            }
        }else{draft=item}
    }
    public mutating func next()->CaptionSegment? {
        if !finals.isEmpty{return finals.removeFirst()}
        defer{draft=nil};return draft
    }
    public mutating func removeAll(){finals=[];draft=nil}
}
