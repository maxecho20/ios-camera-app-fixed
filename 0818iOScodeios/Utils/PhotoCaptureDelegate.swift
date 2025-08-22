//
//  PhotoCaptureDelegate.swift
//  打咔 (Daka)
//
//  拍照代理 - 处理拍照回调
//  Created by CodeBuddy on 2025/8/18.
//

import Foundation
import AVFoundation
import UIKit

class PhotoCaptureDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    
    private let completion: (Result<UIImage, Error>) -> Void
    private var hasCompleted = false
    
    init(completion: @escaping (Result<UIImage, Error>) -> Void) {
        self.completion = completion
        super.init()
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        print("PhotoCaptureDelegate: 拍照完成回调")
        
        // 防止重复调用completion
        guard !hasCompleted else {
            print("PhotoCaptureDelegate: ⚠️ 重复回调，忽略")
            return
        }
        hasCompleted = true
        
        // 清理关联对象
        defer {
            objc_setAssociatedObject(output, "PhotoCaptureDelegate", nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
        
        if let error = error {
            print("PhotoCaptureDelegate: ❌ 拍照错误: \(error)")
            completion(.failure(error))
            return
        }
        
        guard let imageData = photo.fileDataRepresentation() else {
            print("PhotoCaptureDelegate: ❌ 无法获取图片数据")
            completion(.failure(CameraServiceError.imageProcessingFailed))
            return
        }
        
        print("PhotoCaptureDelegate: ✅ 获取到图片数据，大小: \(imageData.count) bytes")
        
        guard let image = UIImage(data: imageData) else {
            print("PhotoCaptureDelegate: ❌ 无法创建UIImage")
            completion(.failure(CameraServiceError.imageProcessingFailed))
            return
        }
        
        print("PhotoCaptureDelegate: ✅ 成功创建UIImage，尺寸: \(image.size)")
        completion(.success(image))
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, didCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        print("PhotoCaptureDelegate: 拍照开始")
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        print("PhotoCaptureDelegate: 即将开始拍照")
    }
    
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        print("PhotoCaptureDelegate: 即将拍照")
    }
}