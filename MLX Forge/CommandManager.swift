import SwiftUI
import Foundation
import Combine
import AppKit

// Keep QuantizationLevel here or move it if preferred
// enum QuantizationLevel: String, CaseIterable, Identifiable { ... }

@MainActor
class CommandManager: ObservableObject {
    @Published var outputLog = "Process output will appear here..."
    @Published var isRunning = false
    @Published var isEnvironmentValid: Bool? = nil
    @Published var environmentStatusMessage = "Checking Python environment..."
    @Published var isSettingUpEnvironment = false
    @Published var pythonPath: String = ""
    @Published var inputRepo: String = ""
    @Published var outputRepo: String = ""
    @Published var quantizationLevel: QuantizationLevel = .none

    private var currentTask: Process?

    func buildArguments(pythonPath: String, inputRepo: String, outputRepo: String?, quantizationLevel: QuantizationLevel, upload: Bool) -> (executable: String, arguments: [String]) {
        var args = [String]()
        let effectivePythonPath = (pythonPath.isEmpty || pythonPath == "/usr/bin/env") ? "/usr/bin/env" : pythonPath
        _ = (effectivePythonPath == "/usr/bin/env") ? "python3" : effectivePythonPath

        if effectivePythonPath == "/usr/bin/env" {
            args.append("python3") // Let /usr/bin/env find python3
        }
        args.append("-m")
        args.append("mlx_lm")
        args.append("convert")

        args.append("--hf-path")
        args.append(inputRepo)

        args.append(contentsOf: quantizationLevel.arguments)

        if upload, let repo = outputRepo, !repo.isEmpty {
            args.append("--upload-repo")
            args.append(repo)
        }

        return (effectivePythonPath, args)
    }

