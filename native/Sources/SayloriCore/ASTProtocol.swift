import Foundation

public enum SayError: LocalizedError {
    case message(String)
    case service(Int,String)
    public var errorDescription:String?{
        switch self{case .message(let s):return s;case .service(let code,let text):return "豆包会话失败（\(code)）：\(text)"}
    }
    public static func canRetry(_ error:Error)->Bool {
        if case .service(let code,_) = error as? SayError {return (55000000...55999999).contains(code)}
        if let url=error as? URLError {return [.timedOut,.networkConnectionLost,.notConnectedToInternet,.cannotConnectToHost,.cannotFindHost].contains(url.code)}
        return false
    }
}

// Minimal protobuf wire codec; field numbers are pinned to the official AST proto files.
// No JSON wrapper, custom header, gzip or base64 is added to the binary WebSocket frames.
public enum Proto {
    public static func number(_ field: Int, _ value: UInt64) -> Data { var d = varint(UInt64(field << 3)); d.append(varint(value)); return d }
    public static func bytes(_ field: Int, _ value: Data) -> Data { var d = varint(UInt64(field << 3 | 2)); d.append(varint(UInt64(value.count))); d.append(value); return d }
    public static func string(_ field: Int, _ value: String) -> Data { bytes(field, Data(value.utf8)) }
    static func varint(_ value: UInt64) -> Data {
        var v = value; var d = Data()
        while v >= 128 { d.append(UInt8(v & 127) | 128); v >>= 7 }; d.append(UInt8(v)); return d
    }
    public struct Field { public let number: Int; public let integer: UInt64; public let data: Data
        public var text: String { String(data: data, encoding: .utf8) ?? "" }
    }
    public static func parse(_ data: Data) throws -> [Field] {
        let b = [UInt8](data); var p = 0; var fields: [Field] = []
        func read() throws -> UInt64 {
            var n: UInt64 = 0
            for i in 0..<10 {
                guard p < b.count else { throw SayError.message("服务消息不完整") }
                let v = b[p]; p += 1
                if i == 9 && v > 1 { throw SayError.message("服务消息整数越界") }
                n |= UInt64(v & 127) << (7*i)
                if v < 128 { return n }
            }; throw SayError.message("服务消息整数无效")
        }
        while p < b.count {
            let tag = try read(); let field = Int(tag >> 3); let wire = tag & 7
            guard field > 0 && field <= 536870911 else { throw SayError.message("服务消息字段无效") }
            if wire == 0 { fields.append(Field(number: field, integer: try read(), data: Data())); continue }
            let length: UInt64
            switch wire { case 1: length = 8; case 5: length = 4; case 2: length = try read(); default: throw SayError.message("服务消息编码不受支持") }
            guard length <= UInt64(b.count-p) else { throw SayError.message("服务消息长度无效") }
            let end = p+Int(length); fields.append(Field(number: field, integer: 0, data: Data(b[p..<end]))); p=end
        }; return fields
    }
}

public struct ASTEvent: Sendable {
    public let type: Int; public let text: String; public let sessionID: String
    public let status: Int; public let message: String; public let start: Int; public let end: Int
    public let receivedAt = ProcessInfo.processInfo.systemUptime
    public let usage: [String: Double]
    public init(data: Data) throws {
        // Protobuf varints are unsigned on the wire. A malformed response must
        // fail the connection, not trap while converting UInt64 to native Int.
        func integer(_ fields:[Proto.Field],_ number:Int)throws->Int {
            guard let value=Int(exactly:fields.first{$0.number==number}?.integer ?? 0) else{
                throw SayError.message("服务消息整数超出支持范围")
            }
            return value
        }
        let f = try Proto.parse(data)
        type = try integer(f,2)
        text = f.first{$0.number == 4}?.text ?? ""
        start = try integer(f,5); end = try integer(f,6)
        let m = try Proto.parse(f.first{$0.number == 1}?.data ?? Data())
        sessionID = m.first{$0.number == 1}?.text ?? ""
        status = try integer(m,3); message = m.first{$0.number == 4}?.text ?? ""
        var usage: [String: Double] = [:]
        if let billing = m.first(where: {$0.number == 5}) {
            for item in try Proto.parse(billing.data) where item.number == 1 {
                let fields = try Proto.parse(item.data)
                if let unit = fields.first(where: {$0.number == 1})?.text,
                   let value = fields.first(where: {$0.number == 2})?.data, value.count == 4 {
                    let bits = value.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << (8*$1.offset) }
                    usage[unit] = Double(Float(bitPattern: bits))
                }
            }
        }; self.usage = usage
    }
}
public enum ASTProtocol {
    public static let endpoint = URL(string: "wss://openspeech.bytedance.com/api/v4/ast/v2/translate")!
    public static let resource = "volc.service_type.10053"
    public static func request(event: Int, session: String, audio: Data = Data()) -> Data {
        let meta = Proto.string(6, session)
        var source = Proto.string(4, "pcm") + Proto.number(7, 16000) + Proto.number(8, 16) + Proto.number(9, 1)
        if !audio.isEmpty { source += Proto.bytes(14, audio) }
        let config = Proto.string(1, "s2t") + Proto.string(2, "en") + Proto.string(3, "zh")
        return Proto.bytes(1, meta) + Proto.number(2, UInt64(event)) + Proto.bytes(4, source) + Proto.bytes(6, config)
    }
}

public struct Credentials: Codable, Sendable {
    public var apiKey: String; public var appID: String; public var accessToken: String; public var legacy: Bool
    public init(apiKey: String = "", appID: String = "", accessToken: String = "", legacy: Bool = false) {
        self.apiKey=apiKey; self.appID=appID; self.accessToken=accessToken; self.legacy=legacy
    }
    public var isValid: Bool { legacy ? !appID.isEmpty && !accessToken.isEmpty : !apiKey.isEmpty }
    public var trimmed:Credentials {Credentials(apiKey:apiKey.trimmingCharacters(in:.whitespacesAndNewlines),appID:appID.trimmingCharacters(in:.whitespacesAndNewlines),accessToken:accessToken.trimmingCharacters(in:.whitespacesAndNewlines),legacy:legacy)}
}

