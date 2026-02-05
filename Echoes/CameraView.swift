//
//  ContentView.swift
//  Echoes
//
//  Created by 古田聖直 on 2026/01/27.
//

import SwiftUI
import CoreLocation
import UIKit
import AVFoundation
import CoreData
import Combine

struct CameraView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @StateObject private var locationManager = LocationManager()
    @StateObject private var cameraService = CameraService()
    @State private var showCameraUnavailableAlert = false
    @State private var showLocationUnavailableAlert = false
    @State private var capturedImage: UIImage?
    @State private var pendingImageData: Data?
    @State private var pendingCapturedAt: Date?

    var body: some View {
        ZStack(alignment: .bottom) {
            CameraPreviewLayer(session: cameraService.session)
            CapturedThumbnail(image: capturedImage)
            CaptureButton(isEnabled: cameraService.isReady, action: capture)
        }
        .ignoresSafeArea()
        .onAppear(perform: startCamera)
        .onDisappear(perform: clearCapturedPreview)
        .onChange(of: locationManager.location) { _, _ in saveIfPossible() }
        .onReceive(locationManager.$locationError) { error in
            handleLocationError(error)
        }
        .onChange(of: cameraService.lastImage) { _, image in handleNewImage(image) }
        .alert("カメラが使えません", isPresented: $showCameraUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("このデバイスではカメラが利用できないか、権限が許可されていません。")
        }
        .alert("位置情報が取得できません", isPresented: $showLocationUnavailableAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("写真に位置情報を付けられないため保存できませんでした。")
        }
    }

    private func startCamera() {
        locationManager.requestLocation()
        cameraService.requestAccessAndConfigure { available in
            if !available {
                showCameraUnavailableAlert = true
            }
        }
    }

    private func clearCapturedPreview() {
        capturedImage = nil
        cameraService.clearLastImage()
    }

    private func capture() {
        pendingCapturedAt = Date()
        locationManager.requestLocation()
        cameraService.capturePhoto()
    }

    private func handleLocationError(_ error: Error?) {
        guard error != nil else { return }
        showLocationUnavailableAlert = true
        pendingImageData = nil
        pendingCapturedAt = nil
    }

    private func handleNewImage(_ image: UIImage?) {
        guard let image else { return }
        capturedImage = image
        handleCapturedImage(image)
        cameraService.clearLastImage()
    }

    func handleCapturedImage(_ image: UIImage) {
        guard let data = image.jpegData(compressionQuality: 0.8) else { return }
        pendingImageData = data
        saveIfPossible()
    }

    private func saveIfPossible() {
        guard let data = pendingImageData, let location = locationManager.location else { return }

        let echo = Echo(context: viewContext)
        echo.id = UUID()
        echo.imageData = data
        echo.createdAt = pendingCapturedAt ?? Date()
        echo.latitude = location.coordinate.latitude
        echo.longitude = location.coordinate.longitude

        do {
            try viewContext.save()
            pendingImageData = nil
            pendingCapturedAt = nil
        } catch {
            print("Failed to save echo:", error.localizedDescription)
        }
    }
}

private struct CameraPreviewLayer: View {
    let session: AVCaptureSession

    var body: some View {
        GeometryReader { proxy in
            CameraPreview(session: session)
                .frame(width: proxy.size.width, height: proxy.size.height)
                .background(.black)
        }
    }
}

private struct CapturedThumbnail: View {
    let image: UIImage?

    var body: some View {
        if let image {
            VStack {
                HStack {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 96, height: 96)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(.white.opacity(0.7), lineWidth: 2)
                        )
                        .shadow(radius: 6)
                    Spacer()
                }
                Spacer()
            }
            .padding(.leading, 16)
            .padding(.top, 24)
        }
    }
}

private struct CaptureButton: View {
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(.white)
                .frame(width: 72, height: 72)
                .overlay(
                    Circle()
                        .stroke(.black.opacity(0.2), lineWidth: 2)
                        .frame(width: 80, height: 80)
                )
        }
        .padding(.bottom, 32)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
    }
}

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.videoPreviewLayer.videoGravity = .resizeAspectFill
        view.videoPreviewLayer.session = session
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.videoPreviewLayer.session = session
    }
}

final class PreviewView: UIView {
    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }

    var videoPreviewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }
}

final class CameraService: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()

    @Published private(set) var isReady = false
    @Published private(set) var lastImage: UIImage?

    private var isConfigured = false

    func requestAccessAndConfigure(completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            configureSessionIfNeeded()
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    if granted {
                        self?.configureSessionIfNeeded()
                        completion(true)
                    } else {
                        completion(false)
                    }
                }
            }
        default:
            completion(false)
        }
    }

    func capturePhoto() {
        guard isReady else { return }
        let settings = AVCapturePhotoSettings()
        output.capturePhoto(with: settings, delegate: self)
    }

    func clearLastImage() {
        lastImage = nil
    }

    private func configureSessionIfNeeded() {
        guard !isConfigured else { return }
        isConfigured = true

        session.beginConfiguration()
        session.sessionPreset = .photo

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            session.commitConfiguration()
            return
        }

        do {
            let input = try AVCaptureDeviceInput(device: device)
            if session.canAddInput(input) {
                session.addInput(input)
            }
            if session.canAddOutput(output) {
                session.addOutput(output)
            }
        } catch {
            session.commitConfiguration()
            return
        }

        session.commitConfiguration()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            self?.session.startRunning()
            DispatchQueue.main.async {
                self?.isReady = true
            }
        }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard error == nil else { return }
        guard let data = photo.fileDataRepresentation(),
              let image = UIImage(data: data) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.lastImage = image
        }
    }
}

#Preview {
    CameraView()
        .environment(\.managedObjectContext, PersistenceController.preview.container.viewContext)
}
