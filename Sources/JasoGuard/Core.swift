import Foundation
import Darwin
#if canImport(CoreServices)
import CoreServices
#endif
#if canImport(AppKit)
import AppKit
#endif

private let appName = "JasoGuard"
private let defaultLabel = "io.github.local.jasoguard"

@inline(__always)
private func stderr(_ message: String) {
    FileHandle.standardError.write((message + "\n").data(using: .utf8)!)
}

@inline(__always)
private func stdout(_ message: String) {
    FileHandle.standardOutput.write((message + "\n").data(using: .utf8)!)
}

private func nowISO() -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.string(from: Date())
}

@inline(__always)
private func log(_ level: String, _ message: String) {
    stderr("\(nowISO()) [\(level)] \(message)")
}

private func expandPath(_ value: String) -> String {
    if value == "~" { return FileManager.default.homeDirectoryForCurrentUser.path }
    if value.hasPrefix("~/") {
        let suffix = String(value.dropFirst(2))
        return FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(suffix).standardizedFileURL.path
    }
    return (value as NSString).expandingTildeInPath
}

private func canonicalPath(_ value: String) -> String {
    URL(fileURLWithPath: expandPath(value)).standardizedFileURL.path
}

private struct WatchPath: Codable, Equatable {
    var path: String
    var recursive: Bool
}

private struct Config: Codable {
    var watch: [WatchPath]
    var ignore: [String]
    var latencySeconds: Double
    var directoryEventDepth: Int
    var scanExistingOnStart: Bool
    var startupScanDepth: Int
    var skipHiddenFiles: Bool

    enum CodingKeys: String, CodingKey {
        case watch
        case ignore
        case latencySeconds
        case directoryEventDepth
        case scanExistingOnStart
        case startupScanDepth
        case skipHiddenFiles
    }

    init(
        watch: [WatchPath],
        ignore: [String],
        latencySeconds: Double,
        directoryEventDepth: Int,
        scanExistingOnStart: Bool,
        startupScanDepth: Int,
        skipHiddenFiles: Bool
    ) {
        self.watch = watch
        self.ignore = ignore
        self.latencySeconds = latencySeconds
        self.directoryEventDepth = directoryEventDepth
        self.scanExistingOnStart = scanExistingOnStart
        self.startupScanDepth = startupScanDepth
        self.skipHiddenFiles = skipHiddenFiles
    }

    init(from decoder: Decoder) throws {
        let defaults = Config.defaultConfig()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        watch = try container.decodeIfPresent([WatchPath].self, forKey: .watch) ?? defaults.watch
        ignore = try container.decodeIfPresent([String].self, forKey: .ignore) ?? defaults.ignore
        latencySeconds = try container.decodeIfPresent(Double.self, forKey: .latencySeconds) ?? defaults.latencySeconds
        directoryEventDepth = try container.decodeIfPresent(Int.self, forKey: .directoryEventDepth) ?? defaults.directoryEventDepth
        scanExistingOnStart = try container.decodeIfPresent(Bool.self, forKey: .scanExistingOnStart) ?? defaults.scanExistingOnStart
        startupScanDepth = try container.decodeIfPresent(Int.self, forKey: .startupScanDepth) ?? defaults.startupScanDepth
        skipHiddenFiles = try container.decodeIfPresent(Bool.self, forKey: .skipHiddenFiles) ?? defaults.skipHiddenFiles
    }

