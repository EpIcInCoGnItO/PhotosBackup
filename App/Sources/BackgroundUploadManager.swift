import Foundation
import UIKit

final class BackgroundUploadManager: NSObject {
    static let shared = BackgroundUploadManager()
    
    private var session: URLSession!
    var backgroundCompletionHandler: (() -> Void)?
    
    private override init() {
        super.init()
        let identifier = "com.photosbackup.backgroundsession"
        let config = URLSessionConfiguration.background(withIdentifier: identifier)
        
        // Allows OS to schedule uploads efficiently based on power & connectivity
        config.isDiscretionary = false 
        config.sessionSendsLaunchEvents = true
        
        // Re-attaches to existing tasks if the app was recreated in the background
        self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }
    
    /// Enqueues a local file for background upload
    func uploadMedia(fileURL: URL, targetEndpoint: URL, authToken: String) -> URLSessionUploadTask {
        var request = URLRequest(url: targetEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(authToken)", forHTTPHeaderField: "Authorization")
        
        // Background sessions strictly require file URLs (Data payloads will crash background sessions)
        let uploadTask = session.uploadTask(with: request, fromFile: fileURL)
        uploadTask.resume()
        return uploadTask
    }
}

// MARK: - URLSessionTaskDelegate & URLSessionDelegate
extension BackgroundUploadManager: URLSessionTaskDelegate, URLSessionDelegate {
    
    // Updates progress state (called even if task began while app was suspended)
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        let progress = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        print("Task \(task.taskIdentifier) progress: \(Int(progress * 100))%")
    }
    
    // Handles task completion or network failure
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error = error {
            print("Upload failed for Task \(task.taskIdentifier): \(error.localizedDescription)")
            // Mark task as failed in SwiftData/SQLite queue for re-try
        } else {
            print("Upload succeeded for Task \(task.taskIdentifier)")
            // Update local asset status to 'uploaded'
        }
    }
    
    // Notifies system that all background events are finished so snapshot can be updated
    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        DispatchQueue.main.async { [weak self] in
            guard let completionHandler = self?.backgroundCompletionHandler else { return }
            self?.backgroundCompletionHandler = nil
            completionHandler()
        }
    }
}
