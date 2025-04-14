//
//  ContentView.swift
//  MLX Forge
//
//  Created by Rudrank Riyam on 4/15/25.
//

import SwiftUI

struct ContentView: View {
    // ADD: State variables for UI inputs and process management
    @State private var inputRepo = ""
    @State private var outputRepo = ""
    @State private var shouldQuantize = true
    @State private var outputLog = "Process output will appear here..."
    @State private var isRunning = false
    // ADD: Variable for Python path (can be refined later)
    @State private var pythonPath = "/usr/bin/env" // Default, might need user configuration

    var body: some View {
        // REPLACE: Default content with new UI
        VStack(alignment: .leading, spacing: 15) {
            Text("MLX Forge")
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
                    // TODO: Add fields for quantization options if needed
                }
                .padding(.vertical, 5)
            }

            Button(action: {
                // TODO: Implement runConversion() call
                print("Run Conversion Tapped!")
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
            .disabled(inputRepo.isEmpty || isRunning) // Disable if no input or already running

            GroupBox("Logs") {
                TextEditor(text: $outputLog)
                    .font(.system(.caption, design: .monospaced))
                    .frame(height: 200) // Adjust height as needed
                    .border(Color.gray.opacity(0.5))
            }

            Spacer() // Pushes content to the top
        }
        .padding()
        .frame(minHeight: 600) // Set a maximum width for the window
    }
}

#Preview {
    ContentView()
}