    static var directoryURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".config", isDirectory: true)
            .appendingPathComponent("jasoguard", isDirectory: true)
    }

    static var fileURL: URL {
        directoryURL.appendingPathComponent("config.json", isDirectory: false)
    }

    static var stateURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".local", isDirectory: true)
            .appendingPathComponent("state", isDirectory: true)
            .appendingPathComponent("jasoguard", isDirectory: true)
    }

    static func defaultConfig() -> Config {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let defaults = ["Desktop", "Documents", "Downloads"].map { name in
            WatchPath(path: home.appendingPathComponent(name, isDirectory: true).path, recursive: true)
        }
        return Config(
            watch: defaults,
            ignore: [
                home.appendingPathComponent("Library", isDirectory: true).path,
                home.appendingPathComponent(".Trash", isDirectory: true).path
            ],
            latencySeconds: 0.25,
            directoryEventDepth: 2,
            scanExistingOnStart: true,
            startupScanDepth: 8,
            skipHiddenFiles: false
        )
    }

    static func load() throws -> Config {
        let url = Config.fileURL
        if !FileManager.default.fileExists(atPath: url.path) {
            let config = Config.defaultConfig()
            try config.save()
            return config
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(Config.self, from: data)
    }

    func save() throws {
        try FileManager.default.createDirectory(at: Config.directoryURL, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(self)
        try data.write(to: Config.fileURL, options: [.atomic])
    }

    func expandedWatchPaths() -> [String] {
        watch.map { canonicalPath($0.path) }
    }

    func expandedIgnorePaths() -> [String] {
        ignore.map { canonicalPath($0) }
    }

    func isIgnored(_ path: String) -> Bool {
        let target = canonicalPath(path)
        for ignored in expandedIgnorePaths() {
            if target == ignored || target.hasPrefix(ignored + "/") { return true }
        }
        return false
    }
}

private final class NFCNormalizer {
    private let fm = FileManager.default
    private let dryRun: Bool
    private let skipHidden: Bool
    private(set) var renamed: Int = 0
    private(set) var skipped: Int = 0
    private(set) var collisions: Int = 0
    private(set) var errors: Int = 0

    private struct DiskEntry {
        let fullPath: String
        let parentPath: String
        let name: String
    }

    init(dryRun: Bool = false, skipHidden: Bool = false) {
        self.dryRun = dryRun
        self.skipHidden = skipHidden
    }

    @inline(__always)
    private func hasNonASCII(_ name: String) -> Bool {
        for scalar in name.unicodeScalars {
            if scalar.value >= 0x80 { return true }
        }
        return false
    }

    @inline(__always)
    private func sameUnicodeScalars(_ lhs: String, _ rhs: String) -> Bool {
        lhs.unicodeScalars.elementsEqual(rhs.unicodeScalars)
    }

    @inline(__always)
    private func nfcName(_ name: String) -> String {
        (name as NSString).precomposedStringWithCanonicalMapping
    }

    @inline(__always)
    private func needsNFCConversion(_ name: String) -> Bool {
        let normalized = nfcName(name)
        // Swift String equality is Unicode-canonical-equivalence aware, so
        // "한" (NFC) and "한" (NFD) can compare equal with ==.
        // Compare scalar sequences so the target is Windows-compatible NFC bytes.
        return !sameUnicodeScalars(name, normalized)
    }

    private func shouldSkipName(_ name: String) -> Bool {
        if name.isEmpty || name == "." || name == ".." { return true }
        if skipHidden && name.first == "." { return true }
        return !hasNonASCII(name)
    }

    private func splitParentAndName(_ fullPath: String) -> (String, String)? {
        guard let slashIndex = fullPath.lastIndex(of: "/") else { return nil }
        let parent = String(fullPath[..<slashIndex])
        let name = String(fullPath[fullPath.index(after: slashIndex)...])
        if parent.isEmpty { return ("/", name) }
        return (parent, name)
    }

    private func actualDiskEntry(for url: URL) -> DiskEntry? {
        // nfd2nfc의 핵심처럼 F_GETPATH로 실제 파일시스템 경로를 얻는다.
        // 단, 최종 대상 경로는 URL.appendingPathComponent로 만들지 않는다.
        // Foundation URL/path는 macOS 파일시스템 표현으로 다시 정규화할 수 있어
        // NFC로 만든 이름이 rename 직전에 다시 NFD처럼 바뀌는 문제가 생긴다.
        let fd = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW)
        let fallbackFD = fd >= 0 ? fd : Darwin.open(url.path, O_EVTONLY)
        guard fallbackFD >= 0 else { return nil }
        defer { Darwin.close(fallbackFD) }

        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        let result = buffer.withUnsafeMutableBufferPointer { pointer -> Int32 in
            guard let base = pointer.baseAddress else { return -1 }
            return Darwin.fcntl(fallbackFD, F_GETPATH, base)
        }
        guard result != -1 else { return nil }

        let fullPath = String(cString: buffer)
        guard let (parentPath, name) = splitParentAndName(fullPath), !name.isEmpty else { return nil }
        return DiskEntry(fullPath: fullPath, parentPath: parentPath, name: name)
    }

    private func makePath(parent: String, name: String) -> String {
        parent == "/" ? "/" + name : parent + "/" + name
    }

    private func pathExists(_ path: String) -> Bool {
        var statBuffer = stat()
        return path.withCString { Darwin.lstat($0, &statBuffer) == 0 }
    }

    private func sameFilesystemItem(_ lhsPath: String, _ rhsPath: String) -> Bool {
        var lhs = stat()
        var rhs = stat()
        let lhsOK = lhsPath.withCString { Darwin.lstat($0, &lhs) == 0 }
        let rhsOK = rhsPath.withCString { Darwin.lstat($0, &rhs) == 0 }
        return lhsOK && rhsOK && lhs.st_dev == rhs.st_dev && lhs.st_ino == rhs.st_ino
    }

    private func temporaryPath(parent: String, originalName: String) -> String {
        for index in 0..<100 {
            let suffix = index == 0 ? UUID().uuidString : "\(UUID().uuidString)-\(index)"
            let candidate = makePath(parent: parent, name: ".jasoguard-renaming-\(suffix)-\(originalName)")
            if !pathExists(candidate) { return candidate }
        }
        return makePath(parent: parent, name: ".jasoguard-renaming-\(UUID().uuidString)-\(originalName)")
    }

    private func posixRenameRaw(from sourcePath: String, to destinationPath: String) throws {
        // sourcePath는 F_GETPATH에서 온 실제 경로이고, destinationPath는
        // 실제 parentPath + NFC 이름을 문자열 결합으로 만든 값이다.
        // URL.path를 통하지 않아 NFC UTF-8 바이트가 그대로 rename에 전달된다.
        let result = sourcePath.withCString { sourcePtr in
            destinationPath.withCString { destinationPtr in
                Darwin.rename(sourcePtr, destinationPtr)
            }
        }
        if result != 0 {
            throw NSError(
                domain: NSPOSIXErrorDomain,
                code: Int(errno),
                userInfo: [NSLocalizedDescriptionKey: String(cString: strerror(errno))]
            )
        }
    }

    private func moveWithNormalizationSafeRename(from sourcePath: String, to destinationPath: String, parentPath: String, originalName: String) throws {
        if pathExists(destinationPath) {
            guard sameFilesystemItem(sourcePath, destinationPath) else {
                collisions += 1
                log("WARN", "collision; leaving unchanged: \(sourcePath) -> \(destinationPath)")
                return
            }

            // 정규화 차이만 있는 rename은 같은 inode로 해석될 수 있다.
            // ASCII 임시 이름으로 빠졌다가 NFC 이름으로 들어가서 디렉터리 엔트리의
            // 최종 UTF-8 바이트가 Windows와 같은 조합형이 되도록 한다.
            let tempPath = temporaryPath(parent: parentPath, originalName: originalName)
            try posixRenameRaw(from: sourcePath, to: tempPath)
            do {
                try posixRenameRaw(from: tempPath, to: destinationPath)
            } catch {
                try? posixRenameRaw(from: tempPath, to: sourcePath)
                throw error
            }
            return
        }

        try posixRenameRaw(from: sourcePath, to: destinationPath)
    }

    private func scalarDebug(_ value: String) -> String {
        value.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
    }

    func normalizeOne(_ url: URL) {
        guard let entry = actualDiskEntry(for: url) else {
            skipped += 1
            return
        }
        let actualName = entry.name
        guard !shouldSkipName(actualName) else {
            skipped += 1
            return
        }

        let normalizedName = nfcName(actualName)
        guard needsNFCConversion(actualName) else {
            skipped += 1
            return
        }

        let destinationPath = makePath(parent: entry.parentPath, name: normalizedName)

        if dryRun {
            renamed += 1
            stdout("DRY-RUN \(entry.fullPath) -> \(destinationPath)")
            stdout("  from scalars: \(scalarDebug(actualName))")
            stdout("  to scalars:   \(scalarDebug(normalizedName))")
            return
        }

        do {
            let previousCollisions = collisions
            try moveWithNormalizationSafeRename(
                from: entry.fullPath,
                to: destinationPath,
                parentPath: entry.parentPath,
                originalName: actualName
            )
            if collisions == previousCollisions {
                renamed += 1
                log("INFO", "renamed: \(entry.fullPath) -> \(destinationPath)")
            }
        } catch {
            errors += 1
            log("ERROR", "rename failed: \(entry.fullPath): \(error.localizedDescription)")
        }
    }

    func normalizePath(_ path: String) {
        let url = URL(fileURLWithPath: canonicalPath(path))
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            skipped += 1
            return
        }
        normalizeOne(url)
    }

    func normalizeDirectoryChildren(_ path: String, maxDepth: Int) {
        let root = URL(fileURLWithPath: canonicalPath(path), isDirectory: true)
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: root.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            normalizePath(path)
            return
        }

        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: skipHidden ? [.skipsHiddenFiles, .skipsPackageDescendants] : [.skipsPackageDescendants],
            errorHandler: { url, error in
                log("ERROR", "enumerate failed: \(url.path): \(error.localizedDescription)")
                return true
            }
        ) else {
            errors += 1
            return
        }

        var urls: [URL] = [root]
        let rootDepth = root.pathComponents.count
        for case let item as URL in enumerator {
            if maxDepth >= 0 && item.pathComponents.count - rootDepth > maxDepth {
                enumerator.skipDescendants()
                continue
            }
            urls.append(item)
        }

        urls.sort { lhs, rhs in lhs.pathComponents.count > rhs.pathComponents.count }
        for url in urls { normalizeOne(url) }
    }

    func convertRecursively(_ path: String) {
        normalizeDirectoryChildren(path, maxDepth: Int.max)
    }

    func summary() -> String {
        "renamed=\(renamed) skipped=\(skipped) collisions=\(collisions) errors=\(errors)"
    }
}

