import ReplayKit
import Photos
import UIKit

/// Records a video of the session with ReplayKit and saves it to the photo
/// library. ReplayKit captures the whole display, so the UI hides its chrome
/// while recording for a clean shot. Completions are always delivered on the
/// main queue.
final class ScreenRecorder {

    enum RecorderError: LocalizedError {
        case unavailable
        case noPhotoAccess
        case saveFailed

        var errorDescription: String? {
            switch self {
            case .unavailable:   return "Screen recording unavailable"
            case .noPhotoAccess: return "Photo library access denied"
            case .saveFailed:    return "Couldn't save the video"
            }
        }
    }

    private let recorder = RPScreenRecorder.shared()

    var isRecording: Bool { recorder.isRecording }

    func start(completion: @escaping (Bool) -> Void) {
        guard recorder.isAvailable else {
            DispatchQueue.main.async { completion(false) }
            return
        }
        recorder.isMicrophoneEnabled = true
        recorder.startRecording { error in
            DispatchQueue.main.async { completion(error == nil) }
        }
    }

    func stopAndSave(completion: @escaping (Result<Void, Error>) -> Void) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ARPlayground-\(UUID().uuidString).mov")
        recorder.stopRecording(withOutput: url) { error in
            if let error {
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }
            ScreenRecorder.saveToLibrary(url: url, completion: completion)
        }
    }

    private static func saveToLibrary(url: URL,
                                      completion: @escaping (Result<Void, Error>) -> Void) {
        PHPhotoLibrary.requestAuthorization(for: .addOnly) { status in
            guard status == .authorized || status == .limited else {
                DispatchQueue.main.async { completion(.failure(RecorderError.noPhotoAccess)) }
                return
            }
            PHPhotoLibrary.shared().performChanges {
                PHAssetCreationRequest.creationRequestForAssetFromVideo(atFileURL: url)
            } completionHandler: { success, error in
                try? FileManager.default.removeItem(at: url)
                DispatchQueue.main.async {
                    if success {
                        completion(.success(()))
                    } else {
                        completion(.failure(error ?? RecorderError.saveFailed))
                    }
                }
            }
        }
    }
}
