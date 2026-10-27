import SwiftUI
import VoltaneKit

/// 登录流程：先填服务器地址并检查连通性，地址通了再填用户名和密码。
struct LoginView: View {
    @Environment(AppModel.self) private var app
    @State private var address = ""
    @State private var backup = ""
    @State private var showBackup = false
    @State private var checked: (url: URL, health: Health)?
    @State private var username = ""
    @State private var password = ""
    @State private var inviteCode = ""
    @State private var displayName = ""
    @State private var error: String?
    @State private var busy = false
    @State private var mode: Mode = .login
    @FocusState private var focus: Field?

    private enum Mode { case login, join }
    private enum Field { case address, backup, user, password, code, name }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                serverCard
                if checked != nil { accountCard }
                if let error { Text(error).font(.footnote).foregroundStyle(Color.vDanger).multilineTextAlignment(.center) }
            }
            .padding(20)
            .frame(maxWidth: 520)
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .task {
            if address.isEmpty, let s = app.server {
                address = s.primary.absoluteString
                backup = s.backup?.absoluteString ?? ""
                showBackup = s.backup != nil
                username = app.settings.lastUsername
                await check()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Image(systemName: "bolt.car.fill").font(.system(size: 44)).foregroundStyle(Color.vBrand)
            Text("油电簿").font(.largeTitle.bold())
            Text("一车两能，一本算清").font(.subheadline).foregroundStyle(.secondary)
        }
        .padding(.top, 36)
        .accessibilityElement(children: .combine)
    }

    private var serverCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Text("服务器地址").font(.headline)
                TextField("例如 192.168.1.5:8000 或 https://car.example.com", text: $address)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                    .focused($focus, equals: .address).submitLabel(.go).onSubmit { Task { await check() } }
                    .padding(12).background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                if showBackup {
                    TextField("备用地址（可选，主地址连不上时自动切换）", text: $backup)
                        .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                        .focused($focus, equals: .backup)
                        .padding(12).background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                } else {
                    Button("添加备用地址") { showBackup = true }.font(.footnote)
                }
                if let c = checked {
                    Label("已连接 · 服务端 \(c.health.version)", systemImage: "checkmark.circle.fill")
                        .font(.footnote).foregroundStyle(Color.vOk)
                    if let v = c.health.apiVersion, v != APIClient.apiVersion {
                        Label(v > APIClient.apiVersion ? "服务端比 App 新，请更新 App" : "请更新服务端", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(Color.vWarn)
                    } else if c.health.apiVersion == nil {
                        Label("服务端版本较旧，请先升级服务端", systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote).foregroundStyle(Color.vWarn)
                    }
                    if let url = ServerConfig.normalize(address), ServerConfig(primary: url).primaryIsInsecureRemote {
                        Label("当前是明文 http 地址，建议改用 https", systemImage: "lock.open.fill").font(.footnote).foregroundStyle(Color.vWarn)
                    }
                } else {
                    Button { Task { await check() } } label: {
                        HStack { if busy { ProgressView() }; Text("检查连接") }.frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.vGlassProminent).disabled(busy || address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private var accountCard: some View {
        Card {
            VStack(alignment: .leading, spacing: 12) {
                Picker("", selection: $mode) { Text("登录").tag(Mode.login); Text("邀请码注册").tag(Mode.join) }.pickerStyle(.segmented)
                if mode == .join {
                    field("邀请码", text: $inviteCode, id: .code).textInputAutocapitalization(.characters).keyboardType(.asciiCapable)
                    field("昵称（可选）", text: $displayName, id: .name)
                }
                field("用户名", text: $username, id: .user).textContentType(.username).textInputAutocapitalization(.never)
                SecureField("密码", text: $password)
                    .textContentType(mode == .login ? .password : .newPassword).focused($focus, equals: .password)
                    .padding(12).background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .submitLabel(.go).onSubmit { Task { await submit() } }
                Button { Task { await submit() } } label: {
                    HStack { if busy { ProgressView() }; Text(mode == .login ? "登录" : "注册并加入") }.frame(maxWidth: .infinity)
                }
                .buttonStyle(.vGlassProminent).disabled(busy || username.isEmpty || password.isEmpty || (mode == .join && inviteCode.isEmpty))
                Button("修改服务器地址") { checked = nil; error = nil }.font(.footnote)
            }
        }
    }

    private func field(_ title: String, text: Binding<String>, id: Field) -> some View {
        TextField(title, text: text).autocorrectionDisabled().focused($focus, equals: id)
            .padding(12).background(Color(.tertiarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func check() async {
        error = nil
        guard !address.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        busy = true
        defer { busy = false }
        do {
            let r = try await app.checkServer(address)
            if !backup.trimmingCharacters(in: .whitespaces).isEmpty, ServerConfig.normalize(backup) == nil {
                error = "备用地址不正确"
                return
            }
            checked = r
            address = r.0.absoluteString
            focus = username.isEmpty ? .user : .password
        } catch let e as APIError {
            checked = nil
            error = e.isNetwork ? "连不上服务器，请检查地址和网络（局域网地址需要在同一个 Wi-Fi）" : e.message
        } catch {
            checked = nil
            self.error = error.localizedDescription
        }
    }

    private func submit() async {
        guard let c = checked else { return }
        error = nil
        busy = true
        defer { busy = false }
        let config = ServerConfig(primary: c.url, backup: ServerConfig.normalize(backup))
        do {
            if mode == .login {
                try await app.login(config: config, username: username.trimmingCharacters(in: .whitespaces), password: password)
            } else {
                try await app.signup(config: config, code: inviteCode.trimmingCharacters(in: .whitespaces).uppercased(),
                                     username: username.trimmingCharacters(in: .whitespaces), password: password, displayName: displayName)
            }
            password = ""
        } catch let e as APIError {
            error = e.message
        } catch {
            self.error = error.localizedDescription
        }
    }
}