#if canImport(CoreServices)
private final class FileEventWatcher {
    private let config: Config
    private let normalizer: NFCNormalizer
    private var streams: [FSEventStreamRef] = []
    private let queue = DispatchQueue(label: "io.github.local.jasoguard.eventqueue", qos: .utility)
    private var pending = Set<String>()
    private var flushScheduled = false

    init(config: Config) {
        self.config = config
        self.normalizer = NFCNormalizer(dryRun: false, skipHidden: config.skipHiddenFiles)
    }

    func start(blocking: Bool = true) throws {
        let paths = config.expandedWatchPaths().filter { path in
            var isDirectory: ObjCBool = false
            return FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
        }
        if paths.isEmpty {
            throw NSError(domain: appName, code: 2, userInfo: [NSLocalizedDescriptionKey: "No valid watch paths. Add a path first."])
        }

        let callback: FSEventStreamCallback = { _, info, count, eventPaths, _, _ in
            guard let info else { return }
            let watcher = Unmanaged<FileEventWatcher>.fromOpaque(info).takeUnretainedValue()
            let nsArray = unsafeBitCast(eventPaths, to: NSArray.self)
            var changed: [String] = []
            changed.reserveCapacity(count)
            for item in nsArray {
                if let path = item as? String { changed.append(path) }
            }
            watcher.enqueue(changed)
        }

        for path in paths {
            var context = FSEventStreamContext(
                version: 0,
                info: Unmanaged.passUnretained(self).toOpaque(),
                retain: nil,
                release: nil,
                copyDescription: nil
            )
            let flags = FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagNoDefer |
                kFSEventStreamCreateFlagWatchRoot
            )
            guard let stream = FSEventStreamCreate(
                kCFAllocatorDefault,
                callback,
                &context,
                [path] as CFArray,
                FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
                config.latencySeconds,
                flags
            ) else {
                throw NSError(domain: appName, code: 3, userInfo: [NSLocalizedDescriptionKey: "FSEvents stream failed for \(path)"])
            }
            FSEventStreamSetDispatchQueue(stream, DispatchQueue.global(qos: .utility))
            FSEventStreamStart(stream)
            streams.append(stream)
            log("INFO", "watching: \(path)")
        }
        if blocking { dispatchMain() }
    }

    func stop() {
        for stream in streams {
            FSEventStreamStop(stream)
            FSEventStreamInvalidate(stream)
            FSEventStreamRelease(stream)
        }
        streams.removeAll()
    }

    func scanWatchPaths(maxDepth: Int, completion: (() -> Void)? = nil) {
        let paths = config.expandedWatchPaths()
        queue.async {
            log("INFO", "manual/startup scan started: depth=\(maxDepth)")
            for path in paths where !self.config.isIgnored(path) {
                self.normalizer.normalizeDirectoryChildren(path, maxDepth: maxDepth)
            }
            log("INFO", "manual/startup scan finished: \(self.normalizer.summary())")
            completion?()
        }
    }

    private func enqueue(_ paths: [String]) {
        queue.async {
            for path in paths where !self.config.isIgnored(path) {
                self.pending.insert(canonicalPath(path))
            }
            if !self.flushScheduled {
                self.flushScheduled = true
                let delay = max(0.05, self.config.latencySeconds)
                self.queue.asyncAfter(deadline: .now() + delay) { self.flush() }
            }
        }
    }

    private func flush() {
        let batch = Array(pending)
        pending.removeAll(keepingCapacity: true)
        flushScheduled = false
        for path in batch {
            if self.config.isIgnored(path) { continue }
            normalizer.normalizeDirectoryChildren(path, maxDepth: config.directoryEventDepth)
        }
    }

    deinit {
        stop()
    }
}
#endif

private func xmlEscape(_ value: String) -> String {
    var escaped = value.replacingOccurrences(of: "&", with: "&amp;")
    escaped = escaped.replacingOccurrences(of: "<", with: "&lt;")
    escaped = escaped.replacingOccurrences(of: ">", with: "&gt;")
    escaped = escaped.replacingOccurrences(of: "\"", with: "&quot;")
    escaped = escaped.replacingOccurrences(of: "'", with: "&apos;")
    return escaped
}

