import Foundation
import AVFoundation
import CoreImage
import UIKit // For UIImage to handle JPEG conversion

class UVCVideoReceiver: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published var receivedFrameData = Data()
    
    private var captureSession: AVCaptureSession?
    private var videoOutput: AVCaptureVideoDataOutput?
    private let queue = DispatchQueue(label: "UVCVideoQueue")
    
    override init() {
        super.init()
        setupCaptureSession()
    }
    
    private func setupCaptureSession() {
        captureSession = AVCaptureSession()
        
        // Discover connected UVC devices via Developer Strap
        let discoverySession = AVCaptureDevice.DiscoverySession(
            deviceTypes: [.external],
            mediaType: .video,
            position: .unspecified
        )
        
        guard let uvcDevice = discoverySession.devices.first else {
            print("No UVC device found. Ensure Developer Strap is connected and device is attached.")
            return
        }
        
        do {
            let input = try AVCaptureDeviceInput(device: uvcDevice)
            if captureSession?.canAddInput(input) == true {
                captureSession?.addInput(input)
            } else {
                print("Failed to add input to capture session.")
                return
            }
            
            videoOutput = AVCaptureVideoDataOutput()
            videoOutput?.setSampleBufferDelegate(self, queue: queue)
            if captureSession?.canAddOutput(videoOutput!) == true {
                captureSession?.addOutput(videoOutput!)
            } else {
                print("Failed to add output to capture session.")
                return
            }
            
            captureSession?.startRunning()
            print("Capture session started for UVC device.")
        } catch {
            print("Error setting up capture session: \(error)")
        }
    }
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        
        // Convert CVPixelBuffer to JPEG Data using UIImage
        let ciImage = CIImage(cvPixelBuffer: pixelBuffer)
        let uiImage = UIImage(ciImage: ciImage)
        if let jpegData = uiImage.jpegData(compressionQuality: 0.8), !jpegData.isEmpty {
            DispatchQueue.main.async { [weak self] in
                self?.receivedFrameData = jpegData
            }
        }
    }
    
    deinit {
        captureSession?.stopRunning()
    }
}
