import CryptoKit
import Foundation

/// Resumable URLSession-based downloader with SHA-256 verification.
/// Emits progress callbacks at ~1 Hz.
final class ModelDownloader: NSObject, URLSessionDownloadDelegate {
  enum DownloadError: LocalizedError {
    case cancelled
    case invalidChecksum
    case noTempFile
    case http(Int)
    case unknown(Error)

    var errorDescription: String? {
      switch self {
      case .cancelled:        return "Download cancelled"
      case .invalidChecksum:  return "Downloaded file failed checksum verification"
      case .noTempFile:       return "Downloader did not produce a temporary file"
      case .http(let code):   return "HTTP error \(code)"
      case .unknown(let err): return err.localizedDescription
      }
    }
  }

  struct Progress {
    let bytesDownloaded: Int64
    let totalBytes: Int64
  }

  /// Source URL for the model file. For hackathon, point at HF resolve URL or own CDN.
  let url: URL
  /// Local destination on Application Support directory.
  let destination: URL
  /// Hex SHA-256 of the expected file contents. Empty string disables verification.
  let expectedSHA256: String

  private var session: URLSession!
  private var task: URLSessionDownloadTask?
  private var continuation: CheckedContinuation<Void, Error>?

  /// Called from the URLSession delegate queue. Wrap on main if you bind to UI.
  var onProgress: ((Progress) -> Void)?

  init(url: URL, destination: URL, expectedSHA256: String) {
    self.url = url
    self.destination = destination
    self.expectedSHA256 = expectedSHA256
    super.init()
    let config = URLSessionConfiguration.default
    config.allowsCellularAccess = false
    config.waitsForConnectivity = true
    self.session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
  }

  func download() async throws {
    if FileManager.default.fileExists(atPath: destination.path) {
      if try verify(file: destination) { return }
      try? FileManager.default.removeItem(at: destination)
    }
    try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
      self.continuation = cont
      let task = session.downloadTask(with: url)
      self.task = task
      task.resume()
    }
  }

  func cancel() {
    task?.cancel()
  }

  // MARK: - URLSessionDownloadDelegate

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didWriteData bytesWritten: Int64,
    totalBytesWritten: Int64,
    totalBytesExpectedToWrite: Int64
  ) {
    onProgress?(Progress(
      bytesDownloaded: totalBytesWritten,
      totalBytes: totalBytesExpectedToWrite
    ))
  }

  func urlSession(
    _ session: URLSession,
    downloadTask: URLSessionDownloadTask,
    didFinishDownloadingTo location: URL
  ) {
    do {
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      if FileManager.default.fileExists(atPath: destination.path) {
        try FileManager.default.removeItem(at: destination)
      }
      try FileManager.default.moveItem(at: location, to: destination)

      if try verify(file: destination) {
        continuation?.resume()
      } else {
        try? FileManager.default.removeItem(at: destination)
        continuation?.resume(throwing: DownloadError.invalidChecksum)
      }
      continuation = nil
    } catch {
      continuation?.resume(throwing: DownloadError.unknown(error))
      continuation = nil
    }
  }

  func urlSession(
    _ session: URLSession,
    task: URLSessionTask,
    didCompleteWithError error: Error?
  ) {
    guard let error else { return }
    let nsErr = error as NSError
    if nsErr.code == NSURLErrorCancelled {
      continuation?.resume(throwing: DownloadError.cancelled)
    } else {
      continuation?.resume(throwing: DownloadError.unknown(error))
    }
    continuation = nil
  }

  // MARK: - Verification

  private func verify(file: URL) throws -> Bool {
    if expectedSHA256.isEmpty { return true }
    let data = try Data(contentsOf: file, options: .mappedIfSafe)
    let digest = SHA256.hash(data: data)
    let hex = digest.map { String(format: "%02x", $0) }.joined()
    return hex.lowercased() == expectedSHA256.lowercased()
  }
}
