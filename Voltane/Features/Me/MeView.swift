import SwiftUI
import VoltaneKit

/// 「我的」：账号、显示、加入车辆、服务器地址与退出；其余入口在后续阶段加入。
struct MeView: View {
    @Environment(AppModel.self) private var app
    @State private var confirmLogoutAll = false

    var body: some View {
        @Bindable var app = app
        List {
            if let u = app.user {
                Section {
                    HStack(spacing: 12) {
                        Text(String(u.name.prefix(1))).font(.title3.bold()).foregroundStyle(.white)
                            .frame(width: 44, height: 44).background(Color(hex: u.color), in: Circle())
                        VStack(alignment: .leading) {
                            Text(u.name).font(.headline)
                            Text("@\(u.username)\(u.isAdmin ? " · 管理员" : "")").font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("显示") {
                Picker("主题", selection: $app.themeName) {
                    Text("跟随系统").tag("auto"); Text("浅色").tag("light"); Text("深色").tag("dark")
                }
                Toggle("地点默认选中最常用的", isOn: Binding(
                    get: { app.user?.settings["place_default"]?.stringValue == "top" },
                    set: { on in Task { await app.savePref("place_default", .string(on ? "top" : "none")) } }))
                Toggle("首页显示「提车至今」卡片", isOn: Binding(
                    get: { app.user?.settings["hide_history"]?.boolValue != true },
                    set: { on in Task { await app.savePref("hide_history", .bool(!on)) } }))
            }
            Section("车辆") {
                NavigationLink { JoinVehicleView() } label: { Label("用邀请码加入车辆", systemImage: "key.fill") }
            }
            Section("服务器") {
                LabeledContent("主地址", value: app.server?.primary.absoluteString ?? "–")
                if let b = app.server?.backup { LabeledContent("备用地址", value: b.absoluteString) }
                if app.server?.primaryIsInsecureRemote == true {
                    Label("明文传输，建议改用 https", systemImage: "exclamationmark.triangle.fill").font(.footnote).foregroundStyle(Color.vWarn)
                }
                if app.outboxCount > 0 {
                    Button("\(app.outboxCount) 条记录待同步，立即重试") { Task { await app.flushOutbox() } }
                }
            }
            Section {
                Button("退出登录", role: .destructive) { Task { await app.logout() } }
                Button("退出所有设备", role: .destructive) { confirmLogoutAll = true }
            }
        }
        .navigationTitle("我的")
        .confirmationDialog("所有设备和浏览器上的登录都会失效", isPresented: $confirmLogoutAll, titleVisibility: .visible) {
            Button("退出所有设备", role: .destructive) { Task { await app.logoutAllDevices() } }
        }
    }
}