    func runProcess(executablePath: String, arguments: [String], currentDirectory: String? = nil) async throws -> (success: Bool, output: String) {
        let task = Process()
        var processArguments = arguments
        var finalExecutablePath = executablePath
        
        if executablePath == "/usr/bin/env" {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            if arguments.first != "python3" {
                processArguments.insert("python3", at: 0)
            }
            finalExecutablePath = "/usr/bin/env"
        } else {
            guard FileManager.default.fileExists(atPath: executablePath) else {
                throw CommandError.executableNotFound(path: executablePath)
            }
            task.executableURL = URL(fileURLWithPath: executablePath)
            if executablePath != "/usr/bin/env" && processArguments.first == "python3" {
                processArguments = Array(processArguments.dropFirst())
            }
        }
        
        task.arguments = processArguments
        if let currentDirectory = currentDirectory {
            task.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe
        
        var output = "Running: \(finalExecutablePath) \(processArguments.joined(separator: " "))\n\n"
        
        do {
            try task.run()
            
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            
            if let outputString = String(data: outputData, encoding: .utf8), !outputString.isEmpty {
                output += outputString
            }
            
            if let errorString = String(data: errorData, encoding: .utf8), !errorString.isEmpty {
                output += "Error Output:\n\(errorString)"
            }
            
            task.waitUntilExit()
            output += "\nProcess terminated with status: \(task.terminationStatus)"
            
            return (task.terminationStatus == 0, output)
        } catch {
            throw CommandError.executionFailed(error: error)
        }
    }
    
    func checkPythonEnvironment(pythonPath: String) {
        isEnvironmentValid = nil
        environmentStatusMessage = "Checking Python environment..."
        
        Task {
            let checkCommand = "-c"
            let importCheck = """
            import sys
            print(f"Python Version: {sys.version.splitlines()[0]}")
            try:
                import mlx
                import mlx_lm
                print("mlx and mlx_lm found")
            except ImportError as e:
                print(f"Import Error: {str(e)}")
                sys.exit(1)
            sys.exit(0)
            """
            
            do {
                let (success, output) = try await runProcess(
                    executablePath: pythonPath,
                    arguments: [checkCommand, importCheck]
                )
                
                if success && output.contains("mlx and mlx_lm found") {
                    let versionLine = output.split(separator: "\n")
                        .first(where: { $0.contains("Python Version:") }) ?? ""
                    environmentStatusMessage = "✅ Python environment OK (\(versionLine))"
                    isEnvironmentValid = true
                } else {
                    var errorMessage = "❌ Python environment requires setup:\n"
                    if !output.contains("mlx and mlx_lm found") {
                        errorMessage += "   - 'mlx' or 'mlx_lm' package not found.\n"
                    }
                    errorMessage += "\nDetails:\n\(output)\n"
                    errorMessage += "\nTo fix:\n1. Open Terminal\n2. Run: pip install mlx mlx-lm"
                    environmentStatusMessage = errorMessage
                    isEnvironmentValid = false
                }
            } catch {
                environmentStatusMessage = "❌ Failed to check Python environment: \(error.localizedDescription)"
                isEnvironmentValid = false
            }
        }
    }
    
    func runConversion(pythonPath: String, inputRepo: String, outputRepo: String, quantizationLevel: QuantizationLevel, upload: Bool) {
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
        
        Task {
            do {
                let baseArguments = ["-m", "mlx_lm", "convert", "--hf-path", inputRepo]
                var arguments = baseArguments + quantizationLevel.arguments
                
                if upload && !outputRepo.isEmpty {
                    arguments += ["--upload-repo", outputRepo]
                }
                
                let (success, output) = try await runProcess(
                    executablePath: pythonPath,
                    arguments: arguments
                )
                
                outputLog = output
                
                if success {
                    outputLog += "\n\n\(upload ? "Conversion and Upload" : "Conversion") Successful!"
                }
            } catch {
                outputLog += "\n\nError: \(error.localizedDescription)"
            }
            isRunning = false
        }
    }
    
    func setupPythonEnvironment(basePythonPath: String, directoryPath: String) async throws {
        isSettingUpEnvironment = true
        outputLog = "Starting Python environment setup in: \(directoryPath)\n"
        
        let venvPath = "\(directoryPath)/.venv"
        let venvPythonPath = "\(venvPath)/bin/python3"
        
        // Create virtual environment
        outputLog += "Creating virtual environment...\n"
        let (venvSuccess, venvOutput) = try await runProcess(
            executablePath: basePythonPath,
            arguments: ["-m", "venv", venvPath],
            currentDirectory: directoryPath
        )
        
        guard venvSuccess else {
            throw CommandError.venvCreationFailed(output: venvOutput)
        }
        
        // Install packages
        outputLog += "Installing required packages...\n"
        let (installSuccess, installOutput) = try await runProcess(
            executablePath: venvPythonPath,
            arguments: ["-m", "pip", "install", "mlx", "mlx-lm"],
            currentDirectory: directoryPath
        )
        
        guard installSuccess else {
            throw CommandError.packageInstallationFailed(output: installOutput)
        }
        
        outputLog += "\nSetup complete! Please update the Python Path to: \(venvPythonPath)"
        isSettingUpEnvironment = false
        checkPythonEnvironment(pythonPath: venvPythonPath)
    }
    
    // UI entrypoint: show directory picker and dispatch async setup
    func setupPythonEnvironment() {
        let openPanel = NSOpenPanel()
        openPanel.title = "Choose Directory for Virtual Environment"
        openPanel.message = "Select a folder where the '.venv' directory will be created."
        openPanel.showsHiddenFiles = false
        openPanel.canChooseDirectories = true
        openPanel.canChooseFiles = false
        openPanel.canCreateDirectories = true
        openPanel.allowsMultipleSelection = false

        openPanel.begin { response in
            if response == .OK, let url = openPanel.url {
                DispatchQueue.main.async {
                    self.isSettingUpEnvironment = true
                    self.outputLog = "Starting Python environment setup in: \(url.path)\n"
                }
                Task {
                    do {
                        try await self.setupPythonEnvironment(basePythonPath: self.pythonPath, directoryPath: url.path)
                    } catch {
                        DispatchQueue.main.async {
                            self.outputLog += "\n\nError: \(error.localizedDescription)"
                            self.isSettingUpEnvironment = false
                        }
                    }
                }
            }
        }
    }

    // Parameterless environment check
    func checkPythonEnvironment() {
        checkPythonEnvironment(pythonPath: self.pythonPath)
    }
}

enum CommandError: LocalizedError {
    case executableNotFound(path: String)
    case executionFailed(error: Error)
    case venvCreationFailed(output: String)
    case packageInstallationFailed(output: String)
    
    var errorDescription: String? {
        switch self {
        case .executableNotFound(let path):
            return "Python executable not found at path: \(path)"
        case .executionFailed(let error):
            return "Command execution failed: \(error.localizedDescription)"
        case .venvCreationFailed(let output):
            return "Failed to create virtual environment: \(output)"
        case .packageInstallationFailed(let output):
            return "Failed to install required packages: \(output)"
        }
    }
}
