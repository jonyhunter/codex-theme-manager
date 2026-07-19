import AppKit
import Darwin
import SwiftUI

struct RuntimeState: Decodable {
  let session: String?
  let port: Int?
  let injectorPid: Int?
}

struct ThemeItem: Identifiable {
  let manifest: ThemeManifest
  let directory: URL

  var id: String { manifest.id }
  var backgroundURL: URL { directory.appendingPathComponent(manifest.image) }
  var previewURL: URL {
    guard let preview = manifest.preview, !preview.isEmpty else { return backgroundURL }
    return directory.appendingPathComponent(preview)
  }
  var isOriginal: Bool { manifest.mode == "original" }
  var isBuiltIn: Bool { BuiltinThemeCatalog.ids.contains(id) }
  var accent: Color { Color(hex: manifest.colors?["accent"] ?? "#24785b") }
  var appearanceLabel: String {
    if isOriginal { return "原版" }
    switch manifest.appearance {
    case "light": return "浅色"
    case "dark": return "深色"
    default: return "跟随系统"
    }
  }
}

final class ThemeImageCache {
  static let shared = ThemeImageCache()
  private let images = NSCache<NSURL, NSImage>()

  private init() {
    images.countLimit = 24
  }

  func image(at url: URL) -> NSImage? {
    let key = url as NSURL
    if let cached = images.object(forKey: key) { return cached }
    guard let image = NSImage(contentsOf: url) else { return nil }
    images.setObject(image, forKey: key)
    return image
  }
}

enum StudioSection: String, CaseIterable, Identifiable {
  case library = "皮肤库"
  case installed = "已安装"
  case integration = "接入标准"
  case runtime = "运行状态"

  var id: String { rawValue }
  var icon: String {
    switch self {
    case .library: return "rectangle.stack"
    case .installed: return "paintpalette"
    case .integration: return "book.closed"
    case .runtime: return "bolt"
    }
  }
}

enum StudioPalette {
  static let canvas = Color(red: 0.955, green: 0.962, blue: 0.960)
  static let sidebar = Color(red: 0.075, green: 0.086, blue: 0.092)
  static let sidebarSelected = Color.white.opacity(0.09)
  static let surface = Color.white
  static let line = Color(red: 0.84, green: 0.86, blue: 0.855)
  static let ink = Color(red: 0.075, green: 0.086, blue: 0.092)
  static let muted = Color(red: 0.38, green: 0.42, blue: 0.405)
  static let accent = Color(red: 0.86, green: 0.31, blue: 0.25)
  static let accentSoft = Color(red: 1.0, green: 0.93, blue: 0.91)
  static let signal = Color(red: 0.07, green: 0.48, blue: 0.43)
  static let signalSoft = Color(red: 0.89, green: 0.96, blue: 0.945)
  static let gold = Color(red: 0.73, green: 0.50, blue: 0.16)
  static let sidebarText = Color(red: 0.95, green: 0.96, blue: 0.955)
}

final class ThemeStore: ObservableObject {
  @Published var themes: [ThemeItem] = []
  @Published var activeID: String?
  @Published var runtimeState: RuntimeState?
  @Published private(set) var runtimeConnected = false
  @Published var status = "正在读取皮肤库…"
  @Published var applyingThemeID: String?
  @Published var isCreateThemePresented = false
  @Published var isThemeCreatorSkillInstalled = false

  let home = FileManager.default.homeDirectoryForCurrentUser
  lazy var engineRoot = home.appendingPathComponent(".codex/codex-dream-skin-studio")
  lazy var stateRoot = home.appendingPathComponent("Library/Application Support/CodexDreamSkinStudio")
  lazy var themesRoot = stateRoot.appendingPathComponent("themes")
  lazy var activeThemeURL = stateRoot.appendingPathComponent("theme/theme.json")
  lazy var runtimeStateURL = stateRoot.appendingPathComponent("state.json")
  lazy var updateService = UpdateService(stateRoot: stateRoot, themesRoot: themesRoot)
  lazy var codexHome: URL = {
    if let configured = ProcessInfo.processInfo.environment["CODEX_HOME"], !configured.isEmpty {
      return URL(fileURLWithPath: configured, isDirectory: true)
    }
    return home.appendingPathComponent(".codex", isDirectory: true)
  }()
  lazy var themeCreatorSkillRoot = codexHome
    .appendingPathComponent("skills/codex-skin-theme-creator", isDirectory: true)
  private var themeLibraryFingerprint = ""
  private var liveStateFingerprint = ""
  private var themeMonitor: Timer?
  private let themeCreatorSkillFiles = [
    "SKILL.md",
    "agents/openai.yaml",
    "scripts/create-theme.mjs",
    "scripts/create-theme-windows.ps1",
    "references/theme-format.md",
  ]

  var activeTheme: ThemeItem? { themes.first { $0.id == activeID } }
  var installedThemes: [ThemeItem] { themes.filter { !$0.isOriginal } }
  var isApplying: Bool { applyingThemeID != nil }
  var isRuntimeActive: Bool { runtimeConnected }
  var runtimeSessionLabel: String {
    if isRuntimeActive { return "运行中" }
    if runtimeState?.session == "paused" { return "已暂停" }
    if runtimeState != nil { return "未连接" }
    return "未启动"
  }

