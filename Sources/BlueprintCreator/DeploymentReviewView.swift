import SwiftUI

struct DeploymentReviewView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 20) {
            Text("Create Blueprint").font(.largeTitle.bold())
            Text("The adaptive plan must be ready before any Platform request is sent.")
                .foregroundStyle(.secondary)

            GroupBox("Conversion Plan") {
                Text(model.conversionPlanSummary)
                    .font(.caption.monospaced())
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }

            Picker("Platform device group", selection: $model.selectedGroup) {
                Text("Select a compatible Platform group").tag(DeviceGroup?.none)
                ForEach(model.groups) { group in
                    Text(group.family == .unknown ? "\(group.name) (Unknown type)" : group.name)
                        .tag(Optional(group))
                }
            }
            .onChange(of: model.selectedGroup) { _ in model.generate() }

            VStack(spacing: 12) {
                primary("Create Blueprint Only", "plus.circle.fill") {
                    Task { await model.performDeployment(.createOnly) }
                }
                primary("Create and Distribute Blueprint", "paperplane.fill") {
                    Task { await model.performDeployment(.createAndDistribute) }
                }
                primary("Create and Distribute Blueprint and Unscope Configuration Profile", "arrow.triangle.2.circlepath.circle.fill") {
                    model.requestCreateDistributeAndUnscope()
                }
            }
            .frame(width: 560)

            HStack { Spacer(); Button("Cancel") { dismiss() } }
        }
        .padding(28)
        .frame(width: 780, height: 650)
    }

    private func primary(_ title: String, _ icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).frame(maxWidth: .infinity).padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .tint(.blue)
        .disabled(!model.conversionReady || model.selectedGroup == nil || model.busy)
    }
}
