import SwiftUI

/// 颜色语义固定：油是琥珀色，电是青绿色，费用是紫色，快照和静置是灰蓝色。值来自 Asset Catalog，浅色深色各一套。
extension Color {
    static let vBrand = Color("Brand")
    static let vBrandSoft = Color("BrandSoft")
    static let vFuel = Color("Fuel")
    static let vFuelStrong = Color("FuelStrong")
    static let vFuelSoft = Color("FuelSoft")
    static let vElec = Color("Elec")
    static let vElecStrong = Color("ElecStrong")
    static let vElecSoft = Color("ElecSoft")
    static let vExpense = Color("Expense")
    static let vExpenseSoft = Color("ExpenseSoft")
    static let vSnapshot = Color("Snapshot")
    static let vSnapshotSoft = Color("SnapshotSoft")
    static let vOk = Color("Ok")
    static let vOkSoft = Color("OkSoft")
    static let vWarn = Color("Warn")
    static let vWarnSoft = Color("WarnSoft")
    static let vDanger = Color("Danger")
    static let vDangerSoft = Color("DangerSoft")

    static func quality(_ q: String?) -> Color {
        switch q {
        case "A": Color("QualityA")
        case "B": Color("QualityB")
        case "C": Color("QualityC")
        default: Color("QualityD")
        }
    }

    /// 车辆色点，取车辆自己的颜色。
    init(hex: String?) {
        let h = (hex ?? "#4F46E5").trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        var v: UInt64 = 0
        Scanner(string: h).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }
}

enum Tone {
    case fuel, elec, expense, snapshot, brand

    var color: Color {
        switch self { case .fuel: .vFuel; case .elec: .vElec; case .expense: .vExpense; case .snapshot: .vSnapshot; case .brand: .vBrand }
    }

    var soft: Color {
        switch self { case .fuel: .vFuelSoft; case .elec: .vElecSoft; case .expense: .vExpenseSoft; case .snapshot: .vSnapshotSoft; case .brand: .vBrandSoft }
    }

    /// 文字用的加深色，保证浅色模式下对比度。
    var text: Color {
        switch self { case .fuel: .vFuelStrong; case .elec: .vElecStrong; default: color }
    }
}
