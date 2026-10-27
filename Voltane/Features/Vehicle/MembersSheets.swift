import SwiftUI
import VoltaneKit

private let roleDetail = [
    "owner": "可以管理成员、删除车辆",
    "editor": "可以记录和编辑，只能删除自己记的",
    "viewer": "只能查看",
]

/// 邀请成员：邀请码 / 链接，或按用户名直接添加。
struct InviteSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle

    private enum Mode: Hashable { case code, user }

    @State private var mode = Mode.code
    @State private var role = "editor"
    @State private var days: Int? = 7
    @State private var uses: Int? = 1
    @State private var allowSignup = false
    @State private var username = ""
    @State private var error: String?
    @State private var busy = false
    @State private var created: Invite?

    private static let dayOptions: [(Int?, String)] = [(1, "1 天"), (7, "7 天"), (30, "30 天"), (nil, "长期")]
    private static let useOptions: [(Int?, String)] = [(1, "1 次"), (5, "5 次"), (nil, "不限")]
    private static let roles = ["owner", "editor", "viewer"]

    var body: some View {
        NavigationStack {
            Group {
                if let created { result(created) } else { form }
            }
            .navigationTitle(created == nil ? "邀请成员" : "邀请码已生成")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(created == nil ? "取消" : "完成") { dismiss() } }
                if created == nil {
                    ToolbarItem(placement: .confirmationAction) {
                        if busy { ProgressView() } else {
                            Button("确定") { Task { await submit() } }
                                .disabled(mode == .user && username.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                    }
                }
            }
        }
        .presentationDetents([.large])
    }

    private var form: some View {
        Form {
            Section {
                Picker("方式", selection: $mode) { Text("邀请码 / 链接").tag(Mode.code); Text("按用户名添加").tag(Mode.user) }
                    .pickerStyle(.segmented).listRowInsets(EdgeInsets()).listRowBackground(Color.clear)
            }
            Section("角色") {
                ForEach(Self.roles, id: \.self) { k in
                    RadioRow(title: Labels.role[k] ?? k, detail: roleDetail[k], selected: role == k) { role = k }
                }
            }
            if mode == .code {
                Section("有效期") {
                    Picker("有效期", selection: $days) { ForEach(Self.dayOptions, id: \.1) { Text($0.1).tag($0.0) } }
                        .pickerStyle(.segmented).labelsHidden()
                }
                Section {
                    Picker("可用次数", selection: $uses) { ForEach(Self.useOptions, id: \.1) { Text($0.1).tag($0.0) } }
                        .pickerStyle(.segmented).labelsHidden()
                } header: { Text("可用次数") } footer: {
                    if days == nil || uses == nil {
                        Text("长期有效的邀请码在你作废前一直可用，不限次数的可以发给多位家人共用；不需要了就在成员列表里作废。")
                    }
                }
                Section {
                    Toggle("允许对方用链接自己注册账号", isOn: $allowSignup)
                } footer: { Text("需要管理员在后台打开「允许邀请注册」") }
            } else {
                Section {
                    TextField("对方的用户名", text: $username)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.asciiCapable)
                } header: { Text("对方的用户名") } footer: { Text("账号由管理员创建") }
            }
            FormErrorSection(message: error)
        }
    }

    private func result(_ inv: Invite) -> some View {
        let text = inv.shareText(server: app.server?.primary)
        return Form {
            Section {
                VStack(spacing: 8) {
                    Text(inv.code).font(.system(.largeTitle, design: .monospaced, weight: .bold)).textSelection(.enabled)
                    Text(inv.metaText).font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 8)
            }
            Section {
                ShareLink(item: text) { Label("分享邀请链接", systemImage: "square.and.arrow.up") }
                Button { UIPasteboard.general.string = text; app.toasts.show("邀请链接已复制", sub: inv.code) } label: {
                    Label("复制邀请文字", systemImage: "doc.on.doc")
                }
            } footer: { Text(text) }
        }
    }

    private func submit() async {
        busy = true
        defer { busy = false }
        error = nil
        do {
            if mode == .user {
                _ = try await app.client.send(try API.addMember(vehicleId: vehicle.id, username: username.trimmingCharacters(in: .whitespaces), role: role))
                app.toasts.show("已添加成员")
                app.bump()
                dismiss()
            } else {
                created = try await app.client.send(try API.createInvite(vehicleId: vehicle.id, InviteBody(role: role, days: days, maxUses: uses, allowSignup: allowSignup)))
                app.bump()
            }
        } catch { self.error = error.localizedDescription }
    }
}

/// 车主改成员角色或移出。
struct RoleSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    let vehicle: Vehicle
    let member: Member
    let hasInvites: Bool
    @State private var confirmRemove = false
    @State private var busy = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(["owner", "editor", "viewer"], id: \.self) { k in
                        RadioRow(title: Labels.role[k] ?? k, detail: roleDetail[k], selected: member.role == k) { Task { await setRole(k) } }
                    }
                }
                Section {
                    Button("移出这辆车", systemImage: "person.fill.xmark", role: .destructive) { confirmRemove = true }
                }
            }
            .disabled(busy)
            .navigationTitle(member.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭") { dismiss() } } }
            .confirmationDialog("移出成员？", isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("移出", role: .destructive) { Task { await remove() } }
            } message: {
                Text("移出后 \(member.name) 将看不到这辆车，已记的记录会保留。" + (hasInvites ? "对方如果还拿着有效的邀请码，可以重新加入，需要的话一并作废。" : ""))
            }
        }
        .presentationDetents([.medium])
    }

    private func setRole(_ role: String) async {
        guard role != member.role else { dismiss(); return }
        busy = true
        defer { busy = false }
        do {
            _ = try await app.client.send(try API.setMemberRole(vehicleId: vehicle.id, userId: member.id, role: role))
            app.bump()
            dismiss()
        } catch { app.toasts.error(error) }
    }

    private func remove() async {
        busy = true
        defer { busy = false }
        do {
            _ = try await app.client.send(API.removeMember(vehicleId: vehicle.id, userId: member.id))
            app.bump()
            dismiss()
        } catch { app.toasts.error(error) }
    }
}
