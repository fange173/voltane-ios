import SwiftUI

/// 小问号：点按弹出说明文字，对应网页版 ui.js 的 helpTip。
struct HelpTip: View {
    let text: String
    @State private var shown = false

    var body: some View {
        Button { shown = true } label: {
            Image(systemName: "questionmark.circle").font(.caption).foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("说明")
        .popover(isPresented: $shown) {
            Text(text).font(.footnote).fixedSize(horizontal: false, vertical: true)
                .padding(14).frame(idealWidth: 280)
                .presentationCompactAdaptation(.popover)
        }
    }
}

/// 页面上复用的说明文字，与网页版一致。
enum HelpText {
    static let equiv = "油和电取同一区间：油耗 + 电耗 ÷ 8.9（1 L 汽油约等于 8.9 kWh 电）就是折合油耗，能直接和燃油车比较。"
    static let costPerKm = "花费 ÷ 里程。保险按保险期间（没填就按一年）按天摊销，只算落在这段时间里的部分；「总花费」仍按实际付款计。"
    static let idle = "停着时掉的电（哨兵、空调、自放电）。标成「哨兵/静置」但这段有行驶里程时，按你平时的行驶电耗估出行驶部分，剩下的才算静置。"
}
