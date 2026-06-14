import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
    }
}

@main
struct CodexQuotaDesktopApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var viewModel = QuotaDashboardViewModel()

    var body: some Scene {
        Window("Codex 剩余额度", id: "dashboard") {
            ContentView(viewModel: viewModel)
                .frame(minWidth: 760, minHeight: 520)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("Codex Quota", systemImage: "circle.hexagongrid.fill") {
            MenuBarContent(viewModel: viewModel)
        }
    }
}

private struct MenuBarContent: View {
    @Environment(\.openWindow) private var openWindow

    let viewModel: QuotaDashboardViewModel

    var body: some View {
        Button("显示窗口") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "dashboard")
        }

        Button("手动刷新") {
            viewModel.refresh()
        }

        Divider()

        Button("退出") {
            NSApp.terminate(nil)
        }
    }
}
