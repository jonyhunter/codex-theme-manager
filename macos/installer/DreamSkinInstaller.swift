import AppKit
import SwiftUI

@MainActor
final class InstallerModel: ObservableObject {
  @Published var isInstalling = false
  @Published var isInstalled = false
  @Published var headline = "准备安装"
  @Published var detail = "将主题引擎与皮肤管理器部署到当前用户。"
  @Published var errorDetail: String?

  private let managerBundleID = "com.codexdreamskin.studio"
  private let automaticUpdate = CommandLine.arguments.contains("--automatic-update")

  func install() {
    guard !isInstalling else { return }
    guard let resources = Bundle.main.resourceURL else {
      fail("安装器资源目录缺失")
      return
    }
    let payload = resources.appendingPathComponent("Payload")
    let script = payload.appendingPathComponent("scripts/install-dream-skin-macos.sh")
    let bundledManager = resources.appendingPathComponent("Codex 皮肤管理器.app")
    guard FileManager.default.isExecutableFile(atPath: script.path),
          FileManager.default.fileExists(atPath: bundledManager.path)
    else {
      fail("安装包内容不完整")
      return
    }

    isInstalling = true
    isInstalled = false
    errorDetail = nil
    headline = "正在安装"
    detail = "正在部署主题引擎，请保持此窗口打开。"

    Task.detached(priority: .userInitiated) { [weak self] in
      let process = Process()
      let output = Pipe()
      process.executableURL = URL(fileURLWithPath: "/bin/bash")
      process.arguments = [script.path, "--no-launchers", "--no-launch"]
      process.standardOutput = output
      process.standardError = output

      do {
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        let log = String(data: data, encoding: .utf8)?
          .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard process.terminationStatus == 0 else {
          await self?.fail(log.isEmpty ? "主题引擎安装失败" : log)
          return
        }
        try self?.installManager(from: bundledManager)
        await self?.complete()
      } catch {
        await self?.fail(error.localizedDescription)
      }
    }
  }

  func openManager() {
    let target = FileManager.default.homeDirectoryForCurrentUser
      .appendingPathComponent("Applications/Codex 皮肤管理器.app")
    NSWorkspace.shared.openApplication(at: target, configuration: .init())
  }

  nonisolated private func installManager(from source: URL) throws {
    let fm = FileManager.default
    let home = fm.homeDirectoryForCurrentUser
    let applications = home.appendingPathComponent("Applications", isDirectory: true)
    let destination = applications.appendingPathComponent("Codex 皮肤管理器.app", isDirectory: true)
    let desktop = home.appendingPathComponent("Desktop/Codex 皮肤管理器.app")
    let legacyApps = [
      applications.appendingPathComponent("Codex Dream Skin.app", isDirectory: true),
      home.appendingPathComponent("Desktop/Codex Dream Skin.app"),
    ]

    stopRunningManager()
    try fm.createDirectory(at: applications, withIntermediateDirectories: true)
    for legacy in legacyApps where fm.fileExists(atPath: legacy.path) {
      let existingBundleID = Bundle(url: legacy)?.bundleIdentifier
      let isSymlink = (try? legacy.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
      if existingBundleID == managerBundleID || isSymlink {
        try fm.removeItem(at: legacy)
      }
    }
    if fm.fileExists(atPath: destination.path) {
      guard Bundle(url: destination)?.bundleIdentifier == managerBundleID else {
        throw NSError(domain: "DreamSkinInstaller", code: 2, userInfo: [
          NSLocalizedDescriptionKey: "用户应用目录存在同名的其他应用"
        ])
      }
      try fm.removeItem(at: destination)
    }
    try fm.copyItem(at: source, to: destination)

    if fm.fileExists(atPath: desktop.path) {
      let existingBundleID = Bundle(url: desktop)?.bundleIdentifier
      let isSymlink = (try? desktop.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
      if existingBundleID == managerBundleID || isSymlink {
        try fm.removeItem(at: desktop)
      }
    }
    if !fm.fileExists(atPath: desktop.path) {
      try fm.copyItem(at: destination, to: desktop)
    }

    for app in [destination, desktop] {
      let xattr = Process()
      xattr.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
      xattr.arguments = ["-cr", app.path]
      try? xattr.run()
      xattr.waitUntilExit()
    }
  }

  nonisolated private func stopRunningManager() {
    for processName in ["CodexSkinManager", "DreamSkinStudio"] {
      let terminate = Process()
      terminate.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
      terminate.arguments = ["-TERM", "-x", processName]
      try? terminate.run()
      terminate.waitUntilExit()

      if terminate.terminationStatus == 0 {
        for _ in 0..<20 {
          let probe = Process()
          probe.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
          probe.arguments = ["-x", processName]
          try? probe.run()
          probe.waitUntilExit()
          if probe.terminationStatus != 0 { break }
          Thread.sleep(forTimeInterval: 0.1)
        }
      }
    }
  }

  private func complete() {
    isInstalling = false
    isInstalled = true
    headline = "安装完成"
    detail = "皮肤管理器已放入“应用程序”并在桌面创建入口。"
    openManager()
    if automaticUpdate {
      DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
        NSApp.terminate(nil)
      }
    }
  }

  private func fail(_ message: String) {
    isInstalling = false
    isInstalled = false
    headline = "安装未完成"
    detail = "检查下方信息后重新安装。"
    errorDetail = message
  }
}

struct InstallerView: View {
  @StateObject private var model = InstallerModel()

