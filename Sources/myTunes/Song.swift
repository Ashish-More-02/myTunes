import Foundation
import AVFoundation
import AppKit

struct Song: Identifiable, Hashable, Codable {
    let id: URL
    var url: URL { id }
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    var artwork: NSImage?

    enum CodingKeys: String, CodingKey {
        case id, title, artist, album, duration
    }

    init(id: URL, title: String, artist: String, album: String, duration: TimeInterval, artwork: NSImage?) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.artwork = artwork
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(URL.self, forKey: .id)
        self.title = try c.decode(String.self, forKey: .title)
        self.artist = try c.decode(String.self, forKey: .artist)
        self.album = try c.decode(String.self, forKey: .album)
        self.duration = try c.decode(TimeInterval.self, forKey: .duration)
        self.artwork = nil
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encode(artist, forKey: .artist)
        try c.encode(album, forKey: .album)
        try c.encode(duration, forKey: .duration)
    }

    static func == (lhs: Song, rhs: Song) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    static func load(from url: URL) async -> Song {
        let asset = AVURLAsset(url: url)
        var title = url.deletingPathExtension().lastPathComponent
        var artist = "Unknown Artist"
        var album = ""
        var artwork: NSImage?
        var duration: TimeInterval = 0

        if let d = try? await asset.load(.duration).seconds, d.isFinite, !d.isNaN {
            duration = d
        }

        if let metadata = try? await asset.load(.commonMetadata) {
            for item in metadata {
                guard let key = item.commonKey?.rawValue else { continue }
                switch key {
                case "title":
                    if let v = try? await item.load(.stringValue), !v.isEmpty { title = v }
                case "artist":
                    if let v = try? await item.load(.stringValue), !v.isEmpty { artist = v }
                case "albumName":
                    if let v = try? await item.load(.stringValue) { album = v }
                case "artwork":
                    if let d = try? await item.load(.dataValue), let img = NSImage(data: d) {
                        artwork = img
                    }
                default:
                    break
                }
            }
        }

        return Song(id: url, title: title, artist: artist, album: album, duration: duration, artwork: artwork)
    }

    static func loadArtwork(from url: URL) async -> NSImage? {
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.load(.commonMetadata) else { return nil }
        for item in metadata where item.commonKey?.rawValue == "artwork" {
            if let d = try? await item.load(.dataValue), let img = NSImage(data: d) {
                return img
            }
        }
        return nil
    }
}
