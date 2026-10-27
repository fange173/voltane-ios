import SwiftUI
import VoltaneKit

/// 底部弹出页面的分发。
struct SheetContent: View {
    let sheet: ActiveSheet

    var body: some View {
        switch sheet {
        case .record(let kind, let vid):
            RecordFormView(mode: .create(kind: kind, vehicleId: vid))
        case .editRecord(let r, let finish):
            RecordFormView(mode: .edit(r, finish: finish))
        case .expense(let vid):
            ExpenseFormView(mode: .create(vehicleId: vid))
        case .editExpense(let e):
            ExpenseFormView(mode: .edit(e))
        case .recordDetail(let id, let isExpense):
            NavigationStack { RecordDetailView(id: id, isExpense: isExpense) }
        case .outbox(let vid):
            NavigationStack { OutboxView(vehicleId: vid) }
        case .addMenu:
            AddMenuSheet()
        case .pendingEdit(let item):
            PendingEditView(item: item)
        }
    }
}
