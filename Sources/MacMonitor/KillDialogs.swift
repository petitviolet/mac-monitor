import MacMonitorCore
import SwiftUI

extension KillOutcome {
    /// UIへ表示する文言。nilは知らせることがないことを表す。
    var message: String? {
        switch self {
        case .sent:
            return nil
        case .protected:
            return "PID 0、PID 1、MacMonitor自身には送れません"
        case .pidReused:
            return "同じPIDが別のプロセスに再利用されたため、シグナルを送りませんでした"
        case .permissionDenied:
            return "権限がありません"
        case .alreadyExited:
            return "プロセスはすでに終了しています"
        case .failed(let code):
            return "シグナルを送れませんでした(errno \(code))"
        case .targetChanged(let listed, let current):
            return "プロセス名が「\(listed)」から「\(current)」に変わったため、確認を中止しました"
        }
    }
}

struct KillConfirmation: ViewModifier {
    @Bindable var model: AppModel

    func body(content: Content) -> some View {
        content.alert(
            "プロセスにシグナルを送りますか",
            isPresented: Binding(
                get: { model.pendingKill != nil },
                set: { if !$0 { model.pendingKill = nil } }
            ),
            presenting: model.pendingKill
        ) { ticket in
            Button("終了(SIGTERM)") { model.confirmKill(ticket, signal: .terminate) }
            Button("強制終了(SIGKILL)", role: .destructive) { model.confirmKill(ticket, signal: .forceKill) }
            Button("キャンセル", role: .cancel) {}
        } message: { ticket in
            Text("\(ticket.name)(PID \(String(ticket.pid)))")
        }
    }
}

/// 結果を確認ダイアログの直後に別のalertで出すと、閉じる途中の表示と重なって出ない場合がある。
/// ウィンドウ内の帯なら表示の順序に左右されない。
struct KillResultBanner: View {
    let message: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .accessibilityHidden(true)
            Text(message)
                .textSelection(.enabled)
            Spacer()
            Button("閉じる", action: onClose)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