  init() {
    try? FileManager.default.createDirectory(at: themesRoot, withIntermediateDirectories: true)
    updateService.onThemeInstalled = { [weak self] in self?.reload() }
    reload()
    installThemeCreatorSkill(silent: true)
    updateService.scheduleAutomaticCheck()
    let monitor = Timer(timeInterval: 1.5, repeats: true) { [weak self] _ in
      self?.refreshMonitoredStateIfNeeded()
    }
    themeMonitor = monitor
    RunLoop.main.add(monitor, forMode: .common)
  }

  deinit {
    themeMonitor?.invalidate()
  }

  func reload() {
    let decoder = JSONDecoder()
    let directories = (try? FileManager.default.contentsOfDirectory(
      at: themesRoot,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )) ?? []

    themes = directories.compactMap { directory in
      let manifestURL = directory.appendingPathComponent("theme.json")
      guard let data = try? Data(contentsOf: manifestURL),
            let manifest = try? decoder.decode(ThemeManifest.self, from: data),
            FileManager.default.fileExists(atPath: directory.appendingPathComponent(manifest.image).path)
      else { return nil }
      return ThemeItem(manifest: manifest, directory: directory)
    }.sorted { lhs, rhs in
      let left = BuiltinThemeCatalog.orderedIDs.firstIndex(of: lhs.id) ?? Int.max
      let right = BuiltinThemeCatalog.orderedIDs.firstIndex(of: rhs.id) ?? Int.max
      return left == right ? lhs.manifest.name < rhs.manifest.name : left < right
    }

    loadLiveState(using: decoder)
    isThemeCreatorSkillInstalled = themeCreatorSkillIsCurrent()
    themeLibraryFingerprint = currentThemeLibraryFingerprint()
    liveStateFingerprint = currentLiveStateFingerprint()
    status = themes.isEmpty ? "没有找到皮肤包" : "已载入 \(themes.count) 套皮肤"
  }

  func apply(_ theme: ThemeItem) {
    guard applyingThemeID == nil else {
      status = "正在切换主题，请稍候…"
      return
    }
    let script = engineRoot.appendingPathComponent("scripts/switch-theme-macos.sh")
    guard FileManager.default.isExecutableFile(atPath: script.path) else {
      status = "皮肤引擎未安装"
      return
    }

    applyingThemeID = theme.id
    status = theme.isOriginal ? "正在恢复 Codex 原版…" : "正在应用“\(theme.manifest.name)”…"
    let themeID = theme.id
    let themeName = theme.manifest.name

    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      let process = Process()
      let output = Pipe()
      process.executableURL = URL(fileURLWithPath: "/bin/bash")
      process.arguments = [script.path, "--id", themeID]
      process.standardOutput = output
      process.standardError = output
      do {
        try process.run()
        process.waitUntilExit()
        let messageData = output.fileHandleForReading.readDataToEndOfFile()
        let detail = String(data: messageData, encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        DispatchQueue.main.async {
          guard let self else { return }
          self.applyingThemeID = nil
          if process.terminationStatus == 0 {
            self.activeID = themeID
            self.reload()
            self.status = theme.isOriginal ? "Codex 原版已恢复" : "已应用“\(themeName)”"
          } else {
            self.status = detail.isEmpty ? "皮肤应用失败" : detail
          }
        }
      } catch {
        DispatchQueue.main.async {
          self?.applyingThemeID = nil
          self?.status = "启动皮肤引擎失败：\(error.localizedDescription)"
        }
      }
    }
  }

  func restoreOriginal() {
    guard let original = themes.first(where: { $0.id == "codex-default" }) else { return }
    apply(original)
  }

  func importTheme() {
    let panel = NSOpenPanel()
    panel.title = "安装 Codex 皮肤"
    panel.message = "选择包含 theme.json 和背景图片的皮肤文件夹"
    panel.prompt = "安装皮肤"
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    guard panel.runModal() == .OK, let source = panel.url else { return }

    do {
      let package = try ThemePackageService.validate(directory: source)
      guard !BuiltinThemeCatalog.ids.contains(package.manifest.id) else {
        status = "内置主题 ID 受保护，请更换 theme.json 中的 id"
        return
      }
      let destination = themesRoot.appendingPathComponent(package.manifest.id)
      let replacing = FileManager.default.fileExists(atPath: destination.path)
      if replacing {
        let alert = NSAlert()
        alert.messageText = "替换现有主题？"
        alert.informativeText = "“\(package.manifest.name)”已经安装，继续会替换原主题包。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "替换")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
      }
      try ThemePackageService.install(package: package, into: themesRoot, replacing: replacing)
      reload()
      status = replacing ? "已更新“\(package.manifest.name)”" : "已导入“\(package.manifest.name)”"
    } catch {
      status = "导入失败：\(error.localizedDescription)"
    }
  }

  func presentThemeCreator() { isCreateThemePresented = true }
  func revealThemes() { NSWorkspace.shared.activateFileViewerSelecting([themesRoot]) }
  func revealTheme(_ theme: ThemeItem) { NSWorkspace.shared.activateFileViewerSelecting([theme.directory]) }
  func revealDataDirectory() { NSWorkspace.shared.activateFileViewerSelecting([stateRoot]) }
  func revealThemeCreatorSkill() {
    let target = FileManager.default.fileExists(atPath: themeCreatorSkillRoot.path)
      ? themeCreatorSkillRoot
      : themeCreatorSkillRoot.deletingLastPathComponent()
    try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
    NSWorkspace.shared.activateFileViewerSelecting([target])
  }

