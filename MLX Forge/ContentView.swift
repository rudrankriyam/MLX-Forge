import SwiftUI
import Foundation
import AppKit

enum QuantizationLevel: String, CaseIterable, Identifiable {
    case none = "None"
    case fourBit = "4-bit"
    case eightBit = "8-bit"
    
    var id: String { self.rawValue }
    
    var arguments: [String] {
        switch self {
        case .none:
            return []
        case .fourBit:
            return ["-q", "--q-bits", "4"]
        case .eightBit:
            return ["-q", "--q-bits", "8"]
        }
    }
}

struct ContentView: View {
    @StateObject private var manager = CommandManager()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                if manager.isEnvironmentValid == nil {
                    ProgressView().controlSize(.small)
                    Text(manager.environmentStatusMessage)
                        .font(.footnote)
                        .foregroundColor(.gray)
                } else if manager.isEnvironmentValid == true {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(manager.environmentStatusMessage)
                        .font(.footnote)
                } else {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundColor(.red)
                    Text(manager.environmentStatusMessage)
                        .font(.footnote)
                }
                Spacer()
                if manager.isEnvironmentValid == false {
                    Button("Setup Environment") {
                        manager.setupPythonEnvironment()
                    }
                    .disabled(manager.isSettingUpEnvironment)
                    .padding(.leading, 5)
                }
                
                Button {
                    manager.checkPythonEnvironment()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Re-check Python Environment")
                .disabled(manager.isSettingUpEnvironment)
            }
            .padding(.bottom, 5)
            
            GroupBox("Configuration") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Input Repo ID:")
                        TextField("e.g., mistralai/Mistral-7B-v0.1", text: $manager.inputRepo)
                    }
                    HStack {
                        Text("Output Repo ID:")
                        TextField("Optional: e.g., your-username/Mistral-7B-v0.1-mlx", text: $manager.outputRepo)
                    }
                    Picker("Quantization:", selection: $manager.quantizationLevel) {
                        ForEach(QuantizationLevel.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    HStack {
                        Text("Python Path:")
                        TextField("e.g., /usr/local/bin/python3", text: $manager.pythonPath)
                            .disabled(manager.isRunning || manager.isSettingUpEnvironment)
                    }
                }
                .padding(.vertical, 5)
            }
            
            HStack {
                Button(action: {
                    manager.runConversion(
                        pythonPath: manager.pythonPath,
                        inputRepo: manager.inputRepo,
                        outputRepo: manager.outputRepo,
                        quantizationLevel: manager.quantizationLevel,
                        upload: false
                    )
                }) {
                    HStack {
                        if manager.isRunning {
                            ProgressView().controlSize(.small)
                        }
                        Text(manager.isRunning ? "Working..." : "Convert")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(manager.inputRepo.isEmpty || manager.isRunning || manager.isEnvironmentValid != true || manager.isSettingUpEnvironment)
                .help("Convert the Hugging Face model to MLX format locally.")
                
                Button(action: {
                    manager.runConversion(
                        pythonPath: manager.pythonPath,
                        inputRepo: manager.inputRepo,
                        outputRepo: manager.outputRepo,
                        quantizationLevel: manager.quantizationLevel,
                        upload: true
                    )
                }) {
                    HStack {
                        if manager.isRunning {
                            ProgressView().controlSize(.small)
                        }
                        Text(manager.isRunning ? "Working..." : "Convert and Upload")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(manager.inputRepo.isEmpty || manager.outputRepo.isEmpty || manager.isRunning || manager.isEnvironmentValid != true || manager.isSettingUpEnvironment)
                .help("Convert the model and upload it to the specified Hugging Face repo.")
            }
            
            GroupBox("Logs") {
                TextEditor(text: $manager.outputLog)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 200)
                    .border(Color.gray.opacity(0.5))
            }
            
            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString("pip install mlx mlx-lm", forType: .string)
            } label: {
                Label("Copy install command", systemImage: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Click to copy 'pip install mlx mlx-lm' to clipboard")
            
            Spacer()
        }
        .padding()
        .overlay {
            if manager.isSettingUpEnvironment {
                VStack {
                    ProgressView("Setting up Python environment...")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 5)
                }
            }
        }
        .onAppear {
            manager.checkPythonEnvironment()
        }
    }
}
