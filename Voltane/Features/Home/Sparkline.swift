import Charts
import SwiftUI
import VoltaneKit

/// 概览里的小折线：最近 10 段趋势，质量不是 A 的点画成空心。
struct Sparkline: View {
    let points: [SparkPoint]
    let tone: Tone

    var body: some View {
        let data = points.enumerated().compactMap { i, p in p.per100.map { (i, $0, p.quality != "A") } }
        if data.count > 1 {
            Chart {
                ForEach(data, id: \.0) { i, v, hollow in
                    LineMark(x: .value("序号", i), y: .value("数值", v))
                        .foregroundStyle(tone.color).interpolationMethod(.monotone)
                    AreaMark(x: .value("序号", i), y: .value("数值", v))
                        .foregroundStyle(LinearGradient(colors: [tone.color.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom))
                        .interpolationMethod(.monotone)
                    if hollow || i == data.last?.0 {
                        PointMark(x: .value("序号", i), y: .value("数值", v))
                            .symbolSize(i == data.last?.0 ? 40 : 24)
                            .foregroundStyle(i == data.last?.0 ? tone.color : Color(.secondarySystemGroupedBackground))
                    }
                }
            }
            .chartXAxis(.hidden).chartYAxis(.hidden)
            .chartYScale(domain: .automatic(includesZero: false))
            .frame(width: 120, height: 36)
            .accessibilityHidden(true)
        }
    }
}
