//
//  ContentView.swift
//  MLX Forge
//
//  Created by Rudrank Riyam on 4/15/25.
//

import SwiftUI
import Foundation

struct ContentView: View {
    @State private var inputRepo = ""
    @State private var outputRepo = ""
    @State private var shouldQuantize = true
    @State private var outputLog = "Process output will appear here..."
    @State private var isRunning = false
    @State private var pythonPath = "/usr/bin/env" // Default, might need user configuration

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("MLX Model Conversion")
                .font(.title)

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
                    Toggle("Quantize Model (-q)", isOn: $shouldQuantize)
                }
                .padding(.vertical, 5)
            }

            Button(action: {
                runConversion()
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
            .disabled(inputRepo.isEmpty || isRunning)

            GroupBox("Logs") {
                TextEditor(text: $outputLog)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 200)
                    .border(Color.gray.opacity(0.5))
            }

            Spacer()
        }
        .padding()
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
        isRunning = true
        outputLog = "Starting conversion...\n"

        let task = Process()
        if pythonPath == "/usr/bin/env" {
            task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            task.arguments = buildArguments()
        } else {
            task.executableURL = URL(fileURLWithPath: pythonPath)
            task.arguments = buildArguments().dropFirst().compactMap { $0 }
        }

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
                    outputLog += line
                }
            }
        }

        errorHandle.readabilityHandler = { handle in
            let data = handle.availableData
            if let line = String(data: data, encoding: .utf8), !line.isEmpty {
                 DispatchQueue.main.async {
                    outputLog += "ERROR: \(line)"
                }
            }
        }

        task.terminationHandler = { process in
             DispatchQueue.main.async {
                outputHandle.readabilityHandler = nil
                errorHandle.readabilityHandler = nil

                if process.terminationStatus == 0 {
                     outputLog += "\n\nConversion and Upload Successful!"
                } else {
                    outputLog += "\n\nProcess failed with status: \(process.terminationStatus)"
                }
                isRunning = false
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try task.run()
            } catch {
                DispatchQueue.main.async {
                     outputLog += "\n\nFailed to start process: \(error.localizedDescription)"
                     isRunning = false
                }
            }
        }
    }
}

#Preview {
    ContentView()
}