private enum LaunchAgent {
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("LaunchAgents", isDirectory: true)
            .appendingPathComponent(defaultLabel + ".plist", isDirectory: false)
    }

    static func isInstalled() -> Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func install(executablePath: String, launchArguments: [String] = [], startNow: Bool = true) throws {
        try FileManager.default.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: Config.stateURL, withIntermediateDirectories: true)

        let outLog = Config.stateURL.appendingPathComponent("stdout.log").path
        let errLog = Config.stateURL.appendingPathComponent("stderr.log").path
        let programArguments = ([executablePath] + launchArguments)
            .map { "        <string>\(xmlEscape($0))</string>" }
            .joined(separator: "\n")
        let xml = [
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?>",
            "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">",
            "<plist version=\"1.0\">",
            "<dict>",
            "    <key>Label</key>",
            "    <string>\(defaultLabel)</string>",
            "    <key>ProgramArguments</key>",
            "    <array>",
            programArguments,
            "    </array>",
            "    <key>RunAtLoad</key>",
            "    <true/>",
            "    <key>KeepAlive</key>",
            "    <dict>",
            "        <key>SuccessfulExit</key>",
            "        <false/>",
            "    </dict>",
            "    <key>StandardOutPath</key>",
            "    <string>\(xmlEscape(outLog))</string>",
            "    <key>StandardErrorPath</key>",
            "    <string>\(xmlEscape(errLog))</string>",
            "</dict>",
            "</plist>",
            ""
        ].joined(separator: "\n")
        try xml.data(using: .utf8)!.write(to: plistURL, options: [.atomic])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plistURL.path)

        _ = runLaunchctl(["enable", "gui/\(getuid())/\(defaultLabel)"])
        guard startNow else { return }

        _ = runLaunchctl(["bootout", "gui/\(getuid())", plistURL.path])
        let result = runLaunchctl(["bootstrap", "gui/\(getuid())", plistURL.path])
        if result != 0 { throw NSError(domain: appName, code: 10, userInfo: [NSLocalizedDescriptionKey: "launchctl bootstrap failed with exit \(result)"]) }
        _ = runLaunchctl(["kickstart", "-k", "gui/\(getuid())/\(defaultLabel)"])
    }

    static func uninstall(stopRunning: Bool = true) throws {
        _ = runLaunchctl(["disable", "gui/\(getuid())/\(defaultLabel)"])
        if stopRunning { _ = runLaunchctl(["bootout", "gui/\(getuid())", plistURL.path]) }
        if FileManager.default.fileExists(atPath: plistURL.path) {
            try FileManager.default.removeItem(at: plistURL)
        }
    }

    private static func runLaunchctl(_ args: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        process.arguments = args
        process.standardOutput = FileHandle.standardError
        process.standardError = FileHandle.standardError
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus
        } catch {
            log("ERROR", "launchctl failed: \(error.localizedDescription)")
            return 127
        }
    }
}

private func executablePathFromArgs(_ args: [String]) -> String {
    if let index = args.firstIndex(of: "--app-path"), index + 1 < args.count {
        return URL(fileURLWithPath: canonicalPath(args[index + 1]))
            .appendingPathComponent("Contents/MacOS/JasoGuard", isDirectory: false)
            .path
    }
    return URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
}


#if canImport(AppKit)
private enum AppLanguage: String {
    case system
    case english = "en"
    case korean = "ko"
}

private let languagePreferenceKey = "languagePreference"

