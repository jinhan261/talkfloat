import Foundation
import Combine

/// Credential work is independent from capture/translation state. No automatic prompt or retry.
@MainActor public final class CredentialSession:ObservableObject {
    @Published public var draft:Credentials {didSet{draftRevision += 1}}
    @Published public private(set) var credentials=Credentials()
    @Published public private(set) var working=false
    @Published public private(set) var message=""
    @Published public private(set) var stored=false
    private var draftRevision=0
    private var revision=0
    private let read:@Sendable (Bool)async throws->Credentials?
    private let write:@Sendable (Credentials)async throws->Void
    public init(draft:Credentials=Credentials(legacy:true),
                read:@escaping @Sendable (Bool)async throws->Credentials?={interactive in try await Task.detached{try Keychain.load(interactive:interactive)}.value},
                write:@escaping @Sendable (Credentials)async throws->Void={credentials in try await Task.detached{try Keychain.save(credentials)}.value}){
        self.draft=draft;self.read=read;self.write=write
    }
    public func load(interactive:Bool=false)async {
        guard !working else{return}
        working=true;let version=revision,editVersion=draftRevision
        defer{working=false}
        message=interactive ? "等待 macOS 授权；下方仍可填写凭据。":""
        do{
            let value=try await read(interactive)
            guard version==revision else{return}
            if let value,value.isValid{
                credentials=value;stored=true;message="已读取保存的凭据。"
                if editVersion==draftRevision{draft=value}
            }else{message=""}
        }catch{if version==revision{message=error.localizedDescription}}
    }
    public func useForSession(_ value:Credentials){
        revision += 1;credentials=value;stored=false
        message="凭据仅用于本次运行，退出后清除。"
    }
    public func persist(_ value:Credentials)async {
        guard !working else{message="钥匙串正在处理请求；当前凭据仅用于本次运行。";return}
        working=true;let version=revision
        defer{working=false}
        do{
            try await write(value)
            if version==revision{stored=true;message="凭据已保存在这台 Mac 的钥匙串。"}
        }catch{if version==revision{stored=false;message="本次仍可使用，未保存：\(error.localizedDescription)"}}
    }
}
