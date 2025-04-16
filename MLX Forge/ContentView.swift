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
    @State private var inputRepo = ""
    @State private var outputRepo = ""
    @State private var quantizationLevel: QuantizationLevel = .fourBit
    @State private var outputLog = "Process output will appear here..."
    @State private var isRunning = false
    @State private var pythonPath = "/usr/local/bin/python3"
    @State private var isEnvironmentValid: Bool? = nil
    @State private var environmentStatusMessage = "Checking Python environment..."
    @State private var isSettingUpEnvironment = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            HStack {
                if isEnvironmentValid == nil {
                    ProgressView().controlSize(.small)
                    Text(environmentStatusMessage)
                        .font(.footnote)
                        .foregroundColor(.gray)
                } else if isEnvironmentValid == true {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(environmentStatusMessage)
                        .font(.footnote)
                } else {
                    Image(systemName: "xmark.octagon.fill")
                        .foregroundColor(.red)
                    Text(environmentStatusMessage)
                        .font(.footnote)
                }
                Spacer()
                if isEnvironmentValid == false {
                    Button("Setup Environment") {
                        setupPythonEnvironment()
                    }
                    .disabled(isSettingUpEnvironment)
                    .padding(.leading, 5)
                }
                
                Button {
                    checkPythonEnvironment()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Re-check Python Environment")
                .disabled(isSettingUpEnvironment)
            }
            .padding(.bottom, 5)
            
            GroupBox("Configuration") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Input Repo ID:")
                        TextField("e.g., mistralai/Mistral-7B-v0.1", text: $inputRepo)
                    }
                    HStack {
                        Text("Output Repo ID:")
                        TextField("Optional: e.g., your-username/Mistral-7B-v0.1-mlx", text: $outputRepo)
                    }
                    Picker("Quantization:", selection: $quantizationLevel) {
                        ForEach(QuantizationLevel.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }
                    .pickerStyle(.segmented)
                    
                    HStack {
                        Text("Python Path:")
                        TextField("e.g., /usr/local/bin/python3", text: $pythonPath)
                            .disabled(isRunning || isSettingUpEnvironment)
                    }
                }
                .padding(.vertical, 5)
            }
            
            HStack {
                Button(action: {
                    runConversion(upload: false)
                }) {
                    HStack {
                        if isRunning {
                            ProgressView().controlSize(.small)
                        }
                        Text(isRunning ? "Working..." : "Convert")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .disabled(inputRepo.isEmpty || isRunning || isEnvironmentValid != true || isSettingUpEnvironment)
                .help("Convert the Hugging Face model to MLX format locally.")
                
                Button(action: {
                    runConversion(upload: true)
                }) {
                    HStack {
                        if isRunning {
                            ProgressView().controlSize(.small)
                        }
                        Text(isRunning ? "Working..." : "Convert and Upload")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(inputRepo.isEmpty || outputRepo.isEmpty || isRunning || isEnvironmentValid != true || isSettingUpEnvironment)
                .help("Convert the model and upload it to the specified Hugging Face repo.")
            }
            
            GroupBox("Logs") {
                TextEditor(text: $outputLog)
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
            if isSettingUpEnvironment {
                VStack {
                    ProgressView("Setting up Python environment...")
                        .padding()
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .shadow(radius: 5)
                }
            }
        }
        .onAppear {
            checkPythonEnvironment()
        }
    }
    
    func buildArguments(upload: Bool) -> [String] {
        var args = [String]()
        let pythonExecutable = pythonPath == "/usr/bin/env" ? "python3" : pythonPath
        
        if pythonPath == "/usr/bin/env" {
            args.append(pythonExecutable)
        }
        args.append("-m")
        args.append("mlx_lm")
        args.append("convert")
        
        args.append("--hf-path")
        args.append(inputRepo)
        
        args.append(contentsOf: quantizationLevel.arguments)
        
        if upload && !outputRepo.isEmpty {
            args.append("--upload-repo")
            args.append(outputRepo)
        }
        
        return args
    }
    
    func runConversion(upload: Bool) {
        guard isEnvironmentValid == true else {
            outputLog = "Cannot run conversion, Python environment is not valid.\n\(environmentStatusMessage)"
            return
        }
        
        if upload && outputRepo.isEmpty {
            outputLog = "ERROR: Output Repo ID cannot be empty when uploading."
            return
        }
        
        isRunning = true
        outputLog = "Starting \(upload ? "conversion and upload" : "conversion")...\n"
        
        let task = Process()
        var processArguments: [String]
        
        if pythonPath == "/usr/bin/env" {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            processArguments = buildArguments(upload: upload)
        } else {
            guard FileManager.default.fileExists(atPath: pythonPath) else {
                outputLog = "ERROR: Specified Python path does not exist: \(pythonPath)"
                isRunning = false
                return
            }
            task.executableURL = URL(fileURLWithPath: pythonPath)
            processArguments = buildArguments(upload: upload)
            if pythonPath != "/usr/bin/env" && processArguments.first == "python3" {
                processArguments = Array(processArguments.dropFirst())
            }
        }
        task.arguments = processArguments
        outputLog += "Running: \(task.executableURL?.path ?? "unknown") \(processArguments.joined(separator: " "))\n\n"
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        let outputHandle = outputPipe.fileHandleForReading
        let errorHandle = errorPipe.fileHandleForReading
        
        outputHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                DispatchQueue.main.async {
                    self.outputLog += line
                }
            }
        }
        
        errorHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                DispatchQueue.main.async {
                    self.outputLog += "ERROR: \(line)"
                }
            }
        }
        
        task.terminationHandler = { process in
            DispatchQueue.main.async {
                outputHandle.readabilityHandler = nil
                errorHandle.readabilityHandler = nil
                
                let baseMessage = upload ? "Conversion and Upload" : "Conversion"
                if process.terminationStatus == 0 {
                    self.outputLog += "\n\n\(baseMessage) Successful!"
                } else {
                    self.outputLog += "\n\n\(baseMessage) failed with status: \(process.terminationStatus)"
                }
                self.isRunning = false
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try task.run()
            } catch {
                DispatchQueue.main.async { 
                    self.outputLog += "\n\nFailed to start process: \(error.localizedDescription)"
                    self.isRunning = false
                }
            }
        }
    }
    
    func checkPythonEnvironment() {
        DispatchQueue.main.async {
            self.isEnvironmentValid = nil
            self.environmentStatusMessage = "Checking Python environment..."
        }
        
        let task = Process()
        let checkCommand = "-c"
        let importCheck = """
import sys
print(f"Python Version: {sys.version}")
try:
    import mlx_lm
    print("mlx_lm found")
except ImportError as e:
    print(f"Import Error: {str(e)}")
"""
        
        if pythonPath == "/usr/bin/env" {
            task.executableURL = URL(fileURLWithPath: "/usr/local/bin/python3")
            task.arguments = [checkCommand, importCheck]
        } else {
            task.executableURL = URL(fileURLWithPath: pythonPath)
            task.arguments = [checkCommand, importCheck]
        }
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        task.terminationHandler = { process in
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let outputString = String(data: outputData, encoding: .utf8) ?? ""
            let errorString = String(data: errorData, encoding: .utf8) ?? ""
            
            DispatchQueue.main.async {
                if process.terminationStatus == 0 && outputString.contains("mlx_lm found") {
                    self.environmentStatusMessage = "✅ Python environment OK (mlx-lm found)"
                    self.isEnvironmentValid = true
                } else {
                    var errorMessage = "❌ Python environment requires setup:\n"
                    if !outputString.contains("mlx_lm found") && outputString.contains("Python Version:") {
                        errorMessage += "   - 'mlx' or 'mlx_lm' package not found.\n"
                    }
                    if !outputString.isEmpty {
                        errorMessage += "\nOutput:\n\(outputString.trimmingCharacters(in: .whitespacesAndNewlines))\n"
                    }
                    if !errorString.isEmpty {
                        errorMessage += "\nError Output:\n\(errorString.trimmingCharacters(in: .whitespacesAndNewlines))\n"
                    }
                    errorMessage += "\nTo fix:\n1. Open Terminal.\n2. Activate the Python environment if needed (e.g., conda activate <env>).\n3. Run: pip install mlx mlx-lm (Use the button below to copy).\n4. Click the refresh button above."
                    self.environmentStatusMessage = errorMessage
                    self.isEnvironmentValid = false
                }
            }
        }
        
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try task.run()
                task.waitUntilExit()
            } catch {
                DispatchQueue.main.async {
                    self.environmentStatusMessage = "❌ Failed to run Python: \(error.localizedDescription)"
                    self.isEnvironmentValid = false
                }
            }
        }
    }
    
    func setupPythonEnvironment() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Choose Directory for Virtual Environment"
        openPanel.message = "Select a folder where the '.venv' directory will be created."
        openPanel.showsHiddenFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = true
        openPanel.allowsMultipleSelection = false
        
        openPanel.begin { (result) -> Void in
            if result == .OK, let url = openPanel.url {
                let directoryPath = url.path
                DispatchQueue.main.async {
                    self.isSettingUpEnvironment = true
                    self.outputLog = "Starting Python environment setup in: \(directoryPath)\n"
                }
                self.runSetupCommands(in: directoryPath)
            }
        }
    }
    
    func runSetupCommands(in directoryPath: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let basePythonPath = self.pythonPath
            let venvPath = "\(directoryPath)/.venv"
            let venvPythonPath = "\(venvPath)/bin/python3"
            var log = ""
            var success = false
            
            log += "Attempting to create virtual environment using: \(basePythonPath)\n"
            log += "Command: \(basePythonPath) -m venv \(venvPath)\n"
            let createVenvResult = self.runShellCommand(executable: basePythonPath, arguments: ["-m", "venv", venvPath], currentDirectory: directoryPath)
            log += createVenvResult.log
            
            if createVenvResult.success {
                log += "\nVirtual environment created.\n"
                log += "\nAttempting to install packages using: \(venvPythonPath)\n"
                log += "Command: \(venvPythonPath) -m pip install mlx mlx-lm\n"
                let installResult = self.runShellCommand(executable: venvPythonPath, arguments: ["-m", "pip", "install", "mlx", "mlx-lm"], currentDirectory: directoryPath)
                log += installResult.log
                
                if installResult.success {
                    log += "\nPackages installed successfully.\n"
                    success = true
                } else {
                    log += "\nError installing packages.\n"
                }
            } else {
                log += "\nError creating virtual environment. Make sure '\(basePythonPath)' is a valid Python executable.\n"
            }
            DispatchQueue.main.async {
                self.outputLog += log
                self.isSettingUpEnvironment = false
            }
        }
    }
    
    func runShellCommand(executable: String, arguments: [String], currentDirectory: String? = nil) -> (log: String, success: Bool) {
        let task = Process()
        var finalArguments = arguments
        
        if executable == "/usr/bin/env" {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            finalArguments.insert("python3", at: 0)
        } else {
            guard FileManager.default.fileExists(atPath: executable) else {
                return ("Error: Executable path does not exist: \(executable)", false)
            }
            task.executableURL = URL(fileURLWithPath: executable)
        }
        
        task.arguments = finalArguments
        
        if let currentDirectory {
            task.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        var outputLog = ""
        
        do {
            outputLog += "Running command: \(task.executableURL?.path ?? "unknown") \(finalArguments.joined(separator: " "))\n"
            try task.run()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                outputLog += "Output:\n\(output)\n"
            }
            if let error = String(data: errorData, encoding: .utf8), !error.isEmpty {
                outputLog += "Error Output:\n\(error)\n"
            }
            
            task.waitUntilExit()
            outputLog += "Process exited with status: \(task.terminationStatus)\n"
            return (outputLog, task.terminationStatus == 0)
            
        } catch {
            outputLog += "Failed to run command: \(error.localizedDescription)\n"
            return (outputLog, false)
        }
    }
}
