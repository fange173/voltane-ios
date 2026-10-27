import SwiftUI
import VoltaneKit

/// 页面加载统一入口：加载中、有缓存、离线、出错、空数据都在这里处理，页面只写有数据时的界面。
struct RemoteContent<T: Decodable & Sendable, Content: View>: View {
    @Environment(AppModel.self) private var app
    let endpoint: Endpoint<T>
    var emptyCheck: ((T) -> Bool)?
    @ViewBuilder var content: (T) -> Content

    private enum Phase {
        case loading
        case loaded(T, updatedAt: Date, offline: Bool)
        case failed(APIError)
    }

    @State private var phase: Phase = .loading

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            case .loaded(let value, let at, let offline):
                content(value)
                    .safeAreaInset(edge: .top, spacing: 0) { if offline { OfflineBanner(updatedAt: at) } }
            case .failed(let err):
                ContentUnavailableView {
                    Label("加载失败", systemImage: "wifi.exclamationmark")
                } description: {
                    Text(err.message)
                } actions: {
                    Button("重试") { Task { await load(showSpinner: true) } }.buttonStyle(.vGlass)
                }
            }
        }
        .task(id: app.dataVersion) { await load(showSpinner: false) }
        .refreshable { await load(showSpinner: false) }
    }

    private func load(showSpinner: Bool) async {
        if showSpinner { phase = .loading }
        var hasContent = false
        if case .loaded = phase { hasContent = true }
        if !hasContent, let cached = await app.repository.cached(endpoint) {
            phase = .loaded(cached.value, updatedAt: cached.updatedAt, offline: false)
            hasContent = true
        }
        do {
            let fresh = try await app.repository.fetch(endpoint)
            phase = .loaded(fresh.value, updatedAt: fresh.updatedAt, offline: false)
        } catch is CancellationError {
            return
        } catch let e as APIError {
            if hasContent || cachedPhase { markOffline(); return }
            phase = .failed(e)
        } catch {
            if !hasContent { phase = .failed(APIError.network()) }
        }
    }

    private var cachedPhase: Bool { if case .loaded = phase { true } else { false } }

    private func markOffline() {
        if case .loaded(let v, let at, _) = phase { phase = .loaded(v, updatedAt: at, offline: true) }
    }
}

struct OfflineBanner: View {
    let updatedAt: Date

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "icloud.slash")
            Text("离线 · 更新于 \(updatedAt.formatted(date: .omitted, time: .shortened))")
        }
        .font(.footnote)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
        .background(Color.vWarnSoft)
        .foregroundStyle(Color.vWarn)
        .accessibilityElement(children: .combine)
    }
}
