import SwiftUI
import UIKit
import UniformTypeIdentifiers

/// Thin wrapper over the system camera for recording a walkthrough or taking a photo.
struct CameraPicker: UIViewControllerRepresentable {
    enum Mode { case photo, video }
    enum Result { case photo(UIImage), video(URL), cancelled }

    let mode: Mode
    let onFinish: (Result) -> Void

    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        switch mode {
        case .photo:
            picker.mediaTypes = [UTType.image.identifier]
            picker.cameraCaptureMode = .photo
        case .video:
            picker.mediaTypes = [UTType.movie.identifier]
            picker.cameraCaptureMode = .video
            picker.videoQuality = .typeHigh
            picker.videoMaximumDuration = 10 * 60
        }
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (Result) -> Void
        init(onFinish: @escaping (Result) -> Void) { self.onFinish = onFinish }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let url = info[.mediaURL] as? URL {
                // The system deletes its copy after dismissal; keep our own until the scan finishes.
                let copy = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension(url.pathExtension)
                if (try? FileManager.default.copyItem(at: url, to: copy)) != nil {
                    onFinish(.video(copy))
                } else {
                    onFinish(.video(url))
                }
            } else if let image = info[.originalImage] as? UIImage {
                onFinish(.photo(image))
            } else {
                onFinish(.cancelled)
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(.cancelled)
        }
    }
}