  func installThemeCreatorSkill(silent: Bool = false) {
    guard let source = bundledThemeCreatorSkillRoot(),
          themeCreatorSkillFiles.allSatisfy({
            FileManager.default.isReadableFile(atPath: source.appendingPathComponent($0).path)
          })
    else {
      isThemeCreatorSkillInstalled = false
      if !silent { status = "管理器内置的主题创建 Skill 不完整" }
      return
    }

    let fileManager = FileManager.default
    let parent = themeCreatorSkillRoot.deletingLastPathComponent()
    let token = UUID().uuidString
    let staging = parent.appendingPathComponent(".codex-skin-theme-creator.installing.\(token)")
    let backup = parent.appendingPathComponent(".codex-skin-theme-creator.backup.\(token)")
    do {
      try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
      try? fileManager.removeItem(at: staging)
      try? fileManager.removeItem(at: backup)
      try fileManager.copyItem(at: source, to: staging)
      if fileManager.fileExists(atPath: themeCreatorSkillRoot.path) {
        try fileManager.moveItem(at: themeCreatorSkillRoot, to: backup)
      }
      do {
        try fileManager.moveItem(at: staging, to: themeCreatorSkillRoot)
        try? fileManager.removeItem(at: backup)
      } catch {
        if fileManager.fileExists(atPath: backup.path) {
          try? fileManager.moveItem(at: backup, to: themeCreatorSkillRoot)
        }
        throw error
      }
      isThemeCreatorSkillInstalled = themeCreatorSkillIsCurrent()
      if !silent { status = "主题创建 Skill 已安装，Codex 可直接创建并加入主题库" }
    } catch {
      try? fileManager.removeItem(at: staging)
      if fileManager.fileExists(atPath: backup.path),
         !fileManager.fileExists(atPath: themeCreatorSkillRoot.path) {
        try? fileManager.moveItem(at: backup, to: themeCreatorSkillRoot)
      }
      isThemeCreatorSkillInstalled = themeCreatorSkillIsCurrent()
      if !silent { status = "Skill 安装失败：\(error.localizedDescription)" }
    }
  }

  func openCodex() { NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/ChatGPT.app")) }

  private func bundledThemeCreatorSkillRoot() -> URL? {
    Bundle.main.resourceURL?
      .appendingPathComponent("Skills/codex-skin-theme-creator", isDirectory: true)
  }

  private func themeCreatorSkillIsCurrent() -> Bool {
    guard let source = bundledThemeCreatorSkillRoot() else { return false }
    return themeCreatorSkillFiles.allSatisfy { relativePath in
      let sourceFile = source.appendingPathComponent(relativePath).path
      let installedFile = themeCreatorSkillRoot.appendingPathComponent(relativePath).path
      return FileManager.default.contentsEqual(atPath: sourceFile, andPath: installedFile)
    }
  }

  private func currentThemeLibraryFingerprint() -> String {
    let fileManager = FileManager.default
    let directories = (try? fileManager.contentsOfDirectory(
      at: themesRoot,
      includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
      options: [.skipsHiddenFiles]
    )) ?? []
    var parts = directories.sorted { $0.lastPathComponent < $1.lastPathComponent }.map { directory in
      let files = ["theme.json", "background.png", "preview.png"].map { filename -> String in
        let url = directory.appendingPathComponent(filename)
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        return "\(filename):\(values?.fileSize ?? -1):\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
      }
      return "\(directory.lastPathComponent)|\(files.joined(separator: "|"))"
    }
    let marker = stateRoot.appendingPathComponent("theme-library.changed")
    let markerValues = try? marker.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
    parts.append(
      "marker:\(markerValues?.fileSize ?? -1):\(markerValues?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
    )
    return parts.joined(separator: "\n")
  }

  private func loadLiveState(using decoder: JSONDecoder = JSONDecoder()) {
    runtimeState = (try? Data(contentsOf: runtimeStateURL))
      .flatMap { try? decoder.decode(RuntimeState.self, from: $0) }
    runtimeConnected = probeRuntimeConnection()
    if runtimeState?.session == "paused", themes.contains(where: { $0.id == "codex-default" }) {
      activeID = "codex-default"
    } else if let data = try? Data(contentsOf: activeThemeURL),
              let manifest = try? decoder.decode(ThemeManifest.self, from: data) {
      activeID = manifest.id
    } else {
      activeID = nil
    }
  }

  private func probeRuntimeConnection() -> Bool {
    guard runtimeState?.session == "active",
          let pid = runtimeState?.injectorPid,
          pid > 0
    else { return false }
    return kill(pid_t(pid), 0) == 0
  }

  private func currentLiveStateFingerprint() -> String {
    [runtimeStateURL, activeThemeURL].map { url in
      let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
      return "\(url.lastPathComponent):\(values?.fileSize ?? -1):\(values?.contentModificationDate?.timeIntervalSince1970 ?? 0)"
    }.joined(separator: "|")
  }

  private func refreshMonitoredStateIfNeeded() {
    let libraryFingerprint = currentThemeLibraryFingerprint()
    if libraryFingerprint != themeLibraryFingerprint {
      reload()
      status = "检测到新主题，皮肤库已自动刷新"
      return
    }

    let stateFingerprint = currentLiveStateFingerprint()
    if stateFingerprint != liveStateFingerprint {
      loadLiveState()
      liveStateFingerprint = stateFingerprint
    } else {
      let connected = probeRuntimeConnection()
      if connected != runtimeConnected { runtimeConnected = connected }
    }
  }
}

struct SidebarView: View {
  @Binding var selection: StudioSection
  @ObservedObject var store: ThemeStore

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 13) {
        ZStack {
          RoundedRectangle(cornerRadius: 8)
            .fill(LinearGradient(colors: [StudioPalette.accent, StudioPalette.gold], startPoint: .topLeading, endPoint: .bottomTrailing))
          Image(systemName: "sparkles.rectangle.stack.fill")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
        }
        .frame(width: 42, height: 42)
        VStack(alignment: .leading, spacing: 2) {
          Text("Codex 皮肤管理器").font(.system(size: 16, weight: .bold, design: .rounded))
          Text("主题一键切换工具").font(.system(size: 11)).foregroundStyle(.white.opacity(0.52))
        }
      }
      .padding(.horizontal, 22)
      .padding(.top, 26)
      .padding(.bottom, 30)

