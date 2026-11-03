import AppKit
import SayloriCore

// Opt-in diagnostic logging. Normal launches save only the local bilingual meeting archive.
@MainActor enum TestDiagnostics {
    static let directory:URL? = {
        guard let index=CommandLine.arguments.firstIndex(where:{$0=="--self-test" || $0=="--ui-review" || $0=="--meeting-test"}),CommandLine.arguments.count>index+1 else{return nil}
        return URL(fileURLWithPath:CommandLine.arguments[index+1],isDirectory:true)
    }()
    private static let io=DispatchQueue(label:"app.saylori.diagnostics",qos:.utility)
    private static let longTest=CommandLine.arguments.contains("--meeting-test")
    private static var lastWrite=Date.distantPast
    static var events:[[String:Any]]=[]
    static var status:[String:Any]=[:]
    static func record(_ kind:String,_ values:[String:Any]=[:]){
        guard directory != nil else{return}
        var row=values;row["kind"]=kind;row["time"]=Date().timeIntervalSince1970
        events.append(row)
        if let directory,let data=try? JSONSerialization.data(withJSONObject:row,options:.sortedKeys){
            io.async {
                try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                let url=directory.appendingPathComponent("events.ndjson")
                if !FileManager.default.fileExists(atPath:url.path){FileManager.default.createFile(atPath:url.path,contents:nil)}
                if let file=try? FileHandle(forWritingTo:url){do{try file.seekToEnd();try file.write(contentsOf:data+Data([10]));try file.close()}catch{}}
            }
        }
        if !longTest && Date().timeIntervalSince(lastWrite)>1{lastWrite=Date();write("events.json",events)}
    }
    static func update(_ values:[String:Any]){
        guard directory != nil else{return};status.merge(values){_,new in new};status["updated"]=Date().timeIntervalSince1970
        write("status.json",status);if !longTest || values["stage"] as? String == "completed"{write("events.json",events)}
    }
    static func write(_ name:String,_ value:Any){
        guard let directory,JSONSerialization.isValidJSONObject(value) else{return}
        try? FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        if let data=try? JSONSerialization.data(withJSONObject:value,options:[.prettyPrinted,.sortedKeys]){io.async{try? data.write(to:directory.appendingPathComponent(name),options:.atomic)}}
    }
    static func archive(_ record:MeetingRecord){
        guard let directory else{return}
        let encoder=PropertyListEncoder();encoder.outputFormat = .binary
        if let data=try? encoder.encode(record){io.async{try? data.write(to:directory.appendingPathComponent("archive.plist"),options:.atomic)}}
    }
    static func snapshot(_ window:NSWindow,_ name:String){
        guard let directory,let view=window.contentView else{return}
        view.layoutSubtreeIfNeeded();view.displayIfNeeded()
        if let rep=view.bitmapImageRepForCachingDisplay(in:view.bounds){
            view.cacheDisplay(in:view.bounds,to:rep)
            if let data=rep.representation(using:.png,properties:[:]){try? data.write(to:directory.appendingPathComponent(name+".png"))}
        }
        record("window",["name":name,"visible":window.isVisible,"frame":NSStringFromRect(window.frame),"level":window.level.rawValue,"alpha":window.alphaValue,"screens":NSScreen.screens.map{NSStringFromRect($0.visibleFrame)}])
    }
}
