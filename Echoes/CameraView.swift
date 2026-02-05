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
import Combine

struct CameraView: View {
    @EnvironmentObject var photoStore: PhotoStore
    @StateObject private var locationManager = LocationManager()
    @StateObject private var cameraService = CameraService()
    @State private var showCameraUnavailableAlert = false
    @State private var showLocationUnavailableAlert = false
    @State private var capturedImage: UIImage?

    var body: some View {
        ZStack(alignment: .bottom) {
            GeometryReader { proxy in
                CameraPreview(session: cameraService.session)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .background(.black)
            }
            .ignoresSafeArea()

            if let capturedImage {
                VStack {
                    HStack {
                        Image(uiImage: capturedImage)
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

            Button {
                cameraService.capturePhoto()
            } label: {
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
            .disabled(!cameraService.isReady)
            .opacity(cameraService.isReady ? 1 : 0.4)
        }
        .onAppear {
            locationManager.requestLocation()
            cameraService.requestAccessAndConfigure { available in
                if !available {
                    showCameraUnavailableAlert = true
                }
            }
        }
        .onChange(of: cameraService.lastImage) { _, image in
            guard let image else { return }
            capturedImage = image
            handleCapturedImage(image)
            cameraService.clearLastImage()
        }
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

    func handleCapturedImage(_ image: UIImage) {
        guard let location = locationManager.location else {
            showLocationUnavailableAlert = true
            return
        }

        guard let data = image.jpegData(compressionQuality: 0.8) else { return }

        photoStore.add(imageData: data, location: location)
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
        .environmentObject(PhotoStore())
}