      VStack(spacing: 8) {
        ForEach(StudioSection.allCases) { item in
          SidebarButton(
            item: item,
            isSelected: selection == item,
            badge: item == .installed ? "\(store.installedThemes.count)" : nil,
            showsStatus: item == .runtime
          ) { selection = item }
        }
      }
      .padding(.horizontal, 14)

      Spacer(minLength: 20)

      VStack(alignment: .leading, spacing: 5) {
        Label("安全注入", systemImage: "checkmark.shield")
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(StudioPalette.signal)
        Text("不修改官方 app.asar")
          .font(.system(size: 11))
          .foregroundStyle(.white.opacity(0.48))
      }
      .padding(16)
      .frame(maxWidth: .infinity, alignment: .leading)
      .background(Color.white.opacity(0.055))
      .clipShape(RoundedRectangle(cornerRadius: 8))
      .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.white.opacity(0.10)))
      .padding(.horizontal, 16)
      .padding(.bottom, 16)

      VStack(alignment: .leading, spacing: 4) {
        SidebarUtilityButton(title: "数据目录", icon: "slider.horizontal.3", action: store.revealDataDirectory)
        SidebarUtilityButton(title: "打开 Codex", icon: "arrow.up.forward.app", action: store.openCodex)
      }
      .padding(.horizontal, 14)

      Text("Codex 皮肤管理器 · v\(UpdateService.currentVersion)")
        .font(.system(size: 10, design: .monospaced))
        .foregroundStyle(.white.opacity(0.32))
        .padding(.horizontal, 22)
        .padding(.top, 14)
        .padding(.bottom, 20)
    }
    .foregroundStyle(StudioPalette.sidebarText)
    .background(StudioPalette.sidebar)
  }
}

struct SidebarButton: View {
  let item: StudioSection
  let isSelected: Bool
  let badge: String?
  let showsStatus: Bool
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      HStack(spacing: 12) {
        Image(systemName: item.icon)
          .font(.system(size: 17, weight: .medium))
          .frame(width: 22)
        Text(item.rawValue).font(.system(size: 15, weight: isSelected ? .semibold : .medium))
        Spacer()
        if let badge {
          Text(badge)
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Color.black.opacity(0.05))
            .clipShape(Capsule())
        } else if showsStatus {
          Circle().fill(StudioPalette.signal).frame(width: 7, height: 7)
        }
      }
      .foregroundStyle(isSelected ? .white : .white.opacity(0.62))
      .padding(.horizontal, 14)
      .frame(height: 48)
      .background(isSelected ? StudioPalette.sidebarSelected : Color.clear)
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .buttonStyle(.plain)
  }
}

struct SidebarUtilityButton: View {
  let title: String
  let icon: String
  let action: () -> Void

  var body: some View {
    Button(action: action) {
      Label(title, systemImage: icon)
        .font(.system(size: 13, weight: .medium))
        .foregroundStyle(.white.opacity(0.55))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .frame(height: 34)
    }
    .buttonStyle(.plain)
  }
}

struct PageHeader: View {
  let eyebrow: String
  let title: String
  let subtitle: String
  let actionTitle: String?
  let actionIcon: String
  let action: (() -> Void)?

  var body: some View {
    HStack(alignment: .center, spacing: 24) {
      HStack(spacing: 16) {
        RoundedRectangle(cornerRadius: 2)
          .fill(StudioPalette.accent)
          .frame(width: 5, height: 58)
        VStack(alignment: .leading, spacing: 6) {
          Text(eyebrow.uppercased())
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(StudioPalette.muted)
          Text(title)
            .font(.system(size: 28, weight: .bold))
            .foregroundStyle(StudioPalette.ink)
          Text(subtitle)
            .font(.system(size: 13))
            .foregroundStyle(StudioPalette.muted)
        }
      }
      Spacer()
      if let actionTitle, let action {
        Button(action: action) {
          Label(actionTitle, systemImage: actionIcon)
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 18)
            .frame(height: 42)
            .foregroundStyle(.white)
            .background(StudioPalette.accent)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
      }
    }
  }
}

struct ActiveThemeBar: View {
  @ObservedObject var store: ThemeStore

