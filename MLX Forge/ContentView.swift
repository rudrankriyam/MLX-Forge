//
//  ContentView.swift
//  MLX Forge
//
//  Created by Rudrank Riyam on 4/15/25.
//

import SwiftUI
import Foundation // Keep Foundation for Process
import AppKit // ADD: Import AppKit for NSPasteboard

struct ContentView: View {
    @State private var inputRepo = ""
    @State private var outputRepo = ""
    @State private var quantizationLevel: String = "4-bit" // Default to 4-bit
    let quantizationOptions = ["None", "4-bit", "8-bit"]
    @State private var outputLog = "Process output will appear here..."
    @State private var isRunning = false
    @State private var pythonPath = "/usr/local/bin/python3" // Default, user might override
    @State private var isEnvironmentValid: Bool? = nil
    @State private var environmentStatusMessage = "Checking Python environment..."
    @State private var isSettingUpEnvironment = false

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            // Environment Status Display
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
                    // Consider adding a button/link here to show installation instructions
                }
                Spacer() // Push status to the left
                // ADD: Button to re-check environment
                if isEnvironmentValid == false {
                    Button("Setup Environment") {
                        setupPythonEnvironment()
                    }
                    .disabled(isSettingUpEnvironment) // Disable while setup is running
                    .padding(.leading, 5)
                }

                Button {
                    checkPythonEnvironment()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Re-check Python Environment")
                .disabled(isSettingUpEnvironment) // Disable while setup is running
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
                        ForEach(quantizationOptions, id: \.self) { level in
                            Text(level)
                        }
                    }
                    .pickerStyle(.segmented) // Or .menu for dropdown

                    HStack {
                        Text("Python Path:")
                        TextField("e.g., /usr/local/bin/python3", text: $pythonPath)
                            .disabled(isRunning || isSettingUpEnvironment)
                    }
                }
                .padding(.vertical, 5)
            }

            HStack {
                // Convert Button (Local)
                Button(action: {
                    runConversion(upload: false) // Call with upload: false
                }) {
                    HStack {
                        if isRunning { // Show progress if either is running
                            ProgressView().controlSize(.small)
                        }
                        Text(isRunning ? "Working..." : "Convert")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered) // Use bordered for secondary action
                .disabled(inputRepo.isEmpty || isRunning || isEnvironmentValid != true || isSettingUpEnvironment)
                .help("Convert the Hugging Face model to MLX format locally.")

                // Convert and Upload Button
                Button(action: {
                    runConversion(upload: true) // Call with upload: true
                }) {
                    HStack {
                        if isRunning { // Show progress if either is running
                            ProgressView().controlSize(.small)
                        }
                        Text(isRunning ? "Working..." : "Convert and Upload")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent) // Use prominent for primary action
                .disabled(inputRepo.isEmpty || outputRepo.isEmpty || isRunning || isEnvironmentValid != true || isSettingUpEnvironment) // Also disable if outputRepo is empty
                .help("Convert the model and upload it to the specified Hugging Face repo.")
            }

            GroupBox("Logs") {
                TextEditor(text: $outputLog)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 200)
                    .border(Color.gray.opacity(0.5))
            }

            Button {
                // CHANGE: Use NSPasteboard for macOS
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString("pip install mlx mlx-lm", forType: .string)
            } label: {
                Label("Copy install command", systemImage: "doc.on.doc") // CHANGE: Text slightly
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help("Click to copy 'pip install mlx mlx-lm' to clipboard") // CHANGE: Updated help

            Spacer()
        }
        .padding()
        .overlay { // ADD: Overlay for setup progress
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
            // Run check when the view appears
            checkPythonEnvironment()
        }
    }

    func buildArguments(upload: Bool) -> [String] {
        var args = [String]()
        let pythonExecutable = pythonPath == "/usr/bin/env" ? "python3" : pythonPath

        if pythonPath == "/usr/bin/env" {
             args.append(pythonExecutable) // Add python3 if using env
        }
        args.append("-m")
        args.append("mlx_lm")
        args.append("convert")

        args.append("--hf-path")
        args.append(inputRepo)

        // CHANGE: Add quantization arguments based on selection
        if quantizationLevel != "None" {
            args.append("-q") // Enable quantization
            if quantizationLevel == "4-bit" {
                args.append("--q-bits")
                args.append("4")
                // args.append("--q-group-size") // Optional: Specify default group size
                // args.append("64")
            } else if quantizationLevel == "8-bit" {
                args.append("--q-bits")
                args.append("8")
                // args.append("--q-group-size") // Optional: Specify default group size
                // args.append("64")
            }
        }

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

        // ADD: Check if output repo is provided when uploading
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
            // CHANGE: Pass upload flag
            processArguments = buildArguments(upload: upload) // Includes 'python3'
        } else {
            guard FileManager.default.fileExists(atPath: pythonPath) else {
                 outputLog = "ERROR: Specified Python path does not exist: \(pythonPath)"
                 isRunning = false
                 return
            }
            task.executableURL = URL(fileURLWithPath: pythonPath)
            // CHANGE: Pass upload flag and adjust dropFirst logic if needed
            // Exclude 'python3' from buildArguments if path is direct
            processArguments = buildArguments(upload: upload)
            if pythonPath != "/usr/bin/env" && processArguments.first == "python3" { // Check if buildArguments added python3 unnecessarily
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
                // Ensure handlers are nil'd out on main thread *before* updating state
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

    // CHANGE: Function to check Python environment with more detailed debugging
    func checkPythonEnvironment() {
        DispatchQueue.main.async {
            self.isEnvironmentValid = nil
            self.environmentStatusMessage = "Checking Python environment..."
        }

        let task = Process()
        let checkCommand = "-c"
        // More detailed check that prints Python version and attempts import
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
                    // CHANGE: Refine the error message and instructions
                    var errorMessage = "❌ Python environment requires setup:\n"
                    if !outputString.contains("mlx_lm found") && outputString.contains("Python Version:") {
                         // Specifically mention missing packages if Python ran but import failed
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

    // ADD: Function to setup Python environment
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

    // ADD: Helper to run the setup commands
    func runSetupCommands(in directoryPath: String) {
        DispatchQueue.global(qos: .userInitiated).async {
            let basePythonPath = self.pythonPath // Use the python specified in the TextField to create the venv
            let venvPath = "\(directoryPath)/.venv"
            let venvPythonPath = "\(venvPath)/bin/python3"
            var log = ""
            var success = false

            // --- 1. Create venv ---
            log += "Attempting to create virtual environment using: \(basePythonPath)\n"
            log += "Command: \(basePythonPath) -m venv \(venvPath)\n"
            let createVenvResult = self.runShellCommand(executable: basePythonPath, arguments: ["-m", "venv", venvPath], currentDirectory: directoryPath)
            log += createVenvResult.log

            if createVenvResult.success {
                log += "\nVirtual environment created.\n"
                // --- 2. Install packages using venv's python ---
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

            // --- 3. Update UI on Main Thread ---
            DispatchQueue.main.async {
                self.outputLog += log
                if success {
                    self.outputLog += "\nSetup complete! Updating Python path and re-checking environment.\n"
                    self.pythonPath = venvPythonPath // Update the path in the UI
                    self.checkPythonEnvironment() // Re-run the check
                } else {
                    self.outputLog += "\nEnvironment setup failed. Please check the logs and ensure your base Python path is correct.\n"
                }
                self.isSettingUpEnvironment = false
            }
        }
    }

    // ADD: Helper function to run a shell command and capture output
    func runShellCommand(executable: String, arguments: [String], currentDirectory: String? = nil) -> (log: String, success: Bool) {
        let task = Process()
        var finalArguments = arguments // Use a mutable copy

        // Check if the executable is /usr/bin/env
        if executable == "/usr/bin/env" {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            // Prepend 'python3' (or the appropriate command env should find)
            finalArguments.insert("python3", at: 0)
        } else {
            // Handle direct path
            guard FileManager.default.fileExists(atPath: executable) else {
                return ("Error: Executable path does not exist: \(executable)", false)
            }
            task.executableURL = URL(fileURLWithPath: executable)
        }

        task.arguments = finalArguments // Assign the potentially modified arguments

        if let currentDirectory {
            task.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        var outputLog = ""

        do {
            // Log the actual command being executed
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

#Preview {
    ContentView()
}
