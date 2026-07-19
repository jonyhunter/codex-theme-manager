import AppKit
import CryptoKit
import Foundation
import SwiftUI

private let updatePublicKey = "5_BSHZg9M_SVnRiUlMqF24Am-kprwLXYgDljQcFNOKc"
private let defaultUpdateFeed =
  "https://raw.githubusercontent.com/houyuhang915-sudo/Codex-Skin-Manager/main/updates/stable.json"

struct UpdateAsset: Decodable {
  let url: String
  let sha256: String
  let size: Int64
}

struct ThemeCatalogReference: Decodable {
  let url: String
  let sha256: String
}

struct ManagerUpdateFeed: Decodable {
  let schemaVersion: Int
  let channel: String
  let version: String
  let minimumVersion: String
  let publishedAt: String
  let releaseNotesUrl: String
  let platforms: [String: UpdateAsset]
  let themeCatalog: ThemeCatalogReference
}

struct OnlineTheme: Decodable, Identifiable {
  let id: String
  let name: String
  let version: Int
  let minimumAppVersion: String
  let url: String
  let sha256: String
  let size: Int64
  let description: String?
}

struct OnlineThemeCatalog: Decodable {
  let schemaVersion: Int
  let catalogVersion: Int
  let publishedAt: String
  let themes: [OnlineTheme]
}

enum UpdatePhase: Equatable {
  case idle
  case checking
  case updateAvailable
  case downloading
  case installerReady
  case current
  case failed
}

enum ManagerUpdateError: LocalizedError {
  case invalid(String)

  var errorDescription: String? {
    switch self {
    case .invalid(let message): return message
    }
  }
}

final class UpdateService: ObservableObject {
  static var currentVersion: String {
    Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
  }

  @Published var phase: UpdatePhase = .idle
  @Published var message = "尚未检查更新"
  @Published var availableVersion: String?
  @Published var releaseNotesURL: URL?
  @Published var onlineThemes: [OnlineTheme] = []
  @Published var installingThemeIDs: Set<String> = []
  @Published var isPresented = false
  @Published var downloadedInstallerURL: URL?

  var onThemeInstalled: (() -> Void)?

  private let stateRoot: URL
  private let themesRoot: URL
  private let defaults: UserDefaults
  private var availableAsset: UpdateAsset?
  private let lastCheckKey = "CodexSkinManager.lastUpdateCheck"

  init(stateRoot: URL, themesRoot: URL, defaults: UserDefaults = .standard) {
    self.stateRoot = stateRoot
    self.themesRoot = themesRoot
    self.defaults = defaults
  }

  var updateButtonTitle: String {
    switch phase {
    case .checking: return "正在检查…"
    case .downloading: return "正在下载…"
    case .installerReady: return "打开安装器"
    case .updateAvailable: return "更新到 \(availableVersion ?? "新版本")"
    default: return "检查更新"
    }
  }

  var hasUpdates: Bool {
    phase == .updateAvailable || phase == .installerReady || !onlineThemes.isEmpty
  }

  func scheduleAutomaticCheck() {
    let lastCheck = defaults.object(forKey: lastCheckKey) as? Date ?? .distantPast
    guard Date().timeIntervalSince(lastCheck) >= 24 * 60 * 60 else { return }
    DispatchQueue.main.asyncAfter(deadline: .now() + 6) { [weak self] in
      self?.checkForUpdates(manual: false)
    }
  }

  func present() {
    isPresented = true
    if phase == .idle || phase == .failed { checkForUpdates(manual: true) }
  }

