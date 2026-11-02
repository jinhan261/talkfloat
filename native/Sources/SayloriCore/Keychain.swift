import Foundation
import Security
public enum Keychain {
    private static let lock=NSLock()
    private static let service="app.saylori.credentials"
    private static var query:[String:Any]{[kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:"doubao-ast"]}
    // Existing items use the file-based login keychain. LAContext does not suppress
    // legacy ACL dialogs. Serialize our calls and restore this process-local flag.
    private static func access<T>(interactive:Bool,_ body:()throws->T)throws->T {
        lock.lock();defer{lock.unlock()}
        var previous:DarwinBoolean=true
        let readStatus=SecKeychainGetUserInteractionAllowed(&previous)
        guard readStatus==errSecSuccess else{throw AccessError.status(readStatus)}
        let status=SecKeychainSetUserInteractionAllowed(interactive)
        guard status==errSecSuccess else{throw AccessError.status(status)}
        defer{SecKeychainSetUserInteractionAllowed(previous.boolValue)}
        return try body()
    }
    public enum AccessError:LocalizedError {
        case status(OSStatus)
        public var errorDescription:String? {
            switch self {
            case .status(let status) where [errSecInteractionNotAllowed,errSecAuthFailed,errSecUserCanceled].contains(status):
                return "钥匙串尚未授权。可以直接填写凭据，仅在本次使用；旧凭据仍保留。"
            case .status(let status):return "钥匙串暂不可用（\(status)）。可以仅在本次使用凭据。"
            }
        }
    }
    public static func load(interactive:Bool=false) throws -> Credentials? {
        try access(interactive:interactive){
        var q=query;q[kSecReturnData as String]=true;q[kSecMatchLimit as String]=kSecMatchLimitOne
        var item:CFTypeRef?;let status=SecItemCopyMatching(q as CFDictionary,&item)
        if status==errSecItemNotFound{return nil}
        guard status==errSecSuccess,let data=item as? Data else{throw AccessError.status(status)}
        return try JSONDecoder().decode(Credentials.self,from:data)
        }
    }
    public static func save(_ c:Credentials)throws {
        try access(interactive:false){
        let data=try JSONEncoder().encode(c)
        let status=SecItemUpdate(query as CFDictionary,[kSecValueData as String:data] as CFDictionary)
        if status==errSecItemNotFound{
            var q=query;q[kSecValueData as String]=data;q[kSecAttrAccessible as String]=kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let result=SecItemAdd(q as CFDictionary,nil)
            guard result==errSecSuccess else{throw AccessError.status(result)}
        }else if status != errSecSuccess{throw AccessError.status(status)}
        }
    }
}
