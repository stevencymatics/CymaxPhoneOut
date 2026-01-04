//
//  ContentView.swift
//  CymaxPhoneReceiver
//
//  Main UI for the iOS receiver
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var receiverState: ReceiverState
    @State private var showingLog = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 24) {
                    // Status card
                    statusCard
                    
                    // Stats card
                    if receiverState.isReceiving {
                        statsCard
                    }
                    
                    // Controls
                    controlsSection
                    
                    // Log section
                    if showingLog {
                        logSection
                    }
                    
                    // Instructions
                    instructionsSection
                }
                .padding()
            }
            .navigationTitle("Cymax Receiver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingLog.toggle() }) {
                        Image(systemName: showingLog ? "terminal.fill" : "terminal")
                    }
                }
            }
        }
    }
    
    // MARK: - Log Section
    
    private var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Debug Log")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                Spacer()
                Button("Copy") {
                    UIPasteboard.general.string = receiverState.logMessages.joined(separator: "\n")
                }
                .font(.caption)
            }
            
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 2) {
                    ForEach(receiverState.logMessages.suffix(50), id: \.self) { message in
                        Text(message)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                            .textSelection(.enabled)
                    }
                }
            }
            .frame(height: 150)
            .background(Color(uiColor: .secondarySystemBackground))
            .cornerRadius(8)
        }
        .padding()
        .background(Color(uiColor: .tertiarySystemBackground))
        .cornerRadius(12)
    }
    
    // MARK: - Status Card
    
    private var statusCard: some View {
        VStack(spacing: 16) {
            // Connection indicator
            ZStack {
                Circle()
                    .fill(statusColor.opacity(0.2))
                    .frame(width: 120, height: 120)
                
                Circle()
                    .fill(statusColor)
                    .frame(width: 80, height: 80)
                
                Image(systemName: statusIcon)
                    .font(.system(size: 36))
                    .foregroundColor(.white)
            }
            
            Text(receiverState.connectionState.description)
                .font(.headline)
            
            if receiverState.isReceiving {
                HStack {
                    Text("\(receiverState.sampleRate) Hz")
                    Text("•")
                    Text("\(receiverState.channels) ch")
                }
                .font(.caption)
                .foregroundColor(.secondary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(16)
    }
    
    private var statusColor: Color {
        switch receiverState.connectionState {
        case .idle: return .gray
        case .advertising: return .orange
        case .connected: return .green
        case .error: return .red
        }
    }
    
    private var statusIcon: String {
        switch receiverState.connectionState {
        case .idle: return "antenna.radiowaves.left.and.right.slash"
        case .advertising: return "antenna.radiowaves.left.and.right"
        case .connected: return "checkmark.circle.fill"
        case .error: return "exclamationmark.triangle.fill"
        }
    }
    
    // MARK: - Stats Card
    
    private var statsCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Statistics")
                .font(.subheadline)
                .foregroundColor(.secondary)
            
            HStack(spacing: 20) {
                statItem(
                    title: "Packets",
                    value: formatNumber(receiverState.packetsReceived),
                    color: .blue
                )
                
                statItem(
                    title: "Loss",
                    value: String(format: "%.2f%%", receiverState.lossPercentage),
                    color: receiverState.lossPercentage > 1 ? .red : .green
                )
                
                statItem(
                    title: "Jitter",
                    value: String(format: "%.1fms", receiverState.jitterMs),
                    color: receiverState.jitterMs > 10 ? .orange : .green
                )
                
                statItem(
                    title: "Buffer",
                    value: String(format: "%.1fms", receiverState.bufferLevelMs),
                    color: .purple
                )
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .secondarySystemBackground))
        .cornerRadius(12)
    }
    
    private func statItem(title: String, value: String, color: Color) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
    
    private func formatNumber(_ num: UInt64) -> String {
        if num >= 1_000_000 {
            return String(format: "%.1fM", Double(num) / 1_000_000)
        } else if num >= 1_000 {
            return String(format: "%.1fK", Double(num) / 1_000)
        }
        return "\(num)"
    }
    
    // MARK: - Controls
    
    private var controlsSection: some View {
        VStack(spacing: 16) {
            // Start/Stop button
            Button(action: toggleReceiving) {
                HStack {
                    Image(systemName: isAdvertisingOrConnected ? "stop.fill" : "play.fill")
                    Text(isAdvertisingOrConnected ? "Stop" : "Start Receiving")
                }
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding()
                .background(isAdvertisingOrConnected ? Color.red : Color.blue)
                .foregroundColor(.white)
                .cornerRadius(12)
            }
            
            // Latency mode picker
            if isAdvertisingOrConnected {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Latency Mode")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Picker("Mode", selection: $receiverState.latencyMode) {
                        ForEach(LatencyMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: receiverState.latencyMode) { newValue in
                        receiverState.setLatencyMode(newValue)
                    }
                    
                    Text("Target jitter buffer: \(String(format: "%.0f", receiverState.latencyMode.jitterBufferMs))ms")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemBackground))
                .cornerRadius(12)
            }
        }
    }
    
    private var isAdvertisingOrConnected: Bool {
        switch receiverState.connectionState {
        case .advertising, .connected: return true
        default: return false
        }
    }
    
    private func toggleReceiving() {
        if isAdvertisingOrConnected {
            receiverState.stopAdvertising()
        } else {
            receiverState.startAdvertising()
        }
    }
    
    // MARK: - Instructions
    
    private var instructionsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Setup Instructions")
                .font(.subheadline)
                .fontWeight(.medium)
            
            VStack(alignment: .leading, spacing: 4) {
                instructionRow(1, "Enable Personal Hotspot on this iPhone")
                instructionRow(2, "Connect iPhone to Mac via USB cable")
                instructionRow(3, "Trust this computer if prompted")
                instructionRow(4, "Tap 'Start Receiving' above")
                instructionRow(5, "Select 'Cymax Phone Out (MVP)' in Mac Sound settings")
            }
            .font(.caption)
            .foregroundColor(.secondary)
            
            if isAdvertisingOrConnected {
                Divider()
                    .padding(.vertical, 4)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("iPhone IP Address (for Mac app):")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("172.20.10.1")
                        .font(.system(.caption, design: .monospaced))
                        .fontWeight(.bold)
                        .foregroundColor(.blue)
                    Text("(USB tethering default)")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding()
        .background(Color(uiColor: .tertiarySystemBackground))
        .cornerRadius(12)
    }
    
    private func instructionRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .fontWeight(.medium)
                .frame(width: 20, alignment: .leading)
            Text(text)
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ReceiverState())
}