private enum L {
    private static func activeLanguageCode() -> String {
        let stored = UserDefaults.standard.string(forKey: languagePreferenceKey) ?? AppLanguage.system.rawValue
        if stored == AppLanguage.english.rawValue { return "en" }
        if stored == AppLanguage.korean.rawValue { return "ko" }
        if #available(macOS 13.0, *) {
            return Locale.current.language.languageCode?.identifier == "ko" ? "ko" : "en"
        }
        return Locale.current.languageCode == "ko" ? "ko" : "en"
    }

    static func tr(_ key: String) -> String {
        let ko: [String: String] = [
            "status.running": "실행 중",
            "status.error": "오류",
            "status.waiting": "확인 대기",
            "menu.status": "상태",
            "menu.error": "오류",
            "menu.login": "로그인 시 자동 실행",
            "menu.launchAlert": "실행 확인 창 표시",
            "menu.language": "언어",
            "menu.language.system": "시스템 언어",
            "menu.language.english": "English",
            "menu.language.korean": "한국어",
            "menu.restart": "감시 재시작",
            "menu.scan": "지금 감시 경로 스캔",
            "menu.config": "설정 파일 열기",
            "menu.logs": "로그 폴더 열기",
            "menu.hide": "위젯 숨기기",
            "menu.quit": "완전 종료",
            "alert.ok": "확인",
            "alert.cancel": "취소",
            "alert.hide": "숨기기",
            "alert.quit": "완전 종료",
            "alert.restart.ok": "감시를 다시 시작했습니다.",
            "alert.restart.failed": "감시 재시작에 실패했습니다",
            "alert.scan.title": "스캔 시작",
            "alert.scan.message": "현재 감시 경로의 기존 파일/폴더 이름 변환을 시작했습니다. 진행 결과는 로그 폴더에서 확인할 수 있습니다.",
            "alert.scan.failed": "스캔 실패",
            "alert.login.failed": "자동 실행 설정 실패",
            "alert.config.failed": "설정 파일을 열 수 없음",
            "alert.logs.failed": "로그 폴더를 열 수 없음",
            "alert.hide.title": "메뉴바 위젯을 숨길까요?",
            "alert.hide.message": "감시는 계속 실행됩니다. 다시 표시하려면 /Applications/JasoGuard.app을 다시 열면 됩니다.",
            "alert.quit.title": "JasoGuard를 완전 종료할까요?",
            "alert.quit.message": "백그라운드 감시를 멈추고, 로그인 자동 실행도 해제한 뒤 앱을 종료합니다.",
            "alert.launch.title": "JasoGuard가 실행 중입니다",
            "alert.login.on": "켜짐",
            "alert.login.off": "꺼짐",
            "alert.watch.paths": "감시 대상",
            "alert.config.watch": "설정 파일의 watch 경로",
            "alert.language.changed.title": "언어 변경",
            "alert.language.changed.message": "메뉴와 알림 언어를 변경했습니다.",
            "preflight.start.title": "시작 전 확인",
            "preflight.scan.title": "스캔 전 확인",
            "preflight.start.button": "동의하고 시작",
            "preflight.scan.button": "동의하고 스캔",
            "preflight.settings.button": "권한 설정 열기",
            "preflight.quit.button": "종료",
            "preflight.cancel.button": "취소",
            "preflight.permission.header": "권한 확인 결과",
            "preflight.privacy.header": "개인정보 및 파일 보호 안내",
            "preflight.scan.header": "스캔/변환 안내",
            "preflight.privacy.body": "JasoGuard는 감시 대상 경로 안의 파일/폴더 이름만 확인하고, 한글 자소분리된 이름을 NFC 이름으로 바꿉니다. 파일 내용은 읽거나 수정하지 않으며, 삭제/덮어쓰기/업로드/네트워크 전송을 하지 않습니다. 같은 이름 충돌이 있으면 그대로 건너뜁니다.",
            "preflight.scan.body": "동의하면 감시를 시작합니다. 설정에서 scanExistingOnStart가 켜져 있으면 기존 파일/폴더 이름도 시작 시 한 번 스캔합니다. 이후 새로 생성되거나 변경된 이름은 약 0.25초 단위로 처리됩니다.",
            "preflight.manual.scan.body": "동의하면 현재 감시 대상 경로를 즉시 스캔합니다. 파일 내용은 변경하지 않고 이름 정규화가 필요한 항목만 이름 변경을 시도합니다.",
            "preflight.path.ok": "읽기 가능",
            "preflight.path.missing": "없음",
            "preflight.path.notdir": "폴더 아님",
            "preflight.path.denied": "읽기 실패 또는 권한 필요",
            "preflight.waiting": "사용자 확인을 기다리는 중입니다. 메뉴에서 감시 재시작을 누르면 다시 확인할 수 있습니다."
        ]
        let en: [String: String] = [
            "status.running": "Running",
            "status.error": "Error",
            "status.waiting": "Waiting",
            "menu.status": "Status",
            "menu.error": "Error",
            "menu.login": "Launch at Login",
            "menu.launchAlert": "Show Launch Confirmation",
            "menu.language": "Language",
            "menu.language.system": "System Language",
            "menu.language.english": "English",
            "menu.language.korean": "한국어",
            "menu.restart": "Restart Watcher",
            "menu.scan": "Scan Watch Paths Now",
            "menu.config": "Open Config File",
            "menu.logs": "Open Log Folder",
            "menu.hide": "Hide Widget",
            "menu.quit": "Quit Completely",
            "alert.ok": "OK",
            "alert.cancel": "Cancel",
            "alert.hide": "Hide",
            "alert.quit": "Quit Completely",
            "alert.restart.ok": "Watcher restarted.",
            "alert.restart.failed": "Failed to restart watcher",
            "alert.scan.title": "Scan Started",
            "alert.scan.message": "Started converting existing file/folder names in the current watch paths. Check the log folder for progress.",
            "alert.scan.failed": "Scan Failed",
            "alert.login.failed": "Launch at Login Failed",
            "alert.config.failed": "Could Not Open Config File",
            "alert.logs.failed": "Could Not Open Log Folder",
            "alert.hide.title": "Hide the menu bar widget?",
            "alert.hide.message": "The watcher will keep running. Open /Applications/JasoGuard.app again to show it.",
            "alert.quit.title": "Quit JasoGuard completely?",
            "alert.quit.message": "This stops background watching, disables Launch at Login, and quits the app.",
            "alert.launch.title": "JasoGuard is running",
            "alert.login.on": "On",
            "alert.login.off": "Off",
            "alert.watch.paths": "Watch paths",
            "alert.config.watch": "watch paths from the config file",
            "alert.language.changed.title": "Language Changed",
            "alert.language.changed.message": "Menu and alert language has been updated.",
            "preflight.start.title": "Before Starting",
            "preflight.scan.title": "Before Scanning",
            "preflight.start.button": "Agree and Start",
            "preflight.scan.button": "Agree and Scan",
            "preflight.settings.button": "Open Permissions",
            "preflight.quit.button": "Quit",
            "preflight.cancel.button": "Cancel",
            "preflight.permission.header": "Permission Check",
            "preflight.privacy.header": "Privacy and File Safety",
            "preflight.scan.header": "Scan/Conversion Notice",
            "preflight.privacy.body": "JasoGuard only checks file/folder names inside the configured watch paths and renames decomposed Korean filenames to NFC. It does not read or modify file contents, delete files, overwrite collisions, upload data, or send anything over the network. If a target name already exists, it skips the item.",
            "preflight.scan.body": "If you agree, watching starts now. If scanExistingOnStart is enabled, existing file/folder names are scanned once at startup. New or changed names are then processed in roughly 0.25-second batches.",
            "preflight.manual.scan.body": "If you agree, the current watch paths are scanned immediately. JasoGuard does not modify file contents; it only attempts filename normalization where needed.",
            "preflight.path.ok": "Readable",
            "preflight.path.missing": "Missing",
            "preflight.path.notdir": "Not a folder",
            "preflight.path.denied": "Read failed or permission needed",
            "preflight.waiting": "Waiting for your confirmation. Choose Restart Watcher from the menu to review this again."
        ]
        return (activeLanguageCode() == "ko" ? ko[key] : en[key]) ?? key
    }
}


#if canImport(AppKit)
private enum MenuBarStatusIcon {
    static func image(hasError: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }

        NSColor.black.setStroke()
        NSColor.black.setFill()

        let circle = NSBezierPath(ovalIn: NSRect(x: 3.0, y: 3.0, width: 12.0, height: 12.0))
        circle.lineWidth = 1.7
        circle.stroke()

        if hasError {
            let bar = NSBezierPath(roundedRect: NSRect(x: 8.1, y: 6.6, width: 1.8, height: 5.4), xRadius: 0.9, yRadius: 0.9)
            bar.fill()
            let dot = NSBezierPath(ovalIn: NSRect(x: 7.9, y: 4.1, width: 2.2, height: 2.2))
            dot.fill()
        } else {
            let check = NSBezierPath()
            check.move(to: NSPoint(x: 5.1, y: 8.7))
            check.line(to: NSPoint(x: 7.6, y: 6.2))
            check.line(to: NSPoint(x: 12.8, y: 11.4))
            check.lineWidth = 1.9
            check.lineCapStyle = .round
            check.lineJoinStyle = .round
            check.stroke()
        }

        image.isTemplate = true
        image.accessibilityDescription = hasError ? "JasoGuard error" : "JasoGuard running"
        return image
    }
}
#endif

private let showLaunchConfirmationKey = "showLaunchConfirmation"

