//
//  LidarScanView.swift
//  Echoes
//
//  Created by Codex on 2026/02/05.
//

import SwiftUI
import ARKit
import RealityKit
import CoreData
import CoreLocation
import SceneKit
import UIKit

struct LidarScanView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var locationManager = LocationManager()
    @State private var isScanning = false
    @State private var startToken = 0
    @State private var stopToken = 0
    @State private var pauseToken = 0
    @State private var canStop = false
    @State private var minDurationTask: Task<Void, Never>?
    @State private var exportToken = 0
    @State private var isExporting = false
    @State private var exportError: String?
    @State private var showLocationUnavailableAlert = false
    @State private var pendingScanURL: URL?

    var body: some View {
        ZStack(alignment: .bottom) {
            LidarARViewContainer(
                startToken: $startToken,
                stopToken: $stopToken,
                pauseToken: $pauseToken,
                exportToken: $exportToken
            ) { result in
                isExporting = false
                switch result {
                case .success(let url):
                    saveScan(url: url)
                case .failure(let error):
                    exportError = error.localizedDescription
                }
            }
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
        .onReceive(locationManager.$location) { _ in
            savePendingScanIfPossible()
        }
        .overlay {
            if isExporting {
                ZStack {
                    Color.black.opacity(0.35)
                        .ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                            .progressViewStyle(.circular)
                        Text("書き出し中…")
                            .font(.headline)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .transition(.opacity)
            }
        }
        .allowsHitTesting(!isExporting)
        .alert("位置情報が取得できません", isPresented: $showLocationUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("3Dスキャンに位置情報を付けられないため保存できませんでした。")
        }
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
        exportError = nil
        print("[Scan] startScan")
        locationManager.requestLocation()
        startMinDurationTimer()
    }

    private func stopScanIfPossible() {
        guard canStop else { return }
        isScanning = false
        canStop = false
        print("[Scan] stopScan requested")
        pauseToken += 1
        cancelMinDurationTimer()
        isExporting = true
        locationManager.requestLocation()
        exportToken += 1
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

    private func saveScan(url: URL) {
        guard let location = locationManager.location else {
            print("[Scan] location missing, pending save. url=\(url.path)")
            pendingScanURL = url
            showLocationUnavailableAlert = true
            return
        }

        print("[Scan] saving scan. url=\(url.path) lat=\(location.coordinate.latitude) lon=\(location.coordinate.longitude)")
        let echo = Echo(context: viewContext)
        echo.id = UUID()
        echo.scanLocalURL = url.path
        echo.createdAt = Date()
        echo.latitude = location.coordinate.latitude
        echo.longitude = location.coordinate.longitude

        do {
            try viewContext.save()
            pendingScanURL = nil
            print("[Scan] save success")
        } catch {
            print("Failed to save scan:", error.localizedDescription)
        }
    }

    private func savePendingScanIfPossible() {
        guard let url = pendingScanURL else { return }
        guard locationManager.location != nil else { return }
        print("[Scan] location arrived, saving pending scan")
        saveScan(url: url)
    }
}

private struct LidarARViewContainer: UIViewRepresentable {
    @Binding var startToken: Int
    @Binding var stopToken: Int
    @Binding var pauseToken: Int
    @Binding var exportToken: Int
    let onExport: (Result<URL, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onExport: onExport)
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
        context.coordinator.exportToken = exportToken
        context.coordinator.exportIfNeeded()
    }

    final class Coordinator {
        var arView: ARView?
        var startToken: Int = 0
        var stopToken: Int = 0
        var pauseToken: Int = 0
        var exportToken: Int = 0
        private var lastStartToken: Int = 0
        private var lastStopToken: Int = 0
        private var lastPauseToken: Int = 0
        private var lastExportToken: Int = 0
        private let onExport: (Result<URL, Error>) -> Void

        init(onExport: @escaping (Result<URL, Error>) -> Void) {
            self.onExport = onExport
        }

        func startIfNeeded() {
            guard startToken != lastStartToken else { return }
            lastStartToken = startToken
            print("[Scan] AR session start")
            runScanIfPossible()
        }

        func stopIfNeeded() {
            guard stopToken != lastStopToken else { return }
            lastStopToken = stopToken
            print("[Scan] AR session stop -> preview")
            runPreviewIfPossible()
        }

        func pauseIfNeeded() {
            guard pauseToken != lastPauseToken else { return }
            lastPauseToken = pauseToken
            print("[Scan] AR session pause")
            arView?.session.pause()
        }

        func exportIfNeeded() {
            guard exportToken != lastExportToken else { return }
            lastExportToken = exportToken
            print("[Scan] export start")
            exportCurrentMesh()
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

        private func exportCurrentMesh() {
            guard let arView else {
                print("[Scan] export failed: missing ARView")
                onExport(.failure(ScanExportError.missingARView))
                return
            }
            guard let frame = arView.session.currentFrame else {
                print("[Scan] export failed: missing frame")
                onExport(.failure(ScanExportError.missingFrame))
                return
            }

            let meshAnchors = frame.anchors.compactMap { $0 as? ARMeshAnchor }
            guard let anchor = meshAnchors.max(by: { $0.geometry.vertices.count < $1.geometry.vertices.count }) else {
                print("[Scan] export failed: no mesh anchors")
                onExport(.failure(ScanExportError.noMeshFound))
                return
            }

            let scene = SCNScene()
            let node = SCNNode()

            let viewportSize = arView.bounds.size == .zero ? UIScreen.main.bounds.size : arView.bounds.size
            let orientation = arView.window?.windowScene?.interfaceOrientation ?? .portrait
            let colorInfo = frame.capturedImage.toCGImage().map {
                MeshColorInfo(image: $0, viewportSize: viewportSize, orientation: orientation, camera: frame.camera)
            }

            node.geometry = anchor.geometry.toSCNGeometry(
                colorInfo: colorInfo,
                transform: anchor.transform
            )
            node.transform = SCNMatrix4(anchor.transform)
            scene.rootNode.addChildNode(node)

            do {
                let scansURL = try FileManager.default.ensureScansDirectory()
                let fileName = "scan-\(UUID().uuidString).usdz"
                let url = scansURL.appendingPathComponent(fileName)
                try scene.write(to: url, options: nil, delegate: nil, progressHandler: nil)
                print("[Scan] export success: \(url.path)")
                onExport(.success(url))
            } catch {
                print("[Scan] export failed: \(error.localizedDescription)")
                onExport(.failure(error))
            }
        }
    }
}

private enum ScanExportError: LocalizedError {
    case missingARView
    case missingFrame
    case noMeshFound

    var errorDescription: String? {
        switch self {
        case .missingARView:
            return "スキャン画面の初期化に失敗しました。"
        case .missingFrame:
            return "フレーム情報を取得できませんでした。"
        case .noMeshFound:
            return "まだスキャン情報がありません。少し動いてから停止してください。"
        }
    }
}

private struct MeshColorInfo {
    let image: CGImage
    let viewportSize: CGSize
    let orientation: UIInterfaceOrientation
    let camera: ARCamera
}

private extension ARMeshGeometry {
    func toSCNGeometry(
        colorInfo: MeshColorInfo?,
        transform: simd_float4x4
    ) -> SCNGeometry {
        let vertexData = dataCopy(
            buffer: vertices.buffer,
            offset: vertices.offset,
            length: vertices.count * vertices.stride
        )
        let normalData = dataCopy(
            buffer: normals.buffer,
            offset: normals.offset,
            length: normals.count * normals.stride
        )
        let indexData = dataCopy(
            buffer: faces.buffer,
            offset: 0,
            length: faces.count * faces.indexCountPerPrimitive * faces.bytesPerIndex
        )

        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: vertices.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: vertices.stride
        )

        let normalSource = SCNGeometrySource(
            data: normalData,
            semantic: .normal,
            vectorCount: normals.count,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.size,
            dataOffset: 0,
            dataStride: normals.stride
        )

        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: faces.count,
            bytesPerIndex: faces.bytesPerIndex
        )

        var sources: [SCNGeometrySource] = [vertexSource, normalSource]
        if let colorInfo, let colorSource = makeColorSource(info: colorInfo, transform: transform) {
            sources.append(colorSource)
        }

        let geometry = SCNGeometry(sources: sources, elements: [element])
        geometry.firstMaterial = SCNMaterial()
        geometry.firstMaterial?.diffuse.contents = UIColor.white
        geometry.firstMaterial?.lightingModel = .constant
        geometry.firstMaterial?.isDoubleSided = true
        return geometry
    }

    private func dataCopy(buffer: MTLBuffer, offset: Int, length: Int) -> Data {
        let pointer = buffer.contents().advanced(by: offset)
        return Data(bytes: pointer, count: length)
    }

    private func makeColorSource(
        info: MeshColorInfo,
        transform: simd_float4x4
    ) -> SCNGeometrySource? {
        guard let imageData = info.image.rgba8Data() else { return nil }
        let width = info.image.width
        let height = info.image.height
        let count = vertices.count

        let colorStride = 4
        var colorBytes = [UInt8](repeating: 255, count: count * colorStride)

        for index in 0..<count {
            let vertexPtr = vertices.buffer.contents()
                .advanced(by: vertices.offset + index * vertices.stride)
                .assumingMemoryBound(to: SIMD3<Float>.self)
            let local = SIMD4<Float>(vertexPtr.pointee, 1)
            let world = transform * local
            let projected = info.camera.projectPoint(
                SIMD3<Float>(world.x, world.y, world.z),
                orientation: info.orientation,
                viewportSize: info.viewportSize
            )

            let u = projected.x / info.viewportSize.width
            let v = projected.y / info.viewportSize.height
            let x = Int((u * CGFloat(width)).rounded(.down))
            let y = Int((v * CGFloat(height)).rounded(.down))

            let clampedX = max(0, min(width - 1, x))
            let clampedY = max(0, min(height - 1, y))
            let pixelOffset = (clampedY * width + clampedX) * 4
            let dst = index * colorStride

            colorBytes[dst + 0] = imageData[pixelOffset + 0]
            colorBytes[dst + 1] = imageData[pixelOffset + 1]
            colorBytes[dst + 2] = imageData[pixelOffset + 2]
            colorBytes[dst + 3] = 255
        }

        let colorData = Data(colorBytes)
        return SCNGeometrySource(
            data: colorData,
            semantic: .color,
            vectorCount: count,
            usesFloatComponents: false,
            componentsPerVector: 4,
            bytesPerComponent: MemoryLayout<UInt8>.size,
            dataOffset: 0,
            dataStride: colorStride
        )
    }
}

private extension FileManager {
    func ensureScansDirectory() throws -> URL {
        let documents = try url(
            for: .documentDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let scans = documents.appendingPathComponent("scans", isDirectory: true)
        if !fileExists(atPath: scans.path) {
            try createDirectory(at: scans, withIntermediateDirectories: true)
        }
        return scans
    }
}

private extension CVPixelBuffer {
    func toCGImage() -> CGImage? {
        let ciImage = CIImage(cvPixelBuffer: self)
        let context = CIContext()
        return context.createCGImage(ciImage, from: ciImage.extent)
    }
}

private extension CGImage {
    func rgba8Data() -> [UInt8]? {
        let width = self.width
        let height = self.height
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        var data = [UInt8](repeating: 0, count: width * height * bytesPerPixel)

        guard let context = CGContext(
            data: &data,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.draw(self, in: CGRect(x: 0, y: 0, width: width, height: height))
        return data
    }
}


#Preview {
    LidarScanView()
}
