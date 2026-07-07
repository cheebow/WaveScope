import Foundation
import AVFoundation

/// 音声ファイルのメタデータ(タグ)。ID3 / iTunes / 共通キーから読み取る。
/// 値が無いフィールドは nil。
nonisolated struct AudioMetadata: Sendable, Equatable {
    var title: String?
    var artist: String?
    var album: String?
    var genre: String?
    var year: String?
    /// BPM タグ(ID3 TBPM / iTunes tempo)。未設定を 0 で埋めるタグ付けソフトが
    /// あるため、妥当な範囲(20〜999)の値だけを保持する
    var bpm: Double?

    var isEmpty: Bool {
        title == nil && artist == nil && album == nil
            && genre == nil && year == nil && bpm == nil
    }

    static func load(from url: URL) async throws -> AudioMetadata {
        let asset = AVURLAsset(url: url)
        async let commonLoad = asset.load(.commonMetadata)
        async let allLoad = asset.load(.metadata)
        let common = try await commonLoad
        let all = try await allLoad

        var metadata = AudioMetadata()
        metadata.title = await firstString(in: common, commonKey: .commonKeyTitle)
        metadata.artist = await firstString(in: common, commonKey: .commonKeyArtist)
        metadata.album = await firstString(in: common, commonKey: .commonKeyAlbumName)
        metadata.genre = await firstString(in: all, identifiers: [
            .id3MetadataContentType, .iTunesMetadataUserGenre, .iTunesMetadataPredefinedGenre,
        ])
        var year = await firstString(in: all, identifiers: [
            .id3MetadataRecordingTime, .id3MetadataYear, .iTunesMetadataReleaseDate,
        ])
        if year == nil {
            year = await firstString(in: common, commonKey: .commonKeyCreationDate)
        }
        metadata.year = year
        metadata.bpm = await bpmValue(in: all)
        return metadata
    }

    private static func firstString(
        in items: [AVMetadataItem], commonKey: AVMetadataKey
    ) async -> String? {
        for item in AVMetadataItem.metadataItems(from: items, withKey: commonKey, keySpace: .common) {
            if let value = try? await item.load(.stringValue), !value.isEmpty {
                return value
            }
        }
        return nil
    }

    private static func firstString(
        in items: [AVMetadataItem], identifiers: [AVMetadataIdentifier]
    ) async -> String? {
        for identifier in identifiers {
            for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
                if let value = try? await item.load(.stringValue), !value.isEmpty {
                    return value
                }
            }
        }
        return nil
    }

    private static func bpmValue(in items: [AVMetadataItem]) async -> Double? {
        let identifiers: [AVMetadataIdentifier] = [
            .id3MetadataBeatsPerMinute,
            .iTunesMetadataBeatsPerMin,
        ]
        for identifier in identifiers {
            for item in AVMetadataItem.metadataItems(from: items, filteredByIdentifier: identifier) {
                guard let value = try? await item.load(.value) else { continue }
                let bpm: Double?
                if let number = value as? NSNumber {
                    bpm = number.doubleValue
                } else if let string = value as? String {
                    bpm = Double(string.trimmingCharacters(in: .whitespaces))
                } else {
                    bpm = nil
                }
                if let bpm, (20...999).contains(bpm) { return bpm }
            }
        }
        return nil
    }
}