  var body: some View {
    HStack(spacing: 0) {
      VStack(alignment: .leading, spacing: 11) {
        HStack(spacing: 8) {
          Text("LIVE THEME")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(StudioPalette.signal)
          Circle().fill(StudioPalette.signal).frame(width: 5, height: 5)
          Text("\(store.installedThemes.count) 套已安装")
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(StudioPalette.muted)
        }
        Text(store.activeTheme?.manifest.name ?? "等待连接")
          .font(.system(size: 23, weight: .bold))
          .foregroundStyle(StudioPalette.ink)
        Text(store.activeTheme?.manifest.description ?? "选择一套主题开始使用。")
          .font(.system(size: 11))
          .foregroundStyle(StudioPalette.muted)
          .lineLimit(2)
          .frame(maxWidth: 460, alignment: .leading)
        HStack(spacing: 14) {
          Label(store.isRuntimeActive ? "Codex 已连接" : "等待 Codex 连接", systemImage: "bolt.horizontal.circle.fill")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(store.isRuntimeActive ? StudioPalette.signal : .orange)
          Button(action: store.restoreOriginal) {
            Label("恢复原皮", systemImage: "arrow.counterclockwise")
              .font(.system(size: 11, weight: .semibold))
          }
          .buttonStyle(.plain)
          .foregroundStyle(StudioPalette.ink.opacity(0.72))
          .disabled(store.activeID == "codex-default" || store.isApplying)
        }
      }
      .padding(.horizontal, 22)
      .padding(.vertical, 18)
      .frame(maxWidth: .infinity, minHeight: 142, alignment: .leading)

      Group {
        if let theme = store.activeTheme,
           let image = ThemeImageCache.shared.image(at: theme.backgroundURL) {
          Image(nsImage: image).resizable().scaledToFill()
        } else {
          StudioPalette.sidebar
        }
      }
      .frame(width: 430, height: 142)
      .clipped()
      .overlay(alignment: .bottomTrailing) {
        Text("CURRENT")
          .font(.system(size: 9, weight: .bold, design: .monospaced))
          .foregroundStyle(.white)
          .padding(.horizontal, 9)
          .frame(height: 24)
          .background(Color.black.opacity(0.56))
          .padding(10)
      }
    }
    .background(StudioPalette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(StudioPalette.line, lineWidth: 1))
    .shadow(color: .black.opacity(0.04), radius: 12, y: 4)
  }
}

struct SearchField: View {
  @Binding var text: String
  @FocusState private var isFocused: Bool

  var body: some View {
    HStack(spacing: 9) {
      Image(systemName: "magnifyingglass").foregroundStyle(StudioPalette.muted)
      TextField("搜索皮肤、作者或标签", text: $text)
        .textFieldStyle(.plain)
        .font(.system(size: 13))
        .focused($isFocused)
      if !text.isEmpty {
        Button(action: { text = "" }) {
          Image(systemName: "xmark.circle.fill").foregroundStyle(StudioPalette.muted)
        }
        .buttonStyle(.plain)
      }
    }
    .padding(.horizontal, 13)
    .frame(width: 270, height: 38)
    .background(StudioPalette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(StudioPalette.line))
    .onAppear {
      DispatchQueue.main.async { isFocused = false }
    }
  }
}

struct ThemeCard: View {
  @ObservedObject var store: ThemeStore
  let theme: ThemeItem
  let isActive: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ZStack(alignment: .top) {
        Group {
          if let image = ThemeImageCache.shared.image(at: theme.previewURL) {
            Image(nsImage: image).resizable().scaledToFill()
          } else {
            StudioPalette.sidebar
          }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(3, contentMode: .fit)
        .clipped()

        HStack {
          if isActive {
            Label("使用中", systemImage: "checkmark")
              .font(.system(size: 10, weight: .semibold))
              .padding(.horizontal, 9)
              .frame(height: 24)
              .foregroundStyle(.white)
              .background(StudioPalette.signal)
              .clipShape(Capsule())
          }
          Spacer()
          Text(theme.isBuiltIn ? "内置" : "自定义")
            .font(.system(size: 9, weight: .medium))
            .padding(.horizontal, 8)
            .frame(height: 22)
            .foregroundStyle(.white)
            .background((theme.isBuiltIn ? StudioPalette.gold : StudioPalette.accent).opacity(0.92))
            .clipShape(Capsule())
        }
        .padding(10)
      }

      VStack(alignment: .leading, spacing: 9) {
        HStack(spacing: 8) {
          Text(theme.manifest.name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(StudioPalette.ink)
            .lineLimit(1)
            .minimumScaleFactor(0.78)
            .layoutPriority(1)
          Spacer()
          Menu {
            Button("在访达中显示", systemImage: "folder") { store.revealTheme(theme) }
            Button("打开 Codex", systemImage: "arrow.up.forward.app") { store.openCodex() }
          } label: {
            Image(systemName: "ellipsis")
              .font(.system(size: 14, weight: .semibold))
              .foregroundStyle(StudioPalette.muted)
              .frame(width: 26, height: 24)
          }
          .menuStyle(.borderlessButton)
          .menuIndicator(.hidden)
        }

        Text("by \(theme.manifest.author?.isEmpty == false ? theme.manifest.author! : (theme.isBuiltIn ? "Codex 皮肤管理器" : "本地创作者"))")
          .font(.system(size: 10))
          .foregroundStyle(StudioPalette.muted)

        Text(theme.manifest.description ?? "完整 Codex 皮肤主题")
          .font(.system(size: 11))
          .foregroundStyle(StudioPalette.muted)
          .lineLimit(2)
          .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)

        HStack(spacing: 6) {
          TagChip(theme.manifest.category ?? "主题")
          TagChip(theme.appearanceLabel)
        }

        Button(action: { store.apply(theme) }) {
          HStack(spacing: 7) {
            if isApplyingThisTheme {
              ProgressView().controlSize(.mini)
            } else {
              Image(systemName: actionIcon)
            }
            Text(actionTitle)
          }
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(isActive ? StudioPalette.signal : .white)
          .frame(maxWidth: .infinity)
          .frame(height: 36)
          .background(isActive ? StudioPalette.signalSoft : (isApplyingThisTheme ? StudioPalette.accent : StudioPalette.ink))
          .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
        .disabled(isActive)
      }
      .padding(14)
    }
    .background(StudioPalette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(
      RoundedRectangle(cornerRadius: 8)
        .stroke(isActive ? StudioPalette.signal : StudioPalette.line, lineWidth: isActive ? 1.5 : 1)
    )
    .shadow(color: .black.opacity(0.035), radius: 8, y: 3)
  }

  private var actionTitle: String {
    if isApplyingThisTheme { return "切换中…" }
    if theme.isOriginal { return isActive ? "当前为原版" : "恢复原皮" }
    return isActive ? "当前使用" : "一键切换"
  }

  private var actionIcon: String {
    if theme.isOriginal { return "arrow.counterclockwise" }
    return isActive ? "checkmark" : "arrow.left.arrow.right"
  }

  private var isApplyingThisTheme: Bool {
    store.applyingThemeID == theme.id
  }
}

struct TagChip: View {
  let title: String
  init(_ title: String) { self.title = title }