  func checkForUpdates(manual: Bool) {
    guard phase != .checking && phase != .downloading else { return }
    phase = .checking
    message = "正在验证更新清单…"
    if manual { isPresented = true }

    Task { [weak self] in
      guard let self else { return }
      do {
        let feedURL = try self.feedURL()
        let (feedData, feed) = try await Self.fetchSignedJSON(
          at: feedURL,
          as: ManagerUpdateFeed.self,
          maximumBytes: 2 * 1024 * 1024
        )
        _ = feedData
        try Self.validate(feed: feed)
        guard let asset = feed.platforms["macos"] else {
          throw ManagerUpdateError.invalid("更新清单缺少 macOS 安装包")
        }
        try Self.validate(asset: asset)

        let (catalogData, catalog) = try await Self.fetchSignedJSON(
          at: try Self.secureURL(feed.themeCatalog.url, label: "在线主题目录"),
          as: OnlineThemeCatalog.self,
          maximumBytes: 4 * 1024 * 1024
        )
        guard Self.sha256(catalogData) == feed.themeCatalog.sha256 else {
          throw ManagerUpdateError.invalid("在线主题目录摘要校验失败")
        }
        try Self.validate(catalog: catalog)
        let installedVersions = self.readInstalledThemeVersions()
        let compatibleThemes = catalog.themes.filter { theme in
          guard (try? Self.compareVersions(Self.currentVersion, theme.minimumAppVersion)) != -1 else {
            return false
          }
          return (installedVersions[theme.id] ?? 0) < theme.version
        }
        let updateAvailable = try Self.compareVersions(feed.version, Self.currentVersion) > 0

        await MainActor.run {
          self.defaults.set(Date(), forKey: self.lastCheckKey)
          self.availableVersion = updateAvailable ? feed.version : nil
          self.availableAsset = updateAvailable ? asset : nil
          self.releaseNotesURL = URL(string: feed.releaseNotesUrl)
          self.onlineThemes = compatibleThemes
          if updateAvailable {
            self.phase = .updateAvailable
            self.message = "发现 Codex 皮肤管理器 \(feed.version)"
          } else {
            self.phase = .current
            self.message = compatibleThemes.isEmpty
              ? "当前已是最新版本"
              : "发现 \(compatibleThemes.count) 套在线主题"
          }
        }
      } catch {
        await MainActor.run {
          self.phase = .failed
          self.message = "检查更新失败：\(error.localizedDescription)"
        }
      }
    }
  }

