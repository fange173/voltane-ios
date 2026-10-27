import Foundation

/// 枚举取值到中文文案的映射，照抄网页版 `state.js`。
public enum Labels {
    public static let energy = ["ice": "燃油", "hev": "油混", "phev": "插混", "erev": "增程", "bev": "纯电"]
    public static let charge: [String: String] = ["home": "家充", "public_ac": "公共慢充", "dc": "快充", "swap": "换电"]
    public static let chargeOrder = ["home", "public_ac", "dc", "swap"]

    /// 旧数据里的「超充」并入「快充」。
    public static func chargeKey(_ t: String?) -> String? { t == "super" ? "dc" : t }
    public static func chargeLabel(_ t: String?) -> String? { chargeKey(t).flatMap { charge[$0] } }
    public static let fuelGrades = ["92", "95", "98", "0", "E92", "E95"]
    public static let snapshotTags: [String: String] = [
        "before_park": "停车前", "after_park": "停车后", "month_start": "月初", "other": "其他",
        "ledger_start": "记账起点", "delivery": "提车",
    ]
    public static let snapshotChoices = ["before_park", "after_park", "month_start", "other"]
    public static let segmentTags: [String: String] = [
        "normal": "正常", "idle": "哨兵/静置", "winter": "冬季/空调", "highway": "高速", "load": "拉货/满载", "abnormal": "异常",
    ]
    public static let segmentTagOrder = ["normal", "idle", "winter", "highway", "load", "abnormal"]
    public static let expense: [String: String] = [
        "insurance": "保险", "maintenance": "保养", "repair": "维修", "inspection": "年检", "tires": "轮胎", "wash": "洗车美容",
        "parking": "停车", "toll": "通行费", "fine": "违章", "accessory": "用品/改装", "loan": "车贷", "other": "其他",
    ]
    public static let expenseOrder = ["insurance", "maintenance", "repair", "inspection", "tires", "wash",
                                      "parking", "toll", "fine", "accessory", "loan", "other"]
    public static let role: [String: String] = ["owner": "车主", "editor": "共同记录", "viewer": "只看"]
    public static let placeKind: [String: String] = [
        "home_charger": "家充桩", "charge_station": "充电站", "gas_station": "加油站", "other": "其他",
    ]
    public static let quality: [String: String] = ["A": "精确", "B": "估", "C": "粗略", "D": "不足"]
    public static let hint: [String: String] = [
        "need_start": "还没有记录：先记一条「状态快照」或一次「加满」作为起点",
        "need_full": "下次加油建议加满，之后油耗就准了",
        "need_second_full": "再加满一次，就能算出第一段准确油耗",
        "need_soc": "充电时填一下开始和结束电量，电耗会更准",
        "need_more": "再多记几次就有结果了",
    ]
    public static let segmentIssue: [String: String] = [
        "missed": "有漏记，未计算", "negative": "数据异常（消耗为负）",
        "incomplete": "期间有汇总补能，不单独计算", "uncertain": "误差太大，不显示",
    ]
    public static let anomaly: [String: String] = ["high": "偏高", "low": "偏低", "parked": "疑似停放耗电", "idle_high": "停车耗电偏高"]

    public static func grade(_ g: String?) -> String {
        guard let g, !g.isEmpty else { return "" }
        return g == "0" ? "0# 柴油" : "\(g)#"
    }
}
