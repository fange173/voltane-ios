import SwiftUI
import VoltaneKit

/// 根视图：未登录显示登录流程，登录后按系统版本选择标签栏实现。
struct RootView: View {
    @Environment(AppModel.self) private var app
    @State private var toastWindow = ToastWindowController()

    var body: some View {
        Group {
            switch app.phase {
            case .launching:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .needsLogin:
                LoginView()
            case .ready:
                if #available(iOS 18, *) { ModernTabRoot() } else { LegacyTabRoot() }
            }
        }
        .onAppear { toastWindow.install(app: app) }
        .task { await app.bootstrap() }
    }
}

/// iOS 18 及以上：新的 Tab 写法。
@available(iOS 18, *)
struct ModernTabRoot: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.tab) {
            Tab("概览", systemImage: "house.fill", value: AppTab.home) { TabContent { HomeView() } }
            Tab("记录", systemImage: "list.bullet", value: AppTab.records) { TabContent { RecordsView() } }
            Tab(value: AppTab.add) { Color.clear } label: { AddTabIcon() }
            Tab("统计", systemImage: "chart.bar.xaxis", value: AppTab.stats) { TabContent { StatsPlaceholderView() } }
            Tab("我的", systemImage: "person.crop.circle", value: AppTab.me) { TabContent(path: $app.mePath) { MeView() } }
        }
        .vTabBarFixed()
        .modifier(AddTabIntercept())
        .modifier(SheetRouter())
    }
}

/// 中间的「＋」不是真正的页面：点它时回到原来的标签并弹出记录菜单。
struct AddTabIntercept: ViewModifier {
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        content.onChange(of: app.tab) { old, new in
            guard new == .add else { return }
            app.tab = old
            app.sheet = .addMenu
        }
    }
}

/// iOS 17：旧的 tabItem 写法。
struct LegacyTabRoot: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        TabView(selection: $app.tab) {
            TabContent { HomeView() }.tabItem { Label("概览", systemImage: "house.fill") }.tag(AppTab.home)
            TabContent { RecordsView() }.tabItem { Label("记录", systemImage: "list.bullet") }.tag(AppTab.records)
            Color.clear.tabItem { AddTabIcon() }.tag(AppTab.add)
            TabContent { StatsPlaceholderView() }.tabItem { Label("统计", systemImage: "chart.bar.xaxis") }.tag(AppTab.stats)
            TabContent(path: $app.mePath) { MeView() }.tabItem { Label("我的", systemImage: "person.crop.circle") }.tag(AppTab.me)
        }
        .modifier(AddTabIntercept())
        .modifier(SheetRouter())
    }
}

/// 每个标签页的外壳：导航栈、车辆切换器、提醒铃铛。传入 `path` 时导航栈由 AppModel 控制。
struct TabContent<Content: View>: View {
    var path: Binding<[MeRoute]>?
    @ViewBuilder var content: Content

    var body: some View {
        if let path {
            NavigationStack(path: path) { root }
        } else {
            NavigationStack { root }
        }
    }

    private var root: some View {
        content
            .toolbar { ToolbarItem(placement: .topBarLeading) { VehicleSwitcher() }
                ToolbarItem(placement: .topBarTrailing) { BellButton() } }
            .navigationBarTitleDisplayMode(.inline)
    }
}

struct SheetRouter: ViewModifier {
    @Environment(AppModel.self) private var app

    func body(content: Content) -> some View {
        @Bindable var app = app
        content
            .alert("顺手完成提醒？", isPresented: Binding(get: { !app.pendingReminderCompletions.isEmpty }, set: { if !$0, !app.pendingReminderCompletions.isEmpty { app.pendingReminderCompletions.removeFirst() } }),
                   presenting: app.pendingReminderCompletions.first) { item in
                Button("完成并顺延") { Task { await complete(item) } }
                Button("暂不", role: .cancel) {}
            } message: { item in
                Text("要把「\(item.reminder.title)」标记为已完成，并按本次日期和里程顺延吗？")
            }
            .sheet(item: $app.sheet) { sheet in
            SheetContent(sheet: sheet)
                .presentationDetents(sheet.isMenu ? [.medium] : [.large])
                .presentationDragIndicator(.visible)
                .environment(app)
        }
    }

    private func complete(_ item: ReminderCompletion) async {
        struct Body: Encodable { var doneAt: String; var odometerKm: Double? }
        do {
            let ep = try Endpoint<OKResponse>(.post, "/api/reminders/\(item.reminder.id)/complete", json: Body(doneAt: item.doneAt.dateOnly, odometerKm: item.odometer))
            _ = try await app.client.send(ep)
            app.toasts.show("「\(item.reminder.title)」已顺延")
            app.bump()
            await app.refreshDueCount()
        } catch { app.toasts.error(error) }
    }
}

struct BellButton: View {
    @Environment(AppModel.self) private var app
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "bell.fill")
                .overlay(alignment: .topTrailing) {
                    if app.dueCount > 0 {
                        Text(app.dueCount > 9 ? "9+" : "\(app.dueCount)")
                            .font(.system(size: 10, weight: .bold)).foregroundStyle(.white)
                            .padding(.horizontal, 4).background(Color.vDanger, in: Capsule())
                            .offset(x: 8, y: -6)
                    }
                }
        }
        .accessibilityLabel(app.dueCount > 0 ? "提醒，\(app.dueCount) 条待办" : "提醒")
        .sheet(isPresented: $showing) {
            NavigationStack { ComingSoonView(title: "提醒", systemImage: "bell.fill", text: "提醒列表在下一阶段加入。") }
                .presentationDetents([.medium, .large])
        }
    }
}

struct ComingSoonView: View {
    let title: String
    let systemImage: String
    let text: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(text))
            .navigationTitle(title)
    }
}

struct StatsPlaceholderView: View {
    var body: some View {
        ComingSoonView(title: "统计", systemImage: "chart.bar.xaxis", text: "能耗、花费、里程和日历统计在下一阶段加入。")
    }
}

/// 标签栏中间的「＋」：只有图标，始终用强调色（原色渲染，不随选中状态变灰）。
struct AddTabIcon: View {
    var body: some View {
        let ui = UIImage(systemName: "plus.circle.fill", withConfiguration: UIImage.SymbolConfiguration(pointSize: 30, weight: .semibold))?
            .withTintColor(UIColor(named: "Brand") ?? .systemIndigo, renderingMode: .alwaysOriginal)
        Group {
            if let ui { Image(uiImage: ui) } else { Image(systemName: "plus.circle.fill") }
        }
        .accessibilityLabel("记一笔")
    }
}
