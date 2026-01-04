//
//  SettingsView.swift
//  CymaxPhoneOutMenubar
//
//  Settings window for audio configuration
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    
    @State private var selectedSampleRate: UInt32 = 48000
    @State private var selectedBufferSize: UInt32 = 256
    
    private let sampleRates: [UInt32] = [44100, 48000]
    private let bufferSizes: [UInt32] = [64, 128, 256, 512]
    
    var body: some View {
        Form {
            Section("Audio Configuration") {
                Picker("Sample Rate", selection: $selectedSampleRate) {
                    ForEach(sampleRates, id: \.self) { rate in
                        Text("\(rate) Hz").tag(rate)
                    }
                }
                .onChange(of: selectedSampleRate) { newValue in
                    appState.sampleRate = newValue
                }
                
                Picker("Buffer Size", selection: $selectedBufferSize) {
                    ForEach(bufferSizes, id: \.self) { size in
                        Text("\(size) frames (\(String(format: "%.1f", Double(size) / 48.0)) ms)")
                            .tag(size)
                    }
                }
                .onChange(of: selectedBufferSize) { newValue in
                    appState.bufferSize = newValue
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("Estimated One-Way Latency")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    let bufferMs = Double(selectedBufferSize) / Double(selectedSampleRate) * 1000.0
                    let networkMs = 2.0
                    let jitterMs = 15.0
                    let outputMs = 5.0
                    let total = bufferMs + networkMs + jitterMs + outputMs
                    
                    VStack(alignment: .leading, spacing: 2) {
                        latencyRow("Buffer", bufferMs)
                        latencyRow("Network (USB)", networkMs)
                        latencyRow("Jitter Buffer", jitterMs)
                        latencyRow("Output", outputMs)
                        Divider()
                        latencyRow("Total", total, bold: true)
                    }
                    .font(.system(size: 11, design: .monospaced))
                }
                .padding(.top, 8)
            }
            
            Section("About") {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cymax Phone Out (MVP)")
                        .font(.headline)
                    Text("Routes system audio to your iPhone over USB tethering.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    
                    Link("Setup Instructions", destination: URL(string: "https://github.com/cymax/phone-audio#setup")!)
                        .font(.caption)
                }
            }
            
            Section("Troubleshooting") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("If the driver doesn't appear:")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Text("""
                    1. Run install_driver.sh
                    2. Restart coreaudiod: sudo launchctl kickstart -k system/com.apple.audio.coreaudiod
                    3. Check System Settings > Sound > Output
                    """)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text("If no devices appear:")
                        .font(.caption)
                        .fontWeight(.medium)
                    
                    Text("""
                    1. Enable Personal Hotspot on iPhone
                    2. Connect iPhone via USB cable
                    3. Trust this computer on iPhone
                    4. Ensure iOS app is running
                    """)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 400, height: 500)
        .onAppear {
            selectedSampleRate = appState.sampleRate
            selectedBufferSize = appState.bufferSize
        }
    }
    
    private func latencyRow(_ label: String, _ value: Double, bold: Bool = false) -> some View {
        HStack {
            Text(label)
                .fontWeight(bold ? .semibold : .regular)
            Spacer()
            Text(String(format: "%.1f ms", value))
                .fontWeight(bold ? .semibold : .regular)
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}