  var body: some View {
    Text(title)
      .font(.system(size: 9, weight: .medium))
      .foregroundStyle(StudioPalette.muted)
      .padding(.horizontal, 7)
      .frame(height: 21)
      .background(StudioPalette.canvas)
      .clipShape(RoundedRectangle(cornerRadius: 5))
  }
}

struct ThemeLibraryView: View {
  @ObservedObject var store: ThemeStore
  let installedOnly: Bool
  @State private var searchText = ""

  private var filteredThemes: [ThemeItem] {
    let source = installedOnly ? store.installedThemes : store.themes
    let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !query.isEmpty else { return source }
    return source.filter { theme in
      [theme.manifest.name, theme.manifest.description ?? "", theme.manifest.category ?? "", theme.appearanceLabel]
        .joined(separator: " ").lowercased().contains(query)
    }
  }

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 24) {
        PageHeader(
          eyebrow: "Skin Manager",
          title: installedOnly ? "已安装主题" : "主题工作台",
          subtitle: installedOnly ? "查看、切换并维护本机主题。" : "浏览真实效果，选择下一套 Codex 工作氛围。",
          actionTitle: "创建主题",
          actionIcon: "plus",
          action: store.presentThemeCreator
        )

        ActiveThemeBar(store: store)

        HStack(alignment: .center) {
          HStack(alignment: .firstTextBaseline, spacing: 9) {
            Text(installedOnly ? "已安装" : "皮肤库")
              .font(.system(size: 20, weight: .bold))
              .foregroundStyle(StudioPalette.ink)
            Text("\(filteredThemes.count) 个外观可用")
              .font(.system(size: 11))
              .foregroundStyle(StudioPalette.muted)
          }
          Spacer()
          Button("导入主题", systemImage: "square.and.arrow.down", action: store.importTheme)
            .buttonStyle(.bordered)
          SearchField(text: $searchText)
        }

        if filteredThemes.isEmpty {
          ContentUnavailableView("没有匹配的皮肤", systemImage: "magnifyingglass", description: Text("调整搜索关键词后再试。"))
            .frame(maxWidth: .infinity, minHeight: 260)
        } else {
          LazyVGrid(columns: [GridItem(.adaptive(minimum: 230, maximum: 320), spacing: 18)], spacing: 18) {
            ForEach(filteredThemes) { theme in
              ThemeCard(store: store, theme: theme, isActive: store.activeID == theme.id)
            }
          }
        }

        HStack {
          Text(store.status).font(.system(size: 11)).foregroundStyle(StudioPalette.muted)
          Spacer()
          Button("刷新", systemImage: "arrow.clockwise", action: store.reload)
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(StudioPalette.accent)
        }
        .padding(.top, 4)
      }
      .padding(30)
      .frame(maxWidth: 1320, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .background(StudioPalette.canvas)
  }
}

struct IntegrationView: View {
  @ObservedObject var store: ThemeStore

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        PageHeader(
          eyebrow: "Integration",
          title: "接入标准",
          subtitle: "当前引擎、主题包结构与本地数据路径。",
          actionTitle: "创建主题",
          actionIcon: "plus",
          action: store.presentThemeCreator
        )
        HStack(spacing: 12) {
          Button("导入主题", systemImage: "square.and.arrow.down", action: store.importTheme)
            .buttonStyle(.borderedProminent)
            .tint(StudioPalette.accent)
          Button("打开皮肤目录", systemImage: "folder", action: store.revealThemes)
            .buttonStyle(.bordered)
        }
        ThemeCreatorSkillPanel(store: store)
        VStack(spacing: 0) {
          InfoRow(icon: "checkmark.shield", title: "注入方式", value: "本机回环 CDP，不修改官方 app.asar")
          Divider().padding(.leading, 58)
          InfoRow(icon: "doc.text", title: "主题清单", value: "theme.json + background.png + preview.png")
          Divider().padding(.leading, 58)
          InfoRow(icon: "externaldrive", title: "数据目录", value: store.stateRoot.path)
          Divider().padding(.leading, 58)
          InfoRow(icon: "gearshape.2", title: "引擎目录", value: store.engineRoot.path)
        }
        .background(StudioPalette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(StudioPalette.line))

        ThemeFormatView()
      }
      .padding(30)
      .frame(maxWidth: 1100, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .background(StudioPalette.canvas)
  }
}

struct ThemeCreatorSkillPanel: View {
  @ObservedObject var store: ThemeStore

