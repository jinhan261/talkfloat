import Foundation

/// Only Markdown goes into the user's chosen folder. Private, atomic checkpoints
/// retain received text until an ended record has been written successfully.
public actor TranscriptStore {
    public static let defaultDirectory=FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask)[0].appendingPathComponent("Saylori/Recordings",isDirectory:true)
    public static let defaultRecoveryDirectory=defaultDirectory.deletingLastPathComponent().appendingPathComponent("Recovery",isDirectory:true)
    private var directory:URL
    private let recoveryDirectory:URL
    private var revisions:[UUID:Int]=[:]
    private var completed:Set<UUID>=[]
    struct Checkpoint:Codable {var record:MeetingRecord;var destination:URL}

    public init(directory:URL=defaultDirectory,recoveryDirectory:URL=defaultRecoveryDirectory){
        self.directory=directory;self.recoveryDirectory=recoveryDirectory
    }
    public func changeDirectory(to url:URL) throws {
        var isDirectory:ObjCBool=false
        guard FileManager.default.fileExists(atPath:url.path,isDirectory:&isDirectory),isDirectory.boolValue else{
            throw CocoaError(.fileNoSuchFile,userInfo:[NSFilePathErrorKey:url.path])
        }
        let probe=url.appendingPathComponent(".talkfloat-write-check-\(UUID())")
        try Data().write(to:probe,options:.atomic)
        try FileManager.default.removeItem(at:probe)
        directory=url
    }
    private func checkpointURL(_ id:UUID)->URL{recoveryDirectory.appendingPathComponent(id.uuidString).appendingPathExtension("plist")}
    private func writePrivate(_ data:Data,to url:URL)throws{
        try FileManager.default.createDirectory(at:url.deletingLastPathComponent(),withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        try data.write(to:url,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:url.path)
    }
    private func filename(_ record:MeetingRecord)->String{
        let formatter=DateFormatter();formatter.locale=Locale(identifier:"en_US_POSIX");formatter.dateFormat="yyyyMMdd-HHmmss"
        return "\(formatter.string(from:record.startedAt))-\(record.id.uuidString.prefix(8)).md"
    }
    public func save(_ record:MeetingRecord) throws -> URL? {
        try save(record,to:directory)
    }
    private func save(_ input:MeetingRecord,to destination:URL)throws->URL? {
        guard input.hasText,!completed.contains(input.id),input.revision >= (revisions[input.id] ?? -1) else{return nil}
        var record=input
        let echoes=SystemEchoMatcher.matches(in:record.segments)
        for i in record.segments.indices{record.segments[i].possibleEchoOf=echoes[record.segments[i].id]}
        let encoder=PropertyListEncoder();encoder.outputFormat = .binary
        try writePrivate(encoder.encode(Checkpoint(record:record,destination:destination)),to:checkpointURL(record.id))
        // Advance even when the destination write fails: an older autosave must
        // never replace the newer recovery checkpoint after that failure.
        revisions[record.id]=record.revision
        if destination == Self.defaultDirectory {
            try FileManager.default.createDirectory(at:destination,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
        }
        let markdown=destination.appendingPathComponent(filename(record))
        try Data(record.markdown.utf8).write(to:markdown,options:.atomic)
        try FileManager.default.setAttributes([.posixPermissions:0o600],ofItemAtPath:markdown.path)
        if record.endedAt != nil {
            try FileManager.default.removeItem(at:checkpointURL(record.id))
            completed.insert(record.id)
        }
        return markdown
    }
    public func recoverInterrupted(legacyDirectory:URL?=nil) throws {
        if let legacyDirectory{try migrateLegacy(in:legacyDirectory)}
        guard FileManager.default.fileExists(atPath:recoveryDirectory.path) else{return}
        var firstError:Error?
        for url in try FileManager.default.contentsOfDirectory(at:recoveryDirectory,includingPropertiesForKeys:nil) where url.pathExtension=="plist" {
            do {
                let checkpoint=try PropertyListDecoder().decode(Checkpoint.self,from:Data(contentsOf:url))
                guard url.lastPathComponent==checkpointURL(checkpoint.record.id).lastPathComponent else{continue}
                var record=checkpoint.record
                if record.endedAt==nil {
                    record.status="意外退出 · 已恢复收到的内容"
                    record.endedAt=record.segments.last?.receivedAt ?? record.startedAt
                }
                _ = try save(record,to:checkpoint.destination)
            }catch{if firstError==nil{firstError=error}}
        }
        if let firstError{throw firstError}
    }
    /// Only the old app-owned folder is supplied by the app. Valid legacy JSON
    /// is moved to a private backup, never destroyed or taken from arbitrary folders.
    private func migrateLegacy(in folder:URL)throws{
        guard FileManager.default.fileExists(atPath:folder.path) else{return}
        let decoder=JSONDecoder();decoder.dateDecodingStrategy = .iso8601
        for url in try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil) where url.pathExtension=="json" {
            guard var record=try? decoder.decode(MeetingRecord.self,from:Data(contentsOf:url)),
                  url.deletingPathExtension().lastPathComponent.range(of:"^[0-9]{8}-[0-9]{6}-\(record.id.uuidString.prefix(8))$",options:.regularExpression) != nil else{continue}
            if record.endedAt==nil || !FileManager.default.fileExists(atPath:url.deletingPathExtension().appendingPathExtension("md").path){
                if record.endedAt==nil{record.status="意外退出 · 已恢复收到的内容";record.endedAt=record.segments.last?.receivedAt ?? record.startedAt}
                _ = try save(record,to:folder)
            }
            let backup=recoveryDirectory.appendingPathComponent("Legacy",isDirectory:true)
            try FileManager.default.createDirectory(at:backup,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
            var target=backup.appendingPathComponent(url.lastPathComponent)
            if FileManager.default.fileExists(atPath:target.path){target=backup.appendingPathComponent("\(UUID())-\(url.lastPathComponent)")}
            try FileManager.default.moveItem(at:url,to:target)
        }
    }
}
