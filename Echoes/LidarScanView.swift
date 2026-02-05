//
//  LidarScanView.swift
//  Echoes
//
//  Created by Codex on 2026/02/05.
//

import SwiftUI
import ARKit
import RealityKit

struct LidarScanView: View {
    @State private var isScanning = false
    @State private var startToken = 0
    @State private var stopToken = 0
    @State private var pauseToken = 0
    @State private var canStop = false
    @State private var minDurationTask: Task<Void, Never>?

    var body: some View {
        ZStack(alignment: .bottom) {
            LidarARViewContainer(
                startToken: $startToken,
                stopToken: $stopToken,
                pauseToken: $pauseToken
            )
                .ignoresSafeArea()

            if isScanning {
                VStack {
                    Text("スキャン中…\nゆっくり周囲を見回してください")
                        .font(.headline)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)
                        .background(.ultraThinMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .padding(.top, 24)
                    Spacer()
                }
            }

            Button {
                if isScanning {
                    stopScanIfPossible()
                } else {
                    startScan()
                }
            } label: {
                ZStack {
                    Circle()
                        .fill(buttonFillColor)
                        .frame(width: 72, height: 72)
                        .overlay(
                            Circle()
                                .stroke(.black.opacity(0.2), lineWidth: 2)
                                .frame(width: 80, height: 80)
                        )

                    if isScanning && canStop {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(.white)
                            .frame(width: 22, height: 22)
                    } else if isScanning && !canStop {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.7))
                            .frame(width: 22, height: 22)
                    }
                }
            }
            .padding(.bottom, 32)
            .disabled(isScanning && !canStop)
            .opacity(isScanning && !canStop ? 0.4 : 1)
        }
        .onDisappear(perform: forceStopScan)
    }

    private var buttonFillColor: Color {
        if isScanning {
            return canStop ? .red : .gray
        }
        return .white
    }

    private func startScan() {
        isScanning = true
        canStop = false
        startToken += 1
        startMinDurationTimer()
    }

    private func stopScanIfPossible() {
        guard canStop else { return }
        isScanning = false
        canStop = false
        stopToken += 1
        cancelMinDurationTimer()
    }

    private func forceStopScan() {
        if isScanning {
            isScanning = false
            canStop = false
            stopToken += 1
        }
        cancelMinDurationTimer()
        pauseToken += 1
    }

    private func startMinDurationTimer() {
        minDurationTask?.cancel()
        minDurationTask = Task {
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            await MainActor.run {
                canStop = true
            }
        }
    }

    private func cancelMinDurationTimer() {
        minDurationTask?.cancel()
        minDurationTask = nil
    }
}

private struct LidarARViewContainer: UIViewRepresentable {
    @Binding var startToken: Int
    @Binding var stopToken: Int
    @Binding var pauseToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> ARView {
        let view = ARView(frame: .zero)
        view.debugOptions = [.showSceneUnderstanding]
        view.automaticallyConfigureSession = false
        context.coordinator.arView = view
        context.coordinator.runPreviewIfPossible()
        return view
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        context.coordinator.startToken = startToken
        context.coordinator.startIfNeeded()
        context.coordinator.stopToken = stopToken
        context.coordinator.stopIfNeeded()
        context.coordinator.pauseToken = pauseToken
        context.coordinator.pauseIfNeeded()
    }

    final class Coordinator {
        var arView: ARView?
        var startToken: Int = 0
        var stopToken: Int = 0
        var pauseToken: Int = 0
        private var lastStartToken: Int = 0
        private var lastStopToken: Int = 0
        private var lastPauseToken: Int = 0

        func startIfNeeded() {
            guard startToken != lastStartToken else { return }
            lastStartToken = startToken
            runScanIfPossible()
        }

        func stopIfNeeded() {
            guard stopToken != lastStopToken else { return }
            lastStopToken = stopToken
            runPreviewIfPossible()
        }

        func pauseIfNeeded() {
            guard pauseToken != lastPauseToken else { return }
            lastPauseToken = pauseToken
            arView?.session.pause()
        }

        func runPreviewIfPossible() {
            guard let arView else { return }
            let configuration = ARWorldTrackingConfiguration()
            configuration.environmentTexturing = .automatic
            configuration.planeDetection = [.horizontal, .vertical]
            arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }

        func runScanIfPossible() {
            guard let arView else { return }
            let configuration = ARWorldTrackingConfiguration()
            configuration.sceneReconstruction = .mesh
            configuration.environmentTexturing = .automatic
            configuration.planeDetection = [.horizontal, .vertical]
            arView.session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
        }
    }
}

#Preview {
    LidarScanView()
}