  var body: some View {
    HStack(spacing: 18) {
      Image(systemName: "wand.and.stars")
        .font(.system(size: 22, weight: .semibold))
        .foregroundStyle(StudioPalette.accent)
        .frame(width: 48, height: 48)
        .background(StudioPalette.accentSoft)
        .clipShape(RoundedRectangle(cornerRadius: 8))

      VStack(alignment: .leading, spacing: 5) {
        HStack(spacing: 9) {
          Text("Codex 主题创建 Skill")
            .font(.system(size: 15, weight: .bold))
          Text(store.isThemeCreatorSkillInstalled ? "已安装" : "需要安装")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(
              store.isThemeCreatorSkillInstalled ? StudioPalette.signal : StudioPalette.gold
            )
            .padding(.horizontal, 7)
            .frame(height: 21)
            .background(
              store.isThemeCreatorSkillInstalled ? StudioPalette.signalSoft : Color.orange.opacity(0.10)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        Text("通过对话生成或重做主题，完成后自动加入当前皮肤库。")
          .font(.system(size: 12))
          .foregroundStyle(StudioPalette.muted)
      }

      Spacer()

      Button(
        store.isThemeCreatorSkillInstalled ? "重新安装" : "安装 Skill",
        systemImage: store.isThemeCreatorSkillInstalled ? "arrow.triangle.2.circlepath" : "square.and.arrow.down",
        action: { store.installThemeCreatorSkill() }
      )
      .buttonStyle(.borderedProminent)
      .tint(StudioPalette.ink)
      Button(action: store.revealThemeCreatorSkill) {
        Image(systemName: "folder")
      }
      .buttonStyle(.bordered)
      .help("打开 Skill 目录")
    }
    .padding(20)
    .background(StudioPalette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(StudioPalette.line))
  }
}

struct RuntimeView: View {
  @ObservedObject var store: ThemeStore

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 26) {
        PageHeader(
          eyebrow: "Runtime",
          title: "运行状态",
          subtitle: "检查 Codex 连接、注入器与当前皮肤。",
          actionTitle: "刷新状态",
          actionIcon: "arrow.clockwise",
          action: store.reload
        )
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 16)], spacing: 16) {
          RuntimeMetric(title: "皮肤会话", value: store.runtimeSessionLabel, icon: "bolt.fill", good: store.isRuntimeActive)
          RuntimeMetric(title: "当前皮肤", value: store.activeTheme?.manifest.name ?? "未识别", icon: "paintpalette.fill", good: store.activeID != nil)
          RuntimeMetric(title: "CDP 端口", value: String(store.runtimeState?.port ?? 9341), icon: "network", good: store.isRuntimeActive)
          RuntimeMetric(title: "主题数量", value: "\(store.themes.count)", icon: "rectangle.stack.fill", good: !store.themes.isEmpty)
        }
        HStack(spacing: 12) {
          Button("打开 Codex", systemImage: "arrow.up.forward.app", action: store.openCodex)
            .buttonStyle(.borderedProminent).tint(StudioPalette.accent)
          Button("打开数据目录", systemImage: "folder", action: store.revealDataDirectory)
            .buttonStyle(.bordered)
        }
      }
      .padding(30)
      .frame(maxWidth: 1100, alignment: .leading)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .background(StudioPalette.canvas)
  }
}

struct ThemeFormatView: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      HStack {
        Label("主题导入格式", systemImage: "shippingbox")
          .font(.system(size: 17, weight: .bold))
        Spacer()
        Text("SCHEMA 2")
          .font(.system(size: 10, weight: .bold, design: .monospaced))
          .foregroundStyle(StudioPalette.signal)
      }

      HStack(alignment: .top, spacing: 32) {
        VStack(alignment: .leading, spacing: 9) {
          FormatFileRow(icon: "doc.text", name: "theme.json", detail: "清单与配色")
          FormatFileRow(icon: "photo", name: "background.png", detail: "至少 1200×400")
          FormatFileRow(icon: "rectangle.on.rectangle", name: "preview.png", detail: "至少 600×200")
        }
        .frame(maxWidth: .infinity, alignment: .leading)

        VStack(alignment: .leading, spacing: 9) {
          Label("两张图片均为精确 3:1 PNG", systemImage: "checkmark.circle")
          Label("ID 使用小写字母、数字和连字符", systemImage: "checkmark.circle")
          Label("avatarOverlay 固定为 show", systemImage: "checkmark.circle")
          Label("不使用 taskImage 或符号链接", systemImage: "checkmark.circle")
        }
        .font(.system(size: 12))
        .foregroundStyle(StudioPalette.muted)
        .frame(maxWidth: .infinity, alignment: .leading)
      }
    }
    .padding(22)
    .background(StudioPalette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(StudioPalette.line))
  }
}

struct FormatFileRow: View {
  let icon: String
  let name: String
  let detail: String

  var body: some View {
    HStack(spacing: 12) {
      Image(systemName: icon)
        .foregroundStyle(StudioPalette.accent)
        .frame(width: 22)
      Text(name)
        .font(.system(size: 12, weight: .semibold, design: .monospaced))
      Spacer()
      Text(detail)
        .font(.system(size: 11))
        .foregroundStyle(StudioPalette.muted)
    }
  }
}

struct InfoRow: View {
  let icon: String
  let title: String
  let value: String