  func downloadOrOpenInstaller() {
    if let downloadedInstallerURL {
      launchInstaller(from: downloadedInstallerURL)
      return
    }
    guard let asset = availableAsset, let version = availableVersion else {
      checkForUpdates(manual: true)
      return
    }
    phase = .downloading
    message = "正在下载 \(version)…"

    Task { [weak self] in
      guard let self else { return }
      do {
        let url = try Self.secureURL(asset.url, label: "macOS 更新包")
        let (temporaryURL, response) = try await URLSession.shared.download(from: url)
        try Self.validateHTTP(response)
        let fileSize = try temporaryURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
        guard Int64(fileSize) == asset.size else {
          throw ManagerUpdateError.invalid("安装包大小与更新清单不一致")
        }
        guard try Self.sha256(fileAt: temporaryURL) == asset.sha256 else {
          throw ManagerUpdateError.invalid("安装包 SHA-256 校验失败")
        }
        let updateDirectory = self.stateRoot
          .appendingPathComponent("updates", isDirectory: true)
          .appendingPathComponent(version, isDirectory: true)
        try FileManager.default.createDirectory(at: updateDirectory, withIntermediateDirectories: true)
        let destination = updateDirectory.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: destination)
        try FileManager.default.moveItem(at: temporaryURL, to: destination)
        await MainActor.run {
          self.downloadedInstallerURL = destination
          self.phase = .installerReady
          self.message = "安装包已校验，正在启动一键更新…"
          self.launchInstaller(from: destination)
        }
      } catch {
        await MainActor.run {
          self.phase = .failed
          self.message = "更新下载失败：\(error.localizedDescription)"
        }
      }
    }
  }

  private func launchInstaller(from diskImage: URL) {
    message = "正在挂载已验证的安装包…"
    Task { [weak self] in
      guard let self else { return }
      do {
        let installer = try Self.mountInstaller(from: diskImage)
        try await Self.openInstallerApplication(installer)
        await MainActor.run {
          self.message = "一键更新已启动，管理器稍后会自动重开"
        }
      } catch {
        await MainActor.run {
          self.phase = .installerReady
          self.message = "启动安装器失败：\(error.localizedDescription)"
        }
      }
    }
  }

  func installOnlineTheme(_ theme: OnlineTheme) {
    guard !installingThemeIDs.contains(theme.id) else { return }
    installingThemeIDs.insert(theme.id)
    message = "正在安装“\(theme.name)”…"

    Task { [weak self] in
      guard let self else { return }
      let temporaryRoot = FileManager.default.temporaryDirectory
        .appendingPathComponent("codex-skin-online-theme-\(UUID().uuidString)", isDirectory: true)
      do {
        let packageURL = try Self.secureURL(theme.url, label: "在线主题包")
        let (downloadURL, response) = try await URLSession.shared.download(from: packageURL)
        try Self.validateHTTP(response)
        let fileSize = try downloadURL.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? -1
        guard Int64(fileSize) == theme.size else {
          throw ManagerUpdateError.invalid("主题包大小与目录不一致")
        }
        guard try Self.sha256(fileAt: downloadURL) == theme.sha256 else {
          throw ManagerUpdateError.invalid("主题包 SHA-256 校验失败")
        }
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
        try Self.validateZipEntries(downloadURL)
        try Self.run("/usr/bin/ditto", arguments: ["-x", "-k", downloadURL.path, temporaryRoot.path])
        let themeDirectory = try Self.findThemeDirectory(in: temporaryRoot)
        let package = try ThemePackageService.validate(directory: themeDirectory)
        guard package.manifest.id == theme.id else {
          throw ManagerUpdateError.invalid("主题包 ID 与在线目录不一致")
        }
        let destination = self.themesRoot.appendingPathComponent(theme.id, isDirectory: true)
        let replacing = FileManager.default.fileExists(atPath: destination.path)
        try ThemePackageService.install(package: package, into: self.themesRoot, replacing: replacing)
        var versions = self.readInstalledThemeVersions()
        versions[theme.id] = theme.version
        try self.writeInstalledThemeVersions(versions)
        try? FileManager.default.removeItem(at: temporaryRoot)
        await MainActor.run {
          self.installingThemeIDs.remove(theme.id)
          self.onlineThemes.removeAll { $0.id == theme.id }
          self.message = "已安装“\(theme.name)”"
          self.onThemeInstalled?()
        }
      } catch {
        try? FileManager.default.removeItem(at: temporaryRoot)
        await MainActor.run {
          self.installingThemeIDs.remove(theme.id)
          self.message = "主题安装失败：\(error.localizedDescription)"
        }
      }
    }
  }

  private func feedURL() throws -> URL {
    let configured = ProcessInfo.processInfo.environment["CODEX_SKIN_UPDATE_FEED_URL"]
    return try Self.secureURL(configured ?? defaultUpdateFeed, label: "更新清单")
  }

  private var installedThemeVersionsURL: URL {
    stateRoot.appendingPathComponent("official-theme-versions.json")
  }

  private func readInstalledThemeVersions() -> [String: Int] {
    guard let data = try? Data(contentsOf: installedThemeVersionsURL),
          let versions = try? JSONDecoder().decode([String: Int].self, from: data)
    else { return [:] }
    return versions
  }

  private func writeInstalledThemeVersions(_ versions: [String: Int]) throws {
    try FileManager.default.createDirectory(at: stateRoot, withIntermediateDirectories: true)
    let data = try JSONEncoder().encode(versions)
    let temporary = stateRoot.appendingPathComponent(".official-theme-versions.\(UUID().uuidString)")
    try data.write(to: temporary, options: .atomic)
    try? FileManager.default.removeItem(at: installedThemeVersionsURL)
    try FileManager.default.moveItem(at: temporary, to: installedThemeVersionsURL)
  }

  private static func fetchSignedJSON<Value: Decodable>(
    at url: URL,
    as type: Value.Type,
    maximumBytes: Int
  ) async throws -> (Data, Value) {
    let signatureURL = try secureURL("\(url.absoluteString).sig", label: "更新签名")
    async let dataRequest = URLSession.shared.data(from: url)
    async let signatureRequest = URLSession.shared.data(from: signatureURL)
    let (dataResult, signatureResult) = try await (dataRequest, signatureRequest)
    try validateHTTP(dataResult.1)
    try validateHTTP(signatureResult.1)
    guard !dataResult.0.isEmpty, dataResult.0.count <= maximumBytes else {
      throw ManagerUpdateError.invalid("更新清单大小无效")
    }
    guard !signatureResult.0.isEmpty, signatureResult.0.count <= 4096 else {
      throw ManagerUpdateError.invalid("更新签名大小无效")
    }
    let signatureText = String(data: signatureResult.0, encoding: .utf8)?
      .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard let signature = Data(base64Encoded: signatureText), signature.count == 64 else {
      throw ManagerUpdateError.invalid("更新签名格式无效")
    }
    let keyData = try decodeBase64URL(updatePublicKey)
    let publicKey = try Curve25519.Signing.PublicKey(rawRepresentation: keyData)
    guard publicKey.isValidSignature(signature, for: dataResult.0) else {
      throw ManagerUpdateError.invalid("更新清单签名校验失败")
    }
    return (dataResult.0, try JSONDecoder().decode(type, from: dataResult.0))
  }

  private static func validate(feed: ManagerUpdateFeed) throws {
    guard feed.schemaVersion == 1, feed.channel == "stable" else {
      throw ManagerUpdateError.invalid("更新清单版本不受支持")
    }
    _ = try compareVersions(feed.version, feed.minimumVersion)
    guard ISO8601DateFormatter().date(from: feed.publishedAt) != nil else {
      throw ManagerUpdateError.invalid("更新发布日期无效")
    }
    _ = try secureURL(feed.releaseNotesUrl, label: "版本说明")
    _ = try secureURL(feed.themeCatalog.url, label: "在线主题目录")
    try validateSHA256(feed.themeCatalog.sha256)
  }

  private static func validate(catalog: OnlineThemeCatalog) throws {
    guard catalog.schemaVersion == 1, catalog.catalogVersion > 0,
          ISO8601DateFormatter().date(from: catalog.publishedAt) != nil
    else { throw ManagerUpdateError.invalid("在线主题目录格式不受支持") }
    var ids = Set<String>()
    for theme in catalog.themes {
      guard theme.id.range(of: "^[a-z0-9]+(?:-[a-z0-9]+)*$", options: .regularExpression) != nil,
            ids.insert(theme.id).inserted,
            theme.version > 0
      else { throw ManagerUpdateError.invalid("在线主题 ID 或版本无效") }
      _ = try compareVersions(theme.minimumAppVersion, theme.minimumAppVersion)
      try validate(asset: UpdateAsset(url: theme.url, sha256: theme.sha256, size: theme.size))
    }
  }

  private static func validate(asset: UpdateAsset) throws {
    _ = try secureURL(asset.url, label: "更新文件")
    try validateSHA256(asset.sha256)
    guard asset.size > 0, asset.size <= 512 * 1024 * 1024 else {
      throw ManagerUpdateError.invalid("更新文件大小无效")
    }
  }

  private static func validateSHA256(_ value: String) throws {
    guard value.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil else {
      throw ManagerUpdateError.invalid("SHA-256 格式无效")
    }
  }

  private static func secureURL(_ value: String, label: String) throws -> URL {
    guard let url = URL(string: value), url.scheme == "https", url.host != nil else {
      throw ManagerUpdateError.invalid("\(label)必须使用 HTTPS")
    }
    return url
  }

  private static func validateHTTP(_ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse,
          (200..<300).contains(http.statusCode),
          http.url?.scheme == "https"
    else {
      throw ManagerUpdateError.invalid("更新服务器返回异常状态")
    }
  }

  static func compareVersions(_ left: String, _ right: String) throws -> Int {
    func parse(_ value: String) throws -> [Int] {
      guard value.range(of: "^(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)\\.(0|[1-9][0-9]*)$", options: .regularExpression) != nil else {
        throw ManagerUpdateError.invalid("版本号格式无效：\(value)")
      }
      return value.split(separator: ".").compactMap { Int($0) }
    }
    let lhs = try parse(left)
    let rhs = try parse(right)
    for index in 0..<3 where lhs[index] != rhs[index] {
      return lhs[index] < rhs[index] ? -1 : 1
    }
    return 0
  }

  private static func decodeBase64URL(_ value: String) throws -> Data {
    var normalized = value.replacingOccurrences(of: "-", with: "+")
      .replacingOccurrences(of: "_", with: "/")
    while normalized.count % 4 != 0 { normalized.append("=") }
    guard let data = Data(base64Encoded: normalized) else {
      throw ManagerUpdateError.invalid("更新公钥格式无效")
    }
    return data
  }

  private static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private static func sha256(fileAt url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let data = try handle.read(upToCount: 1024 * 1024), !data.isEmpty {
      hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private static func validateZipEntries(_ url: URL) throws {
    let process = Process()
    let output = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/bsdtar")
    process.arguments = ["-tf", url.path]
    process.standardOutput = output
    process.standardError = Pipe()
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      throw ManagerUpdateError.invalid("主题 ZIP 目录读取失败")
    }
    let listing = String(data: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    for entry in listing.split(separator: "\n").map(String.init) {
      let components = entry.replacingOccurrences(of: "\\", with: "/").split(separator: "/")
      if entry.hasPrefix("/") || components.contains("..") {
        throw ManagerUpdateError.invalid("主题 ZIP 包含越界路径")
      }
    }
  }

  private static func mountInstaller(from diskImage: URL) throws -> URL {
    let process = Process()
    let output = Pipe()
    let errorPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
    process.arguments = ["attach", "-readonly", "-nobrowse", "-plist", diskImage.path]
    process.standardOutput = output
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      let detail = String(
        data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
      )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
      throw ManagerUpdateError.invalid(detail.isEmpty ? "DMG 挂载失败" : detail)
    }
    let data = output.fileHandleForReading.readDataToEndOfFile()
    guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil)
      as? [String: Any],
      let entities = plist["system-entities"] as? [[String: Any]]
    else { throw ManagerUpdateError.invalid("DMG 挂载结果格式无效") }
    let mountPoints = entities.compactMap { $0["mount-point"] as? String }
    for mountPoint in mountPoints {
      let installer = URL(fileURLWithPath: mountPoint, isDirectory: true)
        .appendingPathComponent("安装 Codex 皮肤管理器.app", isDirectory: true)
      if FileManager.default.fileExists(atPath: installer.path) { return installer }
    }
    throw ManagerUpdateError.invalid("DMG 中缺少内置安装器")
  }

  @MainActor
  private static func openInstallerApplication(_ installer: URL) async throws {
    let configuration = NSWorkspace.OpenConfiguration()
    configuration.arguments = ["--automatic-update"]
    configuration.activates = true
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
      NSWorkspace.shared.openApplication(at: installer, configuration: configuration) { _, error in
        if let error {
          continuation.resume(throwing: error)
        } else {
          continuation.resume()
        }
      }
    }
  }

  private static func findThemeDirectory(in root: URL) throws -> URL {
    if FileManager.default.fileExists(atPath: root.appendingPathComponent("theme.json").path) {
      return root
    }
    let directories = try FileManager.default.contentsOfDirectory(
      at: root,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ).filter { url in
      (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true &&
        FileManager.default.fileExists(atPath: url.appendingPathComponent("theme.json").path)
    }
    guard directories.count == 1, let directory = directories.first else {
      throw ManagerUpdateError.invalid("主题 ZIP 必须只包含一套标准主题")
    }
    return directory
  }

  private static func run(_ executable: String, arguments: [String]) throws {
    let process = Process()
    let errorPipe = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = Pipe()
    process.standardError = errorPipe
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      let detail = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
      throw ManagerUpdateError.invalid(detail.isEmpty ? "主题包解压失败" : detail)
    }
  }
}

