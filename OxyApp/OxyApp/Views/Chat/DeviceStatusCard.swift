import SwiftUI
struct DeviceStatusCard: View {
    var telemetry: PendantTelemetryMonitor

    var body: some View {
        VStack(spacing: 0) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 14) {
                    liveState
                    Spacer(minLength: 8)
                    metrics
                }

                VStack(alignment: .leading, spacing: 9) {
                    liveState
                    metrics
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 11)
        }
    }

    private var liveState: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(telemetry.isStreaming ? Color.appLive : Color.appMuted.opacity(0.5))
                .frame(width: 6, height: 6)
            Text(telemetry.isStreaming ? "Connected" : "Idle")
                .font(.role(.footnote, weight: .medium))
                .foregroundStyle(telemetry.isStreaming ? Color.appInk : Color.appMuted)
                .fixedSize()
        }
    }

    private var metrics: some View {
        HStack(spacing: 12) {
            metric(String(format: "%.0f ms", telemetry.routingLatencyMillis))
            metric("Battery \(telemetry.coreBatteryPercent)%")
        }
    }

    private func metric(_ text: String) -> some View {
        Text(text)
            .font(.reading(.footnote))
            .foregroundStyle(Color.appMuted)
            .fixedSize()
            // Live telemetry rolls its digits instead of popping.
            .contentTransition(.numericText())
            .animation(.appStandard, value: text)
    }
}

#Preview {
    ZStack(alignment: .top) {
        Color.appObsidian.ignoresSafeArea()
        DeviceStatusCard(telemetry: {
            let monitor = PendantTelemetryMonitor()
            monitor.start()
            return monitor
        }())
    }
}