private final class JasoGuardAppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var watcherError: String?
    private var launchAlertShown = false
    private var isWaitingForPreflight = false

    #if canImport(CoreServices)
    private var watcher: FileEventWatcher?
    #endif

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        registerDefaultPreferences()
        ensureRuntimeFiles()
        createStatusItemIfNeeded()

        DispatchQueue.main.async {
            self.runPreflightThenStart(showLaunchConfirmationAfterStart: true)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        createStatusItemIfNeeded()
        showLaunchConfirmation(force: true)
        return true
    }

    private func registerDefaultPreferences() {
        UserDefaults.standard.register(defaults: [showLaunchConfirmationKey: true, languagePreferenceKey: AppLanguage.system.rawValue])
    }

    private func ensureRuntimeFiles() {
        do {
            _ = try Config.load()
            try FileManager.default.createDirectory(at: Config.stateURL, withIntermediateDirectories: true)
        } catch {
            watcherError = "Initialization failed: \(error.localizedDescription)"
            log("ERROR", watcherError ?? "initialization failed")
        }
    }

    private func startWatcherForMenuBarApp() {
        #if canImport(CoreServices)
        do {
            let config = try Config.load()
            let newWatcher = FileEventWatcher(config: config)
            try newWatcher.start(blocking: false)
            watcher = newWatcher
            watcherError = nil
            isWaitingForPreflight = false
            log("INFO", "menu bar watcher started")
            if config.scanExistingOnStart {
                newWatcher.scanWatchPaths(maxDepth: config.startupScanDepth)
            }
        } catch {
            watcher = nil
            isWaitingForPreflight = false
            watcherError = error.localizedDescription
            log("ERROR", "menu bar watcher failed: \(error.localizedDescription)")
        }
        #else
        watcherError = "FSEvents requires macOS."
        #endif
    }

    private func restartWatcher() {
        #if canImport(CoreServices)
        watcher?.stop()
        watcher = nil
        #endif
        startWatcherForMenuBarApp()
        refreshStatusItem()
    }

    private func statusText() -> String {
        if isWaitingForPreflight { return L.tr("status.waiting") }
        return watcherError == nil ? L.tr("status.running") : L.tr("status.error")
    }

    private func statusIcon() -> NSImage {
        MenuBarStatusIcon.image(hasError: watcherError != nil)
    }

    private func createStatusItemIfNeeded() {
        guard statusItem == nil else {
            refreshStatusItem()
            return
        }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = item.button {
            button.title = ""
            button.image = statusIcon()
            button.imagePosition = .imageOnly
            button.toolTip = "JasoGuard - \(statusText())"
            button.setAccessibilityLabel("JasoGuard - \(statusText())")
        }
        statusItem = item
        rebuildMenu()
    }

    private func refreshStatusItem() {
        if let button = statusItem?.button {
            button.title = ""
            button.image = statusIcon()
            button.imagePosition = .imageOnly
            button.toolTip = "JasoGuard - \(statusText())"
            button.setAccessibilityLabel("JasoGuard - \(statusText())")
        }
        rebuildMenu()
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let title = NSMenuItem(title: "JasoGuard", action: nil, keyEquivalent: "")
        title.isEnabled = false
        menu.addItem(title)

        let state = NSMenuItem(title: "\(L.tr("menu.status")): \(statusText())", action: #selector(refreshStatus), keyEquivalent: "")
        state.target = self
        menu.addItem(state)

        if let watcherError {
            let errorItem = NSMenuItem(title: "\(L.tr("menu.error")): \(watcherError)", action: nil, keyEquivalent: "")
            errorItem.isEnabled = false
            menu.addItem(errorItem)
        }

        menu.addItem(NSMenuItem.separator())

        let loginItem = NSMenuItem(title: L.tr("menu.login"), action: #selector(toggleLoginItem), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LaunchAgent.isInstalled() ? .on : .off
        menu.addItem(loginItem)

        let launchAlertItem = NSMenuItem(title: L.tr("menu.launchAlert"), action: #selector(toggleLaunchConfirmation), keyEquivalent: "")
        launchAlertItem.target = self
        launchAlertItem.state = UserDefaults.standard.bool(forKey: showLaunchConfirmationKey) ? .on : .off
        menu.addItem(launchAlertItem)

        let languageItem = NSMenuItem(title: L.tr("menu.language"), action: nil, keyEquivalent: "")
        let languageMenu = NSMenu()
        let selectedLanguage = UserDefaults.standard.string(forKey: languagePreferenceKey) ?? AppLanguage.system.rawValue
        for (titleKey, value) in [("menu.language.system", AppLanguage.system.rawValue), ("menu.language.english", AppLanguage.english.rawValue), ("menu.language.korean", AppLanguage.korean.rawValue)] {
            let item = NSMenuItem(title: L.tr(titleKey), action: #selector(changeLanguage(_:)), keyEquivalent: "")
            item.representedObject = value
            item.target = self
            item.state = (selectedLanguage == value) ? .on : .off
            languageMenu.addItem(item)
        }
        languageItem.submenu = languageMenu
        menu.addItem(languageItem)

        menu.addItem(NSMenuItem.separator())

        let restartItem = NSMenuItem(title: L.tr("menu.restart"), action: #selector(restartWatcherAction), keyEquivalent: "r")
        restartItem.target = self
        menu.addItem(restartItem)

        let scanItem = NSMenuItem(title: L.tr("menu.scan"), action: #selector(scanWatchPathsNow), keyEquivalent: "s")
        scanItem.target = self
        menu.addItem(scanItem)

        let openConfigItem = NSMenuItem(title: L.tr("menu.config"), action: #selector(openConfigFile), keyEquivalent: ",")
        openConfigItem.target = self
        menu.addItem(openConfigItem)

        let openLogsItem = NSMenuItem(title: L.tr("menu.logs"), action: #selector(openLogFolder), keyEquivalent: "l")
        openLogsItem.target = self
        menu.addItem(openLogsItem)

        menu.addItem(NSMenuItem.separator())

        let hideItem = NSMenuItem(title: L.tr("menu.hide"), action: #selector(hideWidget), keyEquivalent: "h")
        hideItem.target = self
        menu.addItem(hideItem)

        let quitItem = NSMenuItem(title: L.tr("menu.quit"), action: #selector(quitCompletely), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }


    private enum PreflightReason {
        case startup
        case manualScan
    }

    private struct PathPermissionResult {
        let path: String
        let status: String
    }

    private func runPreflightThenStart(showLaunchConfirmationAfterStart: Bool) {
        guard showPreflightConsentAlert(reason: .startup) else {
            #if canImport(CoreServices)
            watcher?.stop()
            watcher = nil
            #endif
            isWaitingForPreflight = true
            watcherError = L.tr("preflight.waiting")
            refreshStatusItem()
            return
        }

        restartWatcher()
        if showLaunchConfirmationAfterStart && UserDefaults.standard.bool(forKey: showLaunchConfirmationKey) {
            showLaunchConfirmation(force: false)
        }
    }

    private func checkPathPermissions(config: Config) -> [PathPermissionResult] {
        let fm = FileManager.default
        return config.expandedWatchPaths().map { path in
            var isDirectory: ObjCBool = false
            guard fm.fileExists(atPath: path, isDirectory: &isDirectory) else {
                return PathPermissionResult(path: path, status: L.tr("preflight.path.missing"))
            }
            guard isDirectory.boolValue else {
                return PathPermissionResult(path: path, status: L.tr("preflight.path.notdir"))
            }
            do {
                _ = try fm.contentsOfDirectory(atPath: path)
                return PathPermissionResult(path: path, status: L.tr("preflight.path.ok"))
            } catch {
                return PathPermissionResult(path: path, status: "\(L.tr("preflight.path.denied")): \(error.localizedDescription)")
            }
        }
    }

    private func preflightMessage(reason: PreflightReason, config: Config) -> String {
        let results = checkPathPermissions(config: config)
        let permissionLines = results.isEmpty
            ? "- \(L.tr("alert.config.watch"))"
            : results.map { "- \($0.path) — \($0.status)" }.joined(separator: "\n")
        let scanBody = reason == .manualScan ? L.tr("preflight.manual.scan.body") : L.tr("preflight.scan.body")
        let startupScan = "scanExistingOnStart: \(config.scanExistingOnStart), startupScanDepth: \(config.startupScanDepth), latencySeconds: \(config.latencySeconds)"
        return """
        \(L.tr("preflight.permission.header"))
        \(permissionLines)

        \(L.tr("preflight.privacy.header"))
        \(L.tr("preflight.privacy.body"))

        \(L.tr("preflight.scan.header"))
        \(scanBody)
        \(startupScan)
        """
    }

    private func showPreflightConsentAlert(reason: PreflightReason) -> Bool {
        createStatusItemIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        let config: Config
        do {
            config = try Config.load()
        } catch {
            showSimpleAlert(title: "JasoGuard", message: error.localizedDescription)
            return false
        }

        let alert = NSAlert()
        alert.messageText = reason == .manualScan ? L.tr("preflight.scan.title") : L.tr("preflight.start.title")
        alert.informativeText = preflightMessage(reason: reason, config: config)
        alert.alertStyle = .informational
        alert.addButton(withTitle: reason == .manualScan ? L.tr("preflight.scan.button") : L.tr("preflight.start.button"))
        alert.addButton(withTitle: L.tr("preflight.settings.button"))
        alert.addButton(withTitle: reason == .manualScan ? L.tr("preflight.cancel.button") : L.tr("preflight.quit.button"))

        let response = alert.runModal()
        if response == .alertFirstButtonReturn { return true }
        if response == .alertSecondButtonReturn {
            openPrivacySettings()
            return false
        }
        if reason == .startup { performCompleteQuit() }
        return false
    }

    private func openPrivacySettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles",
            "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
        ]
        for value in candidates {
            if let url = URL(string: value), NSWorkspace.shared.open(url) { return }
        }
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Library/PreferencePanes/Security.prefPane"))
    }

    @objc private func refreshStatus() {
        refreshStatusItem()
    }

    @objc private func restartWatcherAction() {
        runPreflightThenStart(showLaunchConfirmationAfterStart: false)
        showSimpleAlert(title: "JasoGuard", message: watcherError == nil ? L.tr("alert.restart.ok") : "\(L.tr("alert.restart.failed")): \(watcherError ?? "Unknown error")")
    }

    @objc private func scanWatchPathsNow() {
        #if canImport(CoreServices)
        guard showPreflightConsentAlert(reason: .manualScan) else { return }
        do {
            _ = try Config.load()
            if watcher == nil { startWatcherForMenuBarApp() }
            watcher?.scanWatchPaths(maxDepth: Int.max) { }
            showSimpleAlert(title: L.tr("alert.scan.title"), message: L.tr("alert.scan.message"))
        } catch {
            showSimpleAlert(title: L.tr("alert.scan.failed"), message: error.localizedDescription)
        }
        #else
        showSimpleAlert(title: L.tr("alert.scan.failed"), message: "FSEvents requires macOS.")
        #endif
    }

    @objc private func changeLanguage(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? String else { return }
        UserDefaults.standard.set(value, forKey: languagePreferenceKey)
        refreshStatusItem()
        showSimpleAlert(title: L.tr("alert.language.changed.title"), message: L.tr("alert.language.changed.message"))
    }

    @objc private func toggleLaunchConfirmation() {
        let current = UserDefaults.standard.bool(forKey: showLaunchConfirmationKey)
        UserDefaults.standard.set(!current, forKey: showLaunchConfirmationKey)
        refreshStatusItem()
    }

    @objc private func toggleLoginItem() {
        do {
            if LaunchAgent.isInstalled() {
                try LaunchAgent.uninstall(stopRunning: false)
            } else {
                let executable = Bundle.main.executablePath ?? URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL.path
                try LaunchAgent.install(executablePath: executable, startNow: false)
            }
            refreshStatusItem()
        } catch {
            showSimpleAlert(title: L.tr("alert.login.failed"), message: error.localizedDescription)
        }
    }

    @objc private func openConfigFile() {
        do {
            _ = try Config.load()
            NSWorkspace.shared.open(Config.fileURL)
        } catch {
            showSimpleAlert(title: L.tr("alert.config.failed"), message: error.localizedDescription)
        }
    }

    @objc private func openLogFolder() {
        do {
            try FileManager.default.createDirectory(at: Config.stateURL, withIntermediateDirectories: true)
            NSWorkspace.shared.open(Config.stateURL)
        } catch {
            showSimpleAlert(title: L.tr("alert.logs.failed"), message: error.localizedDescription)
        }
    }

    @objc private func hideWidget() {
        let alert = NSAlert()
        alert.messageText = L.tr("alert.hide.title")
        alert.informativeText = L.tr("alert.hide.message")
        alert.alertStyle = .informational
        alert.addButton(withTitle: L.tr("alert.hide"))
        alert.addButton(withTitle: L.tr("alert.cancel"))

        if alert.runModal() == .alertFirstButtonReturn, let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    @objc private func quitCompletely() {
        let alert = NSAlert()
        alert.messageText = L.tr("alert.quit.title")
        alert.informativeText = L.tr("alert.quit.message")
        alert.alertStyle = .warning
        alert.addButton(withTitle: L.tr("alert.quit"))
        alert.addButton(withTitle: L.tr("alert.cancel"))

        guard alert.runModal() == .alertFirstButtonReturn else { return }
        performCompleteQuit()
    }

    private func performCompleteQuit() {
        do { try LaunchAgent.uninstall(stopRunning: true) } catch { log("WARN", "LaunchAgent uninstall failed during quit: \(error.localizedDescription)") }
        #if canImport(CoreServices)
        watcher?.stop()
        watcher = nil
        #endif
        NSApp.terminate(nil)
    }

    private func showLaunchConfirmation(force: Bool) {
        if launchAlertShown && !force { return }
        launchAlertShown = true

        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = L.tr("alert.launch.title")
        let loginState = LaunchAgent.isInstalled() ? L.tr("alert.login.on") : L.tr("alert.login.off")
        let detail: String
        if let watcherError {
            detail = "\(L.tr("menu.status")): \(L.tr("status.error"))\n\(L.tr("menu.error")): \(watcherError)\n\(L.tr("menu.login")): \(loginState)"
            alert.alertStyle = .warning
        } else {
            let paths = (try? Config.load().expandedWatchPaths().joined(separator: "\n- ")) ?? L.tr("alert.config.watch")
            detail = "\(L.tr("menu.status")): \(L.tr("status.running"))\n\(L.tr("alert.watch.paths")):\n- \(paths)\n\(L.tr("menu.login")): \(loginState)"
            alert.alertStyle = .informational
        }
        alert.informativeText = detail
        alert.addButton(withTitle: L.tr("alert.ok"))
        alert.addButton(withTitle: L.tr("alert.hide"))
        alert.addButton(withTitle: L.tr("alert.quit"))

        let response = alert.runModal()
        if response == .alertSecondButtonReturn {
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
        } else if response == .alertThirdButtonReturn {
            performCompleteQuit()
        }
    }

    private func showSimpleAlert(title: String, message: String) {
        createStatusItemIfNeeded()
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: L.tr("alert.ok"))
        alert.runModal()
    }
}

private var appDelegateHolder: JasoGuardAppDelegate?

private func runMenuBarApp() {
    let app = NSApplication.shared
    let delegate = JasoGuardAppDelegate()
    appDelegateHolder = delegate
    app.delegate = delegate
    app.setActivationPolicy(.accessory)
    app.run()
}
#endif

private func printHelp() {
    stdout("""
    JasoGuard - macOS NFD to NFC filename normalizer

    Commands:
      init                         Create default config
      status                       Print config and LaunchAgent path
      watch                        Run foreground watcher only
      no arguments                 Run menu bar widget and background watcher
      scan                         Convert all configured watch paths now
      add <path>                   Add a recursive watch path
      ignore <path>                Add an ignore path
      convert <path> [--recursive] [--dry-run]
                                   Convert an existing file or directory
      install-agent [--app-path /Applications/JasoGuard.app]
                                   Install per-user LaunchAgent that opens the app at login
      uninstall-agent              Stop and remove LaunchAgent
      help                         Show this help

    Config: ~/.config/jasoguard/config.json
    Logs:   ~/.local/state/jasoguard/
    """)
}

private func addPath(_ value: String, ignore: Bool) throws {
    var config = try Config.load()
    let path = canonicalPath(value)
    if ignore {
        if !config.ignore.contains(path) { config.ignore.append(path) }
    } else {
        let item = WatchPath(path: path, recursive: true)
        if !config.watch.contains(item) { config.watch.append(item) }
    }
    try config.save()
    stdout(ignore ? "ignored: \(path)" : "watching: \(path)")
}

private func status() throws {
    let config = try Config.load()
    stdout("config: \(Config.fileURL.path)")
    stdout("agent:  \(LaunchAgent.plistURL.path)")
    stdout("login:  \(LaunchAgent.isInstalled() ? "enabled" : "disabled")")
    stdout("latency: \(config.latencySeconds)s")
    stdout("directory event depth: \(config.directoryEventDepth)")
    stdout("scan existing on start: \(config.scanExistingOnStart)")
    stdout("startup scan depth: \(config.startupScanDepth)")
    stdout("watch paths:")
    for item in config.watch { stdout("  - \(canonicalPath(item.path)) recursive=\(item.recursive)") }
    stdout("ignore paths:")
    for path in config.ignore { stdout("  - \(canonicalPath(path))") }
}

@main
private struct Main {
    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        guard let command = args.first else {
            #if canImport(AppKit)
            runMenuBarApp()
            #else
            printHelp()
            #endif
            return
        }

        do {
            switch command {
            case "help", "--help", "-h":
                printHelp()
            case "init":
                let config = Config.defaultConfig()
                try config.save()
                try FileManager.default.createDirectory(at: Config.stateURL, withIntermediateDirectories: true)
                stdout("created: \(Config.fileURL.path)")
            case "status":
                try status()
            case "add":
                guard args.count >= 2 else { throw NSError(domain: appName, code: 20, userInfo: [NSLocalizedDescriptionKey: "missing path"]) }
                try addPath(args[1], ignore: false)
            case "ignore":
                guard args.count >= 2 else { throw NSError(domain: appName, code: 21, userInfo: [NSLocalizedDescriptionKey: "missing path"]) }
                try addPath(args[1], ignore: true)
            case "convert":
                guard args.count >= 2 else { throw NSError(domain: appName, code: 22, userInfo: [NSLocalizedDescriptionKey: "missing path"]) }
                let recursive = args.contains("--recursive")
                let dryRun = args.contains("--dry-run")
                let config = try Config.load()
                let normalizer = NFCNormalizer(dryRun: dryRun, skipHidden: config.skipHiddenFiles)
                if recursive { normalizer.convertRecursively(args[1]) } else { normalizer.normalizePath(args[1]) }
                stdout(normalizer.summary())
            case "scan":
                let config = try Config.load()
                let normalizer = NFCNormalizer(dryRun: false, skipHidden: config.skipHiddenFiles)
                for path in config.expandedWatchPaths() where !config.isIgnored(path) {
                    normalizer.convertRecursively(path)
                }
                stdout(normalizer.summary())
            case "watch":
                let config = try Config.load()
                log("INFO", "starting watcher")
                #if canImport(CoreServices)
                let watcher = FileEventWatcher(config: config)
                try watcher.start(blocking: true)
                #else
                throw NSError(domain: appName, code: 30, userInfo: [NSLocalizedDescriptionKey: "FSEvents requires macOS"])
                #endif
            case "install-agent":
                let exe = executablePathFromArgs(args)
                try Config.load().save()
                try LaunchAgent.install(executablePath: exe)
                stdout("installed LaunchAgent: \(LaunchAgent.plistURL.path)")
            case "uninstall-agent":
                try LaunchAgent.uninstall()
                stdout("removed LaunchAgent: \(LaunchAgent.plistURL.path)")
            default:
                throw NSError(domain: appName, code: 1, userInfo: [NSLocalizedDescriptionKey: "unknown command: \(command)"])
            }
        } catch {
            stderr("error: \(error.localizedDescription)")
            exit(1)
        }
    }
}
