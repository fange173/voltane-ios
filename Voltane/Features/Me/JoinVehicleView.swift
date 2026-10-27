import SwiftUI
import VoltaneKit

/// 用邀请码加入车辆，对应网页版「我的 → 用邀请码加入车辆」。
struct JoinVehicleView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var code = ""
    @State private var preview: InvitePreview?
    @State private var error: String?
    @State private var busy = false
    @FocusState private var focused: Bool

    private var normalized: String { String(code.uppercased().filter { $0.isASCII && ($0.isLetter || $0.isNumber) }) }

    var body: some View {
        Form {
            Section {
                TextField("8 位邀请码", text: $code)
                    .font(.title3.monospaced()).textInputAutocapitalization(.characters).autocorrectionDisabled()
                    .keyboardType(.asciiCapable).focused($focused)
            } footer: {
                Text("让车主在「车辆 → 成员 → 邀请」里生成邀请码，加入后可以一起记录和查看。")
            }
            if let p = preview {
                Section {
                    Label {
                        Text("\(p.inviter) 邀请你以「\(p.roleLabel)」加入「\(p.vehicleName)」")
                    } icon: { Image(systemName: "car.fill").foregroundStyle(Color.vBrand) }
                }
            } else if let error {
                Section { Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(Color.vWarn) }
            }
            Section {
                Button {
                    Task { await join() }
                } label: {
                    HStack { Spacer(); if busy { ProgressView() } else { Text("加入").bold() }; Spacer() }
                }
                .disabled(preview == nil || busy)
            }
        }
        .navigationTitle("加入车辆")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { focused = true }
        .task(id: normalized) { await loadPreview() }
    }

    private func loadPreview() async {
        preview = nil
        error = nil
        guard normalized.count >= 8 else { return }
        try? await Task.sleep(for: .milliseconds(250))
        guard !Task.isCancelled else { return }
        do { preview = try await app.client.send(API.previewInvite(code: normalized)) }
        catch let e as APIError { error = e.message }
        catch {}
    }

    private func join() async {
        busy = true
        defer { busy = false }
        do {
            let r = try await app.client.send(API.acceptInvite(code: normalized))
            await app.loadVehicles()
            app.selectVehicle(r.vehicleId)
            app.toasts.show(r.already == true ? "你已经是这辆车的成员" : "已加入「\(preview?.vehicleName ?? "")」")
            app.finishPushed(.join, dismiss: dismiss)
        } catch { app.toasts.error(error) }
    }
}