  var body: some View {
    HStack(spacing: 16) {
      Image(systemName: icon)
        .font(.system(size: 17, weight: .medium))
        .foregroundStyle(StudioPalette.accent)
        .frame(width: 28)
      Text(title).font(.system(size: 14, weight: .semibold)).frame(width: 90, alignment: .leading)
      Text(value).font(.system(size: 12)).foregroundStyle(StudioPalette.muted).textSelection(.enabled)
      Spacer()
    }
    .padding(.horizontal, 20)
    .frame(minHeight: 66)
  }
}

struct RuntimeMetric: View {
  let title: String
  let value: String
  let icon: String
  let good: Bool

  var body: some View {
    HStack(spacing: 14) {
      Image(systemName: icon)
        .font(.system(size: 18, weight: .medium))
        .foregroundStyle(good ? StudioPalette.signal : .orange)
        .frame(width: 40, height: 40)
        .background(good ? StudioPalette.signalSoft : Color.orange.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8))
      VStack(alignment: .leading, spacing: 4) {
        Text(title).font(.system(size: 11)).foregroundStyle(StudioPalette.muted)
        Text(value).font(.system(size: 16, weight: .semibold)).lineLimit(1)
      }
      Spacer()
    }
    .padding(18)
    .background(StudioPalette.surface)
    .clipShape(RoundedRectangle(cornerRadius: 8))
    .overlay(RoundedRectangle(cornerRadius: 8).stroke(StudioPalette.line))
  }
}

struct ContentView: View {
  @ObservedObject var store: ThemeStore
  @State private var selection: StudioSection = .library

  var body: some View {
    NavigationSplitView {
      SidebarView(selection: $selection, store: store)
        .navigationSplitViewColumnWidth(min: 220, ideal: 235, max: 250)
    } detail: {
      Group {
        switch selection {
        case .library: ThemeLibraryView(store: store, installedOnly: false)
        case .installed: ThemeLibraryView(store: store, installedOnly: true)
        case .integration: IntegrationView(store: store)
        case .runtime: RuntimeView(store: store)
        }
      }
      .toolbar {
        ToolbarItem(placement: .principal) {
          Text("Codex 皮肤管理器").font(.system(size: 13, weight: .semibold))
        }
        ToolbarItemGroup(placement: .primaryAction) {
          UpdateToolbarButton(updater: store.updateService)
          Button(action: store.reload) { Image(systemName: "arrow.clockwise") }.help("刷新皮肤库")
          Button(action: store.revealThemes) { Image(systemName: "folder") }.help("打开皮肤目录")
        }
      }
    }
    .navigationSplitViewStyle(.balanced)
    .preferredColorScheme(.light)
    .sheet(isPresented: $store.isCreateThemePresented) {
      CreateThemeView(store: store)
    }
  }
}

struct MenuBarStatusView: View {
  @ObservedObject var store: ThemeStore
  @ObservedObject var updater: UpdateService
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Text("当前主题：\(store.activeTheme?.manifest.name ?? "尚未选择")")
    Text("实时状态：\(store.runtimeSessionLabel)")
    if let applyingThemeID = store.applyingThemeID,
       let theme = store.themes.first(where: { $0.id == applyingThemeID }) {
      Text("正在切换：\(theme.manifest.name)")
    }

    Divider()

    Menu("快速切换") {
      ForEach(store.themes) { theme in
        Button {
          store.apply(theme)
        } label: {
          Label(
            theme.manifest.name,
            systemImage: store.activeID == theme.id ? "checkmark.circle.fill" : "circle"
          )
        }
        .disabled(store.isApplying || store.activeID == theme.id)
      }
    }
    .disabled(store.themes.isEmpty)

    Button("打开管理器") {
      openWindow(id: "manager")
      NSApp.activate(ignoringOtherApps: true)
    }
    Button("刷新实时状态", action: store.reload)
    Button("打开 Codex", action: store.openCodex)
    Button(updater.hasUpdates ? "有可用更新…" : "检查更新…") {
      updater.present()
      openWindow(id: "manager")
      NSApp.activate(ignoringOtherApps: true)
    }

    Divider()

    Button("退出皮肤管理器") {
      NSApp.terminate(nil)
    }
  }
}

extension Color {
  init(hex: String) {
    let cleaned = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
    var value: UInt64 = 0
    Scanner(string: cleaned).scanHexInt64(&value)
    let red, green, blue: Double
    if cleaned.count == 6 {
      red = Double((value >> 16) & 0xff) / 255
      green = Double((value >> 8) & 0xff) / 255
      blue = Double(value & 0xff) / 255
    } else {
      red = 0.42; green = 0.45; blue = 0.50
    }
    self.init(red: red, green: green, blue: blue)
  }
}

@main
struct DreamSkinStudioApp: App {
  @StateObject private var store = ThemeStore()

  var body: some Scene {
    Window("Codex 皮肤管理器", id: "manager") {
      ContentView(store: store)
        .frame(minWidth: 1320, minHeight: 700)
    }
    .defaultSize(width: 1380, height: 860)
    .windowStyle(.titleBar)
    .windowToolbarStyle(.unifiedCompact(showsTitle: false))
    .commands {
      CommandGroup(replacing: .newItem) { }
    }

    MenuBarExtra {
      MenuBarStatusView(store: store, updater: store.updateService)
    } label: {
      HStack(spacing: 4) {
        Image(systemName: store.isRuntimeActive ? "paintpalette.fill" : "paintpalette")
        Text("皮肤")
      }
      .accessibilityLabel("Codex 皮肤管理器")
    }
    .menuBarExtraStyle(.menu)
  }
}
