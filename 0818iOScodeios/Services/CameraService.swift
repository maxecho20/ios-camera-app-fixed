//
//  CameraService.swift
//  打咔 (Daka)
//
//  相机服务 - 处理相机功能
//  Created by CodeBuddy on 2025/8/18.
//

import Foundation
import AVFoundation
import UIKit
import Combine
import SwiftUI

// MARK: - 相机服务错误
enum CameraServiceError: Error, LocalizedError {
    case cameraUnavailable
    case captureSessionNotConfigured
    case imageProcessingFailed
    case sessionNotRunning
    
    var errorDescription: String? {
        switch self {
        case .cameraUnavailable:
            return "相机不可用"
        case .captureSessionNotConfigured:
            return "相机会话未配置"
        case .imageProcessingFailed:
            return "图片处理失败"
        case .sessionNotRunning:
            return "相机会话未运行"
        }
    }
}

// MARK: - 相机服务
class CameraService: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isSessionRunning = false
    @Published var authorizationStatus: AVAuthorizationStatus = .notDetermined
    
    // MARK: - Private Properties
    private let session = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "camera.session.queue")
    
    private var videoDeviceInput: AVCaptureDeviceInput?
    private var photoOutput: AVCapturePhotoOutput?
    
    // MARK: - Initialization
    override init() {
        super.init()
        checkAuthorizationStatus()
    }
    
    // MARK: - Public Methods
    
    /// 检查相机权限状态
    func checkAuthorizationStatus() {
        print("CameraService: 检查相机权限状态")
        authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
        print("CameraService: 当前权限状态: \(authorizationStatus.rawValue)")
    }
    
    /// 请求相机权限
    func requestCameraPermission() async -> Bool {
        print("CameraService: 请求相机权限")
        
        return await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.authorizationStatus = AVCaptureDevice.authorizationStatus(for: .video)
                    print("CameraService: 权限请求结果: \(granted)")
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    /// 启动相机会话
    func startSession() async {
        print("CameraService: 开始启动相机会话")
        
        guard authorizationStatus == .authorized else {
            print("CameraService: 相机权限未授权")
            return
        }
        
        return await withCheckedContinuation { continuation in
            sessionQueue.async { [weak self] in
                guard let self = self else {
                    continuation.resume()
                    return
                }
                
                print("CameraService: 配置相机会话")
                self.setupCaptureSession()
                
                print("CameraService: 启动会话")
                self.session.startRunning()
                
                // 等待会话真正启动
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                    let isRunning = self.session.isRunning
                    print("CameraService: 会话启动完成，运行状态: \(isRunning)")
                    self.isSessionRunning = isRunning
                    continuation.resume()
                }
            }
        }
    }
    
    /// 停止相机会话
    func stopSession() {
        print("CameraService: 停止相机会话")
        sessionQueue.async { [weak self] in
            self?.session.stopRunning()
            DispatchQueue.main.async {
                self?.isSessionRunning = false
            }
        }
    }
    
    /// 拍照
    func capturePhoto() async throws -> UIImage {
        print("CameraService: 开始拍照流程")
        
        guard let photoOutput = photoOutput else {
            print("CameraService: ❌ photoOutput未配置")
            throw CameraServiceError.captureSessionNotConfigured
        }
        
        guard isSessionRunning else {
            print("CameraService: ❌ 相机会话未运行")
            throw CameraServiceError.sessionNotRunning
        }
        
        print("CameraService: ✅ 前置检查通过，开始拍照")
        
        return try await withCheckedThrowingContinuation { continuation in
            let settings = AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg])
            settings.isHighResolutionPhotoEnabled = true
            
            print("CameraService: 创建拍照设置完成")
            
            let delegate = PhotoCaptureDelegate { result in
                switch result {
                case .success(let image):
                    print("CameraService: ✅ 拍照成功，图片尺寸: \(image.size)")
                    continuation.resume(returning: image)
                case .failure(let error):
                    print("CameraService: ❌ 拍照失败: \(error)")
                    continuation.resume(throwing: error)
                }
            }
            
            // 保持delegate的强引用，防止被释放
            objc_setAssociatedObject(photoOutput, "PhotoCaptureDelegate", delegate, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            
            // 确保在主队列中执行拍照
            DispatchQueue.main.async {
                print("CameraService: 执行拍照命令")
                photoOutput.capturePhoto(with: settings, delegate: delegate)
            }
        }
    }
    
    /// 获取预览层
    func getPreviewLayer() -> AVCaptureVideoPreviewLayer {
        let previewLayer = AVCaptureVideoPreviewLayer(session: session)
        previewLayer.videoGravity = .resizeAspectFill
        return previewLayer
    }
    
    // MARK: - Private Methods
    
    /// 配置捕获会话
    private func setupCaptureSession() {
        print("CameraService: 开始配置捕获会话")
        
        session.beginConfiguration()
        
        // 设置会话预设
        if session.canSetSessionPreset(.photo) {
            session.sessionPreset = .photo
            print("CameraService: 设置会话预设为photo")
        }
        
        // 添加视频输入
        setupVideoInput()
        
        // 添加照片输出
        setupPhotoOutput()
        
        session.commitConfiguration()
        print("CameraService: 捕获会话配置完成")
    }
    
    /// 设置视频输入
    private func setupVideoInput() {
        print("CameraService: 配置视频输入")
        
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("CameraService: ❌ 无法获取后置摄像头")
            return
        }
        
        do {
            let videoDeviceInput = try AVCaptureDeviceInput(device: videoDevice)
            
            if session.canAddInput(videoDeviceInput) {
                session.addInput(videoDeviceInput)
                self.videoDeviceInput = videoDeviceInput
                print("CameraService: ✅ 视频输入添加成功")
            } else {
                print("CameraService: ❌ 无法添加视频输入")
            }
        } catch {
            print("CameraService: ❌ 创建视频输入失败: \(error)")
        }
    }
    
    /// 设置照片输出
    private func setupPhotoOutput() {
        print("CameraService: 配置照片输出")
        
        let photoOutput = AVCapturePhotoOutput()
        
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
            self.photoOutput = photoOutput
            
            // 配置照片输出设置
            photoOutput.isHighResolutionCaptureEnabled = true
            if photoOutput.isLivePhotoCaptureSupported {
                photoOutput.isLivePhotoCaptureEnabled = false
            }
            
            print("CameraService: ✅ 照片输出添加成功")
        } else {
            print("CameraService: ❌ 无法添加照片输出")
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraService: AVCaptureVideoDataOutputSampleBufferDelegate {
    
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // 处理视频帧数据（如果需要实时处理）
    }
}