//
//  ContentView.swift
//  MLX Forge
//
//  Created by Rudrank Riyam on 4/15/25.
//

import SwiftUI
import Foundation // Keep Foundation for Process

struct ContentView: View {
    @State private var inputRepo = ""
    @State private var outputRepo = ""
    @State private var shouldQuantize = true
    @State private var outputLog = "Process output will appear here..."
    @State private var isRunning = false
    // Keep pythonPath, make it configurable later
    @State private var pythonPath = "/usr/bin/env" // Default, user might override

    // ADD: State for environment check results
    @State private var isEnvironmentValid: Bool? = nil // nil = not checked, true = valid, false = invalid
    @State private var environmentStatusMessage = "Checking Python environment..."

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("MLX Model Conversion")
                .font(.title)

            // ADD: Environment Status Display
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
                Button {
                    checkPythonEnvironment()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Re-check Python Environment")
            }
            .padding(.bottom, 5)


            GroupBox("Configuration") {
                VStack(alignment: .leading) {
                    // TODO: Add TextField for Python Path later
                    HStack {
                        Text("Input Repo ID:")
                        TextField("e.g., mistralai/Mistral-7B-v0.1", text: $inputRepo)
                    }
                    HStack {
                        Text("Output Repo ID:")
                        TextField("Optional: e.g., your-username/Mistral-7B-v0.1-mlx", text: $outputRepo)
                    }
                    Toggle("Quantize Model (-q)", isOn: $shouldQuantize)
                    HStack {
                        Text("Python Path:")
                        TextField("e.g., /usr/bin/python3", text: $pythonPath)
                    }
                }
                .padding(.vertical, 5)
            }

            Button(action: {
                runConversion() // Use the Process-based function
            }) {
                HStack {
                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(isRunning ? "Converting..." : "Convert and Upload")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            // CHANGE: Disable if environment isn't valid OR already running OR no input
            .disabled(inputRepo.isEmpty || isRunning || isEnvironmentValid != true)

            GroupBox("Logs") {
                TextEditor(text: $outputLog)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 200)
                    .border(Color.gray.opacity(0.5))
            }

            Spacer()
        }
        .padding()
        .onAppear {
            // Run check when the view appears
            checkPythonEnvironment()
        }
    }

    func buildArguments() -> [String] {
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

        if shouldQuantize {
            args.append("-q")
        }

        if !outputRepo.isEmpty {
            args.append("--upload-repo")
            args.append(outputRepo)
        }

        return args
    }

    func runConversion() {
        guard isEnvironmentValid == true else {
            outputLog = "Cannot run conversion, Python environment is not valid.\n\(environmentStatusMessage)"
            return
        }

        isRunning = true
        outputLog = "Starting conversion...\n"

        let task = Process()
        var processArguments: [String]

        if pythonPath == "/usr/bin/env" {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            processArguments = buildArguments() // Includes 'python3'
        } else {
            // Ensure the path is valid before trying to use it
            guard FileManager.default.fileExists(atPath: pythonPath) else {
                 outputLog = "ERROR: Specified Python path does not exist: \(pythonPath)"
                 isRunning = false
                 return
            }
            task.executableURL = URL(fileURLWithPath: pythonPath)
            // Exclude 'python3' from buildArguments if path is direct
            processArguments = buildArguments().dropFirst().compactMap { $0 }
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

                if process.terminationStatus == 0 {
                     self.outputLog += "\n\nConversion and Upload Successful!"
                } else {
                    self.outputLog += "\n\nProcess failed with status: \(process.terminationStatus)"
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

    // ADD: Function to check Python environment
    func checkPythonEnvironment() {
        DispatchQueue.main.async {
            self.isEnvironmentValid = nil // Reset status while checking
            self.environmentStatusMessage = "Checking Python environment..."
        }

        let task = Process()
        var checkArguments: [String]
        let checkCommand = "-c" // Use -c to execute a command string
        let importCheck = "import mlx_lm; print('mlx_lm found')" // Simple import check

        if pythonPath == "/usr/bin/env" {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            checkArguments = ["python3", checkCommand, importCheck]
        } else {
            // Check if the custom path exists first
            guard FileManager.default.fileExists(atPath: pythonPath) else {
                DispatchQueue.main.async {
                    self.environmentStatusMessage = "❌ Error: Specified Python path not found: \(self.pythonPath)"
                    self.isEnvironmentValid = false
                }
                return
            }
            task.executableURL = URL(fileURLWithPath: pythonPath)
            checkArguments = [checkCommand, importCheck]
        }

        task.arguments = checkArguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe // Capture errors during check

        task.terminationHandler = { process in
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let outputString = String(data: outputData, encoding: .utf8) ?? ""
            let errorString = String(data: errorData, encoding: .utf8) ?? ""

            DispatchQueue.main.async {
                if process.terminationStatus == 0 && outputString.contains("mlx_lm found") {
                    self.environmentStatusMessage = "✅ Python environment OK (mlx-lm found using \(self.pythonPath == "/usr/bin/env" ? "python3 in PATH" : "custom path"))"
                    self.isEnvironmentValid = true
                } else {
                    var errorMessage = "❌ mlx-lm not found or Python error.\n"
                    errorMessage += "   Attempted using: \(self.pythonPath == "/usr/bin/env" ? "python3 in PATH" : self.pythonPath)\n"
                    if !errorString.isEmpty {
                        errorMessage += "   Error Output: \(errorString.trimmingCharacters(in: .whitespacesAndNewlines))"
                    } else if process.terminationStatus != 0 {
                         errorMessage += "   Python process exited with status \(process.terminationStatus)."
                    }
                    errorMessage += "\n   Please run 'pip install mlx-lm' in the correct environment, or specify the Python path in settings."
                    self.environmentStatusMessage = errorMessage
                    self.isEnvironmentValid = false
                }
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try task.run()
            } catch {
                DispatchQueue.main.async {
                    self.environmentStatusMessage = "❌ Failed to run Python check: \(error.localizedDescription)"
                    self.isEnvironmentValid = false
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
