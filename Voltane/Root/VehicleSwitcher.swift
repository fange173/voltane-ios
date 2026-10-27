import SwiftUI
import VoltaneKit

struct VehicleDot: View {
    let vehicle: Vehicle
    var size: CGFloat = 22

    var body: some View {
        Image(systemName: vehicle.energyType == "bev" ? "bolt.fill" : (vehicle.energyType == "ice" || vehicle.energyType == "hev") ? "fuelpump.fill" : "car.fill")
            .font(.system(size: size * 0.5, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Color(hex: vehicle.color), in: Circle())
            .accessibilityHidden(true)
    }
}

/// 导航栏左侧的车辆切换器：色点加车名，菜单列出所有车辆。
struct VehicleSwitcher: View {
    @Environment(AppModel.self) private var app
    @State private var showManage = false

    var body: some View {
        Menu {
            ForEach(app.vehicles) { v in
                Button {
                    app.selectVehicle(v.id)
                } label: {
                    if v.id == app.currentVehicleId { Label(v.name + (v.isArchived ? "（已归档）" : ""), systemImage: "checkmark") }
                    else { Text(v.name + (v.isArchived ? "（已归档）" : "")) }
                }
            }
            Divider()
            Button("管理车辆", systemImage: "car.2.fill") { showManage = true }
        } label: {
            HStack(spacing: 6) {
                if let v = app.currentVehicle {
                    VehicleDot(vehicle: v, size: 20)
                    Text(v.name).font(.headline).lineLimit(1)
                } else {
                    Image(systemName: "car.fill")
                    Text("添加车辆").font(.headline)
                }
                Image(systemName: "chevron.down").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
            }
        }
        .accessibilityLabel("当前车辆：\(app.currentVehicle?.name ?? "无")，切换车辆")
        .sheet(isPresented: $showManage) {
            NavigationStack { ComingSoonView(title: "车辆", systemImage: "car.fill", text: "车辆管理和新车向导在后续阶段加入。") }
                .presentationDetents([.medium, .large])
        }
    }
}
