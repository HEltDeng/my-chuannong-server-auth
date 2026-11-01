import AppKit
import Foundation
import Security

let keychainService = "cn.mychuannong.local.sudo"
let keychainAccount = "deploy@mychangli"
let marker = "__MYCHUANNONG_LOCAL_SUDO_PASSWORD__"

func query() -> [String: Any] {
    [kSecClass as String: kSecClassGenericPassword,
     kSecAttrService as String: keychainService,
     kSecAttrAccount as String: keychainAccount,
     kSecAttrSynchronizable as String: false,
     kSecUseDataProtectionKeychain as String: false]
}
func savePassword(_ data: Data) -> OSStatus {
    let changed = SecItemUpdate(query() as CFDictionary, [kSecValueData as String: data] as CFDictionary)
    if changed != errSecItemNotFound { return changed }
    var item = query()
    item[kSecAttrLabel as String] = "我的川农服务器 sudo（仅本机）"
    item[kSecAttrDescription as String] = "用于用户已授权的川农服务器管理，不参与 iCloud 同步"
    item[kSecValueData as String] = data
    return SecItemAdd(item as CFDictionary, nil)
}
func readPassword() throws -> Data {
    var item = query()
    item[kSecReturnData as String] = true
    item[kSecMatchLimit as String] = kSecMatchLimitOne
    var result: CFTypeRef?
    let status = SecItemCopyMatching(item as CFDictionary, &result)
    guard status == errSecSuccess, let data = result as? Data else {
        throw NSError(domain: "LocalServerAuth", code: Int(status),
                      userInfo: [NSLocalizedDescriptionKey: "本地钥匙串凭据不可用（状态 \(status)）"])
    }
    return data
}
func quote(_ value: String) -> String { "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'" }

// Password is supplied only after sudo's exact prompt, through an SSH stdin pipe.
// It is never put in argv, an environment variable, a file, or program output.
func remoteSudo(password: Data, command: [String], quiet: Bool = false) throws -> Int32 {
    guard !command.isEmpty, !password.isEmpty, !password.contains(10), !password.contains(13) else {
        throw NSError(domain: "LocalServerAuth", code: 1, userInfo: [NSLocalizedDescriptionKey: "密码或命令无效"])
    }
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
    process.arguments = ["-T", "-o", "BatchMode=yes", "-o", "ConnectTimeout=15", "mychangli",
        "sudo -k -S -p " + quote(marker) + " -- " + command.map(quote).joined(separator: " ")]
    let input = Pipe(), errors = Pipe()
    process.standardInput = input
    process.standardError = errors
    process.standardOutput = quiet ? FileHandle.nullDevice : FileHandle.standardOutput
    try process.run()
    var received = Data()
    var sent = false
    while true {
        let chunk = errors.fileHandleForReading.availableData
        if chunk.isEmpty { break }
        received.append(chunk)
        if !sent && received.range(of: Data(marker.utf8)) != nil {
            var line = password
            line.append(10)
            input.fileHandleForWriting.write(line)
            input.fileHandleForWriting.closeFile()
            line.resetBytes(in: 0..<line.count)
            sent = true
        }
    }
    if !sent { input.fileHandleForWriting.closeFile() }
    process.waitUntilExit()
    if !quiet {
        let message = String(decoding: received, as: UTF8.self).replacingOccurrences(of: marker, with: "")
        FileHandle.standardError.write(Data(message.utf8))
    }
    return process.terminationStatus
}
func info(_ title: String, _ text: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = text
    alert.addButton(withTitle: "知道了")
    alert.runModal()
}
func capture() -> Int32 {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    app.activate(ignoringOtherApps: true)
    let alert = NSAlert()
    alert.messageText = "保存川农服务器 sudo 密码"
    alert.informativeText = "请填写服务器 deploy 账号的 sudo 密码。\n这是服务器密码，不是 Mac 开机密码。\n\n仅保存到这台 Mac 的本地钥匙串，不参与 iCloud 同步，不写入项目或聊天。仅用于你已授权的服务器操作。"
    let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 420, height: 30))
    field.placeholderString = "服务器 sudo 密码"
    field.setAccessibilityLabel("服务器 sudo 密码")
    alert.accessoryView = field
    alert.addButton(withTitle: "验证并保存")
    alert.addButton(withTitle: "取消")
    alert.window.title = "川农服务器凭据"
    alert.window.level = .floating
    alert.window.collectionBehavior = [.moveToActiveSpace]
    alert.window.initialFirstResponder = field
    alert.window.center()
    alert.window.makeKeyAndOrderFront(nil)
    if alert.runModal() != .alertFirstButtonReturn { return 2 }
    var secret = Data(field.stringValue.utf8)
    field.stringValue = ""
    defer { secret.resetBytes(in: 0..<secret.count) }
    do {
        let verified = try remoteSudo(password: secret, command: ["true"], quiet: true)
        guard verified == 0 else {
            info("暂未保存", "服务器未通过密码验证，或当前网络无法连接。没有保存这次输入。请确认使用服务器 deploy 账号的 sudo 密码后重新打开此程序。")
            return 1
        }
        let status = savePassword(secret)
        guard status == errSecSuccess else {
            info("暂未保存", "服务器验证已通过，但钥匙串保存失败（状态 \(status)）。密码未写入其他位置。")
            return 1
        }
        print("LOCAL_SUDO_CREDENTIAL_SAVED_AND_VERIFIED")
        info("已验证并保存", "密码已保存到本地钥匙串。回到 Codex 回复“已保存”，我会继续完成这次后台部署。")
        return 0
    } catch {
        info("暂未保存", "服务器验证或本地保存失败，请检查网络和钥匙串状态后重试。")
        return 1
    }
}
final class AuthApplicationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        DispatchQueue.main.async {
            exit(capture())
        }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        sender.activate(ignoringOtherApps: true)
        sender.windows.first?.makeKeyAndOrderFront(nil)
        return true
    }
}
let args = Array(CommandLine.arguments.dropFirst())
let mode = args.first ?? "store"
switch mode {
case "store":
    // LaunchServices must finish registering the app before creating a modal window.
    let application = NSApplication.shared
    let delegate = AuthApplicationDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.regular)
    application.run()

case "status":
    var item = query()
    item[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
    let status = SecItemCopyMatching(item as CFDictionary, nil)
    print(status == errSecSuccess ? "PRESENT_LOCAL_ONLY" : "UNAVAILABLE_STATUS_\(status)")
    exit(status == errSecSuccess ? 0 : 1)
case "run":
    do {
        var password = try readPassword()
        defer { password.resetBytes(in: 0..<password.count) }
        let result = try remoteSudo(password: password, command: Array(args.dropFirst()))
        exit(result)
    } catch {
        fputs("本地凭据不可用；请打开“川农服务器凭据”重新保存或解锁钥匙串。\n", stderr)
        exit(1)
    }
default:
    fputs("Usage: LocalServerAuth [store|status|run COMMAND ARGS...]\n", stderr)
    exit(2)
}
