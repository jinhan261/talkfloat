import Foundation

/// All disk work runs on this actor, never on the audio or UI queues. JSON is the
/// recoverable source of truth; Markdown is the user-readable, portable archive.
public actor TranscriptStore {
    public nonisolated let directory: URL
    public init(directory: URL? = nil) {
        self.directory=directory ?? FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Saylori/Recordings",isDirectory:true)
    }
    private var revisions:[UUID:Int]=[:]
    public func save(_ record: MeetingRecord) throws -> URL? {
        guard record.hasText else { return nil }
        guard record.revision >= (revisions[record.id] ?? -1) else{return nil}
        var record=record
        let echoes=SystemEchoMatcher.matches(in:record.segments)
        for i in record.segments.indices{record.segments[i].possibleEchoOf=echoes[record.segments[i].id]}
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        let formatter=DateFormatter(); formatter.dateFormat="yyyyMMdd-HHmmss"
        let base=directory.appendingPathComponent("\(formatter.string(from:record.startedAt))-\(record.id.uuidString.prefix(8))")
        let encoder=JSONEncoder(); encoder.outputFormatting=[.prettyPrinted,.sortedKeys]; encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(to:base.appendingPathExtension("json"),options:.atomic)
        let markdown=base.appendingPathExtension("md")
        try Data(record.markdown.utf8).write(to:markdown,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:base.appendingPathExtension("json").path)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:markdown.path)
        revisions[record.id]=record.revision
        return markdown
    }
    public func recoverInterrupted() throws {
        guard FileManager.default.fileExists(atPath:directory.path) else { return }
        let decoder=JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        for url in try FileManager.default.contentsOfDirectory(at:directory,includingPropertiesForKeys:nil) where url.pathExtension=="json" {
            guard var record=try? decoder.decode(MeetingRecord.self,from:Data(contentsOf:url)),record.endedAt==nil else { continue }
            record.status="意外退出 · 已恢复收到的内容"; record.endedAt=record.segments.last?.receivedAt ?? record.startedAt
            _ = try save(record)
        }
    }
}