  var body: some View {
    VStack(spacing: 0) {
      HStack(alignment: .top, spacing: 18) {
        ZStack {
          RoundedRectangle(cornerRadius: 14)
            .fill(LinearGradient(
              colors: [Color(red: 0.86, green: 0.31, blue: 0.25), Color(red: 0.73, green: 0.50, blue: 0.16)],
              startPoint: .topLeading,
              endPoint: .bottomTrailing
            ))
          Image(systemName: "sparkles.rectangle.stack.fill")
            .font(.system(size: 28, weight: .semibold))
            .foregroundStyle(.white)
        }
        .frame(width: 70, height: 70)

        VStack(alignment: .leading, spacing: 6) {
          Text("CODEX SKIN")
            .font(.system(size: 12, weight: .bold, design: .monospaced))
            .foregroundStyle(Color(red: 0.86, green: 0.31, blue: 0.25))
          Text("Codex 皮肤管理器")
            .font(.system(size: 25, weight: .bold))
          Text("主题控制器与本地注入引擎")
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
        }
        Spacer()
      }
      .padding(30)

      Divider()

      VStack(alignment: .leading, spacing: 20) {
        HStack(spacing: 14) {
          StatusIcon(systemName: "paintpalette.fill", color: .init(red: 0.86, green: 0.31, blue: 0.25))
          StatusIcon(systemName: "bolt.horizontal.fill", color: .init(red: 0.07, green: 0.48, blue: 0.43))
          StatusIcon(systemName: "checkmark.shield.fill", color: .init(red: 0.73, green: 0.50, blue: 0.16))
          Text("主题库 · 一键切换 · 原版恢复")
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.secondary)
        }

        VStack(alignment: .leading, spacing: 7) {
          Text(model.headline).font(.system(size: 19, weight: .semibold))
          Text(model.detail).font(.system(size: 12)).foregroundStyle(.secondary)
          if let error = model.errorDetail {
            ScrollView {
              Text(error)
                .font(.system(size: 10, design: .monospaced))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: 68)
            .padding(10)
            .background(Color.red.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 7))
          }
        }

        if model.isInstalling {
          ProgressView().progressViewStyle(.linear)
        }

        Button(action: model.isInstalled ? model.openManager : model.install) {
          HStack(spacing: 8) {
            if model.isInstalling { ProgressView().controlSize(.small) }
            Image(systemName: model.isInstalled ? "arrow.up.forward.app" : "arrow.down.app.fill")
            Text(model.isInstalled ? "打开皮肤管理器" : "一键安装")
          }
          .font(.system(size: 14, weight: .semibold))
          .foregroundStyle(.white)
          .frame(maxWidth: .infinity)
          .frame(height: 44)
          .background(model.isInstalled ? Color(red: 0.07, green: 0.48, blue: 0.43) : Color(red: 0.075, green: 0.086, blue: 0.092))
          .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .disabled(model.isInstalling)
      }
      .padding(30)
      .frame(maxWidth: .infinity, alignment: .leading)
    }
    .frame(width: 560, height: 420)
    .background(Color(red: 0.965, green: 0.97, blue: 0.968))
    .preferredColorScheme(.light)
    .onAppear {
      if CommandLine.arguments.contains("--automatic-update") {
        model.install()
      }
    }
  }
}

struct StatusIcon: View {
  let systemName: String
  let color: Color

  var body: some View {
    Image(systemName: systemName)
      .font(.system(size: 13, weight: .semibold))
      .foregroundStyle(color)
      .frame(width: 30, height: 30)
      .background(color.opacity(0.11))
      .clipShape(RoundedRectangle(cornerRadius: 7))
  }
}

@main
struct DreamSkinInstallerApp: App {
  var body: some Scene {
    WindowGroup {
      InstallerView()
    }
    .windowStyle(.titleBar)
    .windowToolbarStyle(.unifiedCompact(showsTitle: false))
    .defaultSize(width: 560, height: 420)
    .windowResizability(.contentSize)
    .commands { CommandGroup(replacing: .newItem) { } }
  }
}
