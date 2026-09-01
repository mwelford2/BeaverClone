import Foundation
import AVFoundation
import CoreMedia

public enum AudioSplitterError: LocalizedError {
    case emptyAsset
    case exportFailed(String?)

    public var errorDescription: String? {
        switch self {
        case .emptyAsset:
            return "The recording appears to be empty."
        case .exportFailed(let reason):
            return reason ?? "Couldn't split the recording into parts."
        }
    }
}

/// Splits long recordings into consecutive .m4a chunks so they stay under transcription
/// APIs' per-request size limits (e.g. OpenAI Whisper's 25MB cap) and so each upload finishes
/// quickly enough to avoid the request timing out on a single, hours-long file.
public enum AudioSplitter {

    public struct Chunk {
        public let url: URL
        /// Where this chunk starts within the original recording, used to offset its
        /// per-word timestamps back onto the full recording's timeline.
        public let startTime: TimeInterval
        public let duration: TimeInterval
    }

    /// Splits `sourceURL` into chunks no longer than `maxChunkDuration`. When the recording
    /// already fits in one chunk, returns it unsplit (pointing at `sourceURL` itself, not a copy)
    /// so short recordings skip the re-encoding round trip entirely.
    ///
    /// Chunk files are written to the temporary directory; the caller owns deleting them.
    public static func split(sourceURL: URL, maxChunkDuration: TimeInterval) async throws -> [Chunk] {
        let asset = AVURLAsset(url: sourceURL)
        let totalDuration = try await asset.load(.duration).seconds
        guard totalDuration.isFinite, totalDuration > 0 else {
            throw AudioSplitterError.emptyAsset
        }

        guard totalDuration > maxChunkDuration else {
            return [Chunk(url: sourceURL, startTime: 0, duration: totalDuration)]
        }

        var chunks: [Chunk] = []
        var start: TimeInterval = 0
        while start < totalDuration {
            let end = min(start + maxChunkDuration, totalDuration)
            let outputURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(UUID().uuidString).m4a")

            guard let export = AVAssetExportSession(asset: asset, presetName: AVAssetExportPresetAppleM4A) else {
                throw AudioSplitterError.exportFailed(nil)
            }
            export.outputURL = outputURL
            export.outputFileType = .m4a
            export.timeRange = CMTimeRange(
                start: CMTime(seconds: start, preferredTimescale: 600),
                end: CMTime(seconds: end, preferredTimescale: 600)
            )

            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                export.exportAsynchronously {
                    if export.status == .completed {
                        continuation.resume()
                    } else {
                        continuation.resume(throwing: AudioSplitterError.exportFailed(export.error?.localizedDescription))
                    }
                }
            }

            chunks.append(Chunk(url: outputURL, startTime: start, duration: end - start))
            start = end
        }

        return chunks
    }
}