struct UpdateCenterView: View {
  @ObservedObject var updater: UpdateService
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack {
        VStack(alignment: .leading, spacing: 4) {
          Text("软件与主题更新")
            .font(.system(size: 20, weight: .bold))
          Text("当前版本 \(UpdateService.currentVersion)")
            .font(.system(size: 12))
            .foregroundStyle(StudioPalette.muted)
        }
        Spacer()
        Button(action: { dismiss() }) { Image(systemName: "xmark") }
          .buttonStyle(.plain)
          .help("关闭")
      }
      .padding(24)

      Divider()

      ScrollView {
        VStack(alignment: .leading, spacing: 20) {
          HStack(spacing: 14) {
            Image(systemName: updater.hasUpdates ? "arrow.down.circle.fill" : "checkmark.circle.fill")
              .font(.system(size: 28))
              .foregroundStyle(updater.hasUpdates ? StudioPalette.accent : StudioPalette.signal)
            VStack(alignment: .leading, spacing: 4) {
              Text(updater.availableVersion.map { "Codex 皮肤管理器 \($0)" } ?? "版本状态")
                .font(.system(size: 15, weight: .semibold))
              Text(updater.message)
                .font(.system(size: 12))
                .foregroundStyle(StudioPalette.muted)
            }
            Spacer()
          }

          if updater.phase == .checking || updater.phase == .downloading {
            ProgressView().controlSize(.small)
          }

          HStack(spacing: 10) {
            if updater.phase == .updateAvailable || updater.phase == .installerReady {
              Button(updater.updateButtonTitle, action: updater.downloadOrOpenInstaller)
                .buttonStyle(.borderedProminent)
                .tint(StudioPalette.accent)
            }
            Button("重新检查", action: { updater.checkForUpdates(manual: true) })
              .disabled(updater.phase == .checking || updater.phase == .downloading)
            if let releaseNotesURL = updater.releaseNotesURL {
              Link("查看版本说明", destination: releaseNotesURL)
            }
          }

          Divider()

          HStack {
            Text("在线主题")
              .font(.system(size: 15, weight: .semibold))
            Spacer()
            Text(updater.onlineThemes.isEmpty ? "暂无待安装主题" : "\(updater.onlineThemes.count) 套可用")
              .font(.system(size: 11))
              .foregroundStyle(StudioPalette.muted)
          }

          ForEach(updater.onlineThemes) { theme in
            HStack(spacing: 14) {
              Image(systemName: "photo.on.rectangle.angled")
                .foregroundStyle(StudioPalette.accent)
                .frame(width: 30)
              VStack(alignment: .leading, spacing: 3) {
                Text(theme.name).font(.system(size: 13, weight: .semibold))
                Text(theme.description ?? "官方在线主题 · 版本 \(theme.version)")
                  .font(.system(size: 11))
                  .foregroundStyle(StudioPalette.muted)
              }
              Spacer()
              Button(updater.installingThemeIDs.contains(theme.id) ? "安装中…" : "安装") {
                updater.installOnlineTheme(theme)
              }
              .disabled(updater.installingThemeIDs.contains(theme.id))
            }
            .padding(.vertical, 8)
          }

          Text("更新清单和安装包会先完成签名、版本、大小与 SHA-256 校验。用户主题和当前选择会保留。")
            .font(.system(size: 11))
            .foregroundStyle(StudioPalette.muted)
        }
        .padding(24)
      }
    }
    .frame(width: 620, height: 520)
    .background(StudioPalette.canvas)
  }
}

struct UpdateToolbarButton: View {
  @ObservedObject var updater: UpdateService

  var body: some View {
    Button(action: updater.present) {
      Image(systemName: updater.hasUpdates ? "arrow.down.circle.fill" : "arrow.down.circle")
    }
    .help(updater.hasUpdates ? "有可用更新" : "检查更新")
    .sheet(isPresented: $updater.isPresented) {
      UpdateCenterView(updater: updater)
    }
  }
}
