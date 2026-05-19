import SwiftUI
import AVFoundation
import AppKit

struct FolderNode: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let name: String
    let isRoot: Bool
    let subfolders: [FolderNode]
    let songs: [Song]

    var totalSongCount: Int {
        songs.count + subfolders.reduce(0) { $0 + $1.totalSongCount }
    }
}

@MainActor
final class MusicPlayer: NSObject, ObservableObject {
    @Published var songs: [Song] = []
    @Published var folders: [URL] = []
    @Published var folderOrder: [URL: [URL]] = [:]
    @Published var selectedFolderURL: URL? = nil {
        didSet { persistSelection() }
    }
    @Published var playbackQueue: [Song] = []
    @Published var currentIndex: Int? = nil
    @Published var isPlaying = false
    @Published var currentTime: TimeInterval = 0
    @Published var folderURL: URL? = nil
    @Published var isLoading = false
    @Published var volume: Float = 0.8 {
        didSet { player?.volume = volume }
    }
    @Published var autoWatchEnabled: Bool = true {
        didSet {
            if autoWatchEnabled { startWatching() } else { stopWatching() }
        }
    }

    private static let selectedFolderURLKey = "selectedFolderURL"
    private static let folderOrderKey = "folderOrder"
    private static let songOrderKey = "songOrder"
    static let defaultVolumeKey = "defaultVolume"

    @Published var songOrder: [URL: [URL]] = [:]
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var watcher: FolderWatcher?

    private let supportedExtensions: Set<String> = ["mp3", "m4a", "wav", "aac", "flac", "aiff", "aif"]

    var currentSong: Song? {
        guard let i = currentIndex, playbackQueue.indices.contains(i) else { return nil }
        return playbackQueue[i]
    }

    var displayedSongs: [Song] {
        let raw: [Song]
        if let url = selectedFolderURL {
            let prefix = url.path + "/"
            raw = songs.filter { $0.url.path.hasPrefix(prefix) }
        } else {
            raw = songs
        }
        return applySongOrder(to: raw, key: displayedScopeKey)
    }

    var displayedScopeKey: URL {
        selectedFolderURL ?? (folderURL ?? URL(fileURLWithPath: "/"))
    }

    private func applySongOrder(to list: [Song], key: URL) -> [Song] {
        guard let order = songOrder[key], !order.isEmpty else { return list }
        let byURL = Dictionary(uniqueKeysWithValues: list.map { ($0.url, $0) })
        var result: [Song] = []
        var seen = Set<URL>()
        for u in order {
            if let s = byURL[u] {
                result.append(s)
                seen.insert(u)
            }
        }
        for s in list where !seen.contains(s.url) {
            result.append(s)
        }
        return result
    }

    var selectedFolderName: String? {
        guard let url = selectedFolderURL else { return nil }
        return url.lastPathComponent
    }

    var tree: FolderNode? {
        guard let root = folderURL else { return nil }
        return buildNode(url: root, isRoot: true)
    }

    func songsRecursivelyIn(_ folder: URL) -> [Song] {
        if folder == folderURL { return songs }
        let prefix = folder.path + "/"
        return songs.filter { $0.url.path.hasPrefix(prefix) }
    }

    private func buildNode(url: URL, isRoot: Bool) -> FolderNode {
        let childFolders = subfoldersOf(url)
        let ordered = orderedChildren(of: url, candidates: childFolders)
        let immediateSongs = songs
            .filter { $0.url.deletingLastPathComponent().path == url.path }
            .sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
        return FolderNode(
            url: url,
            name: url.lastPathComponent,
            isRoot: isRoot,
            subfolders: ordered.map { buildNode(url: $0, isRoot: false) },
            songs: immediateSongs
        )
    }

    private func subfoldersOf(_ parent: URL) -> [URL] {
        folders.filter { $0.deletingLastPathComponent().path == parent.path }
    }

    private func orderedChildren(of parent: URL, candidates: [URL]) -> [URL] {
        let saved = folderOrder[parent] ?? []
        let candidateSet = Set(candidates)
        var result: [URL] = []
        var seen = Set<URL>()
        for u in saved where candidateSet.contains(u) {
            result.append(u)
            seen.insert(u)
        }
        let leftover = candidates
            .filter { !seen.contains($0) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        result.append(contentsOf: leftover)
        return result
    }

    override init() {
        super.init()
        loadSelection()
        loadFolderOrder()
        loadSongOrder()
        loadDefaultVolume()
        if let snapshot = LibraryStore.shared.load() {
            folderURL = snapshot.folderURL
            songs = snapshot.songs
            deriveFoldersFromSongs()
            if folderURL != nil {
                Task { @MainActor in
                    await rescan()
                    if autoWatchEnabled { startWatching() }
                }
            }
        }
    }

    private func loadDefaultVolume() {
        let defaults = UserDefaults.standard
        if defaults.object(forKey: Self.defaultVolumeKey) == nil { return }
        let v = defaults.double(forKey: Self.defaultVolumeKey)
        volume = Float(min(max(0, v), 1))
    }

    private func loadSelection() {
        let s = UserDefaults.standard.string(forKey: Self.selectedFolderURLKey) ?? ""
        if s.isEmpty { selectedFolderURL = nil }
        else { selectedFolderURL = URL(fileURLWithPath: s) }
    }

    private func persistSelection() {
        UserDefaults.standard.set(selectedFolderURL?.path ?? "", forKey: Self.selectedFolderURLKey)
    }

    private func loadFolderOrder() {
        guard let dict = UserDefaults.standard.dictionary(forKey: Self.folderOrderKey) as? [String: [String]] else { return }
        var result: [URL: [URL]] = [:]
        for (k, v) in dict {
            result[URL(fileURLWithPath: k)] = v.map { URL(fileURLWithPath: $0) }
        }
        folderOrder = result
    }

    private func saveFolderOrder() {
        var dict: [String: [String]] = [:]
        for (k, v) in folderOrder {
            dict[k.path] = v.map { $0.path }
        }
        UserDefaults.standard.set(dict, forKey: Self.folderOrderKey)
    }

    private func loadSongOrder() {
        guard let dict = UserDefaults.standard.dictionary(forKey: Self.songOrderKey) as? [String: [String]] else { return }
        var result: [URL: [URL]] = [:]
        for (k, v) in dict {
            result[URL(fileURLWithPath: k)] = v.map { URL(fileURLWithPath: $0) }
        }
        songOrder = result
    }

    private func saveSongOrder() {
        var dict: [String: [String]] = [:]
        for (k, v) in songOrder {
            dict[k.path] = v.map { $0.path }
        }
        UserDefaults.standard.set(dict, forKey: Self.songOrderKey)
    }

    private func deriveFoldersFromSongs() {
        guard let root = folderURL else { folders = []; return }
        var set = Set<URL>()
        for s in songs {
            var current = s.url.deletingLastPathComponent()
            while current.path.count > root.path.count {
                set.insert(current)
                let parent = current.deletingLastPathComponent()
                if parent.path == current.path { break }
                current = parent
            }
        }
        folders = Array(set).sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    func pickFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose Music Folder"
        if panel.runModal() == .OK, let url = panel.url {
            Task { await loadFolder(url) }
        }
    }

    func loadFolder(_ url: URL) async {
        folderURL = url
        isLoading = true
        stop()
        songs = []
        folders = []
        selectedFolderURL = nil
        stopWatching()

        let (foundSongs, foundFolders) = scanAll(url)
        var loaded: [Song] = []
        for u in foundSongs {
            let s = await Song.load(from: u)
            loaded.append(s)
        }
        songs = loaded
        folders = foundFolders
        isLoading = false
        saveSnapshot()

        if autoWatchEnabled { startWatching() }
    }

    func rescan() async {
        guard let folder = folderURL else { return }
        let (foundSongs, foundFolders) = scanAll(folder)

        let existingByURL: [URL: Song] = Dictionary(uniqueKeysWithValues: songs.map { ($0.url, $0) })
        var merged: [Song] = []
        var changed = false

        for url in foundSongs {
            if let existing = existingByURL[url] {
                merged.append(existing)
            } else {
                let s = await Song.load(from: url)
                merged.append(s)
                changed = true
            }
        }
        if merged.count != songs.count { changed = true }
        if foundFolders != folders { changed = true }

        let currentURL = currentSong?.url
        songs = merged
        folders = foundFolders

        if let url = currentURL,
           let qi = playbackQueue.firstIndex(where: { $0.url == url }) {
            currentIndex = qi
        }
        if changed { saveSnapshot() }

        if let sel = selectedFolderURL, sel.path != folder.path, !foundFolders.contains(where: { $0.path == sel.path }) {
            selectedFolderURL = nil
        }
    }

    private func scanAll(_ url: URL) -> (songs: [URL], folders: [URL]) {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: url,
            includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { return ([], []) }

        var songs: [URL] = []
        var folders: [URL] = []
        for case let fileURL as URL in enumerator {
            let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey])
            if values?.isDirectory == true {
                folders.append(fileURL)
            } else if values?.isRegularFile == true,
                      supportedExtensions.contains(fileURL.pathExtension.lowercased()) {
                songs.append(fileURL)
            }
        }
        songs.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        folders.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        return (songs, folders)
    }

    func play(_ song: Song, in queue: [Song]) {
        guard let idx = queue.firstIndex(where: { $0.url == song.url }) else { return }
        playbackQueue = queue
        playInQueue(at: idx)
    }

    private func playInQueue(at index: Int) {
        guard playbackQueue.indices.contains(index) else { return }
        let song = playbackQueue[index]
        do {
            timer?.invalidate()
            player?.stop()
            let p = try AVAudioPlayer(contentsOf: song.url)
            p.delegate = self
            p.volume = volume
            p.prepareToPlay()
            p.play()
            player = p
            currentIndex = index
            currentTime = 0
            isPlaying = true
            startTimer()
            loadArtworkIfNeeded(for: index)
        } catch {
            print("Failed to play \(song.url.lastPathComponent): \(error)")
        }
    }

    func ensureArtworkLoaded(for song: Song) async {
        guard let i = songs.firstIndex(where: { $0.url == song.url }), songs[i].artwork == nil else { return }
        let targetURL = songs[i].url
        guard let art = await Song.loadArtwork(from: targetURL) else { return }
        if let i = songs.firstIndex(where: { $0.url == targetURL }) {
            let old = songs[i]
            songs[i] = Song(
                id: old.id,
                title: old.title,
                artist: old.artist,
                album: old.album,
                duration: old.duration,
                artwork: art
            )
        }
        if let qi = playbackQueue.firstIndex(where: { $0.url == targetURL }) {
            let old = playbackQueue[qi]
            playbackQueue[qi] = Song(
                id: old.id,
                title: old.title,
                artist: old.artist,
                album: old.album,
                duration: old.duration,
                artwork: art
            )
        }
    }

    private func loadArtworkIfNeeded(for queueIndex: Int) {
        guard playbackQueue.indices.contains(queueIndex), playbackQueue[queueIndex].artwork == nil else { return }
        let target = playbackQueue[queueIndex]
        Task { @MainActor in
            guard let art = await Song.loadArtwork(from: target.url) else { return }
            let updated = Song(
                id: target.id,
                title: target.title,
                artist: target.artist,
                album: target.album,
                duration: target.duration,
                artwork: art
            )
            if let qi = playbackQueue.firstIndex(where: { $0.url == target.url }) {
                playbackQueue[qi] = updated
            }
            if let si = songs.firstIndex(where: { $0.url == target.url }) {
                songs[si] = updated
            }
        }
    }

    func togglePlayPause() {
        if let p = player {
            if p.isPlaying { p.pause(); isPlaying = false }
            else { p.play(); isPlaying = true }
        } else {
            let queue = displayedSongs
            if let first = queue.first {
                play(first, in: queue)
            }
        }
    }

    func next() {
        guard let i = currentIndex else {
            let queue = displayedSongs
            if let first = queue.first { play(first, in: queue) }
            return
        }
        if i + 1 < playbackQueue.count { playInQueue(at: i + 1) }
        else { stop() }
    }

    func previous() {
        guard let i = currentIndex else { return }
        if (player?.currentTime ?? 0) > 3 {
            player?.currentTime = 0
            currentTime = 0
        } else if i > 0 {
            playInQueue(at: i - 1)
        } else {
            player?.currentTime = 0
            currentTime = 0
        }
    }

    func stop() {
        player?.stop()
        player = nil
        isPlaying = false
        currentTime = 0
        timer?.invalidate()
        timer = nil
    }

    func seek(to t: TimeInterval) {
        guard let p = player else { return }
        let clamped = min(max(0, t), p.duration)
        p.currentTime = clamped
        currentTime = clamped
    }

    func forgetLibrary() {
        stop()
        stopWatching()
        songs = []
        folders = []
        selectedFolderURL = nil
        playbackQueue = []
        currentIndex = nil
        folderURL = nil
        LibraryStore.shared.clear()
    }

    // MARK: - Folder operations

    @discardableResult
    func createSubfolder(in parent: URL, named name: String) -> URL? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let safe = trimmed.replacingOccurrences(of: "/", with: "-")
        let dest = parent.appendingPathComponent(safe, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: false)
            if !folders.contains(dest) {
                folders.append(dest)
                folders.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            }
            var order = folderOrder[parent] ?? []
            order.append(dest)
            folderOrder[parent] = order
            saveFolderOrder()
            return dest
        } catch {
            print("Create folder failed: \(error)")
            return nil
        }
    }

    func reorderFolder(_ source: URL, after target: URL) {
        let sParent = source.deletingLastPathComponent()
        let tParent = target.deletingLastPathComponent()
        guard sParent.path == tParent.path, source.path != target.path else { return }
        let candidates = subfoldersOf(sParent)
        var order = orderedChildren(of: sParent, candidates: candidates)
        guard let srcIdx = order.firstIndex(of: source) else { return }
        order.remove(at: srcIdx)
        guard let tgtIdx = order.firstIndex(of: target) else { return }
        order.insert(source, at: tgtIdx + 1)
        folderOrder[sParent] = order
        saveFolderOrder()
    }

    func moveFolderUp(_ folder: URL) {
        let parent = folder.deletingLastPathComponent()
        let candidates = subfoldersOf(parent)
        var order = orderedChildren(of: parent, candidates: candidates)
        guard let i = order.firstIndex(of: folder), i > 0 else { return }
        order.swapAt(i, i - 1)
        folderOrder[parent] = order
        saveFolderOrder()
    }

    func moveFolderDown(_ folder: URL) {
        let parent = folder.deletingLastPathComponent()
        let candidates = subfoldersOf(parent)
        var order = orderedChildren(of: parent, candidates: candidates)
        guard let i = order.firstIndex(of: folder), i < order.count - 1 else { return }
        order.swapAt(i, i + 1)
        folderOrder[parent] = order
        saveFolderOrder()
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - Song ordering and queue

    func moveSongUp(_ song: Song, scopeKey: URL) {
        let list = displayedSongs
        guard let i = list.firstIndex(where: { $0.url == song.url }), i > 0 else { return }
        var ordered = list.map { $0.url }
        ordered.swapAt(i, i - 1)
        songOrder[scopeKey] = ordered
        saveSongOrder()
    }

    func moveSongDown(_ song: Song, scopeKey: URL) {
        let list = displayedSongs
        guard let i = list.firstIndex(where: { $0.url == song.url }), i < list.count - 1 else { return }
        var ordered = list.map { $0.url }
        ordered.swapAt(i, i + 1)
        songOrder[scopeKey] = ordered
        saveSongOrder()
    }

    func addToQueue(_ song: Song) {
        guard !playbackQueue.contains(where: { $0.url == song.url }) else { return }
        if let ci = currentIndex, playbackQueue.indices.contains(ci) {
            playbackQueue.insert(song, at: ci + 1)
        } else {
            playbackQueue.append(song)
        }
    }

    func playQueueItem(at index: Int) {
        guard playbackQueue.indices.contains(index) else { return }
        playInQueue(at: index)
    }

    func removeFromQueue(at index: Int) {
        guard playbackQueue.indices.contains(index) else { return }
        let wasCurrent = currentIndex == index
        playbackQueue.remove(at: index)
        if wasCurrent {
            stop()
            currentIndex = nil
        } else if let ci = currentIndex, index < ci {
            currentIndex = ci - 1
        }
    }

    func moveQueueItemUp(at index: Int) {
        guard playbackQueue.indices.contains(index), index > 0 else { return }
        playbackQueue.swapAt(index, index - 1)
        if currentIndex == index { currentIndex = index - 1 }
        else if currentIndex == index - 1 { currentIndex = index }
    }

    func moveQueueItemDown(at index: Int) {
        guard playbackQueue.indices.contains(index), index < playbackQueue.count - 1 else { return }
        playbackQueue.swapAt(index, index + 1)
        if currentIndex == index { currentIndex = index + 1 }
        else if currentIndex == index + 1 { currentIndex = index }
    }

    func clearQueue() {
        stop()
        playbackQueue = []
        currentIndex = nil
    }

    // MARK: - Delete

    func deleteSong(_ song: Song) {
        do {
            try FileManager.default.trashItem(at: song.url, resultingItemURL: nil)
        } catch {
            print("Delete song failed: \(error)")
            return
        }
        let wasCurrent = currentSong?.url == song.url
        if wasCurrent { stop() }
        if let qi = playbackQueue.firstIndex(where: { $0.url == song.url }) {
            playbackQueue.remove(at: qi)
            if wasCurrent {
                currentIndex = nil
            } else if let ci = currentIndex, qi < ci {
                currentIndex = ci - 1
            }
        }
        songs.removeAll { $0.url == song.url }
        for (k, v) in songOrder {
            let filtered = v.filter { $0 != song.url }
            if filtered.count != v.count { songOrder[k] = filtered }
        }
        saveSongOrder()
        saveSnapshot()
    }

    func deleteFolder(_ folder: URL) {
        guard let root = folderURL else { return }
        guard folder.path != root.path else { return }
        do {
            try FileManager.default.trashItem(at: folder, resultingItemURL: nil)
        } catch {
            print("Delete folder failed: \(error)")
            return
        }
        let prefix = folder.path + "/"
        let gone: (URL) -> Bool = { $0.path == folder.path || $0.path.hasPrefix(prefix) }

        if let cs = currentSong, gone(cs.url) { stop(); currentIndex = nil }
        playbackQueue.removeAll { gone($0.url) }
        songs.removeAll { gone($0.url) }
        folders.removeAll { gone($0) }

        if let sel = selectedFolderURL, gone(sel) {
            selectedFolderURL = nil
        }

        let parent = folder.deletingLastPathComponent()
        if var order = folderOrder[parent] {
            order.removeAll { $0 == folder }
            folderOrder[parent] = order
        }
        for key in folderOrder.keys where gone(key) {
            folderOrder.removeValue(forKey: key)
        }
        saveFolderOrder()

        for key in songOrder.keys where gone(key) {
            songOrder.removeValue(forKey: key)
        }
        for (k, v) in songOrder {
            let filtered = v.filter { !gone($0) }
            if filtered.count != v.count { songOrder[k] = filtered }
        }
        saveSongOrder()

        saveSnapshot()
    }

    // MARK: - Song move

    func moveSong(fromURL sourceURL: URL, toFolder targetFolder: URL) async {
        let fm = FileManager.default
        guard let root = folderURL else { return }

        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: targetFolder.path, isDirectory: &isDir), isDir.boolValue else { return }
        guard targetFolder.path == root.path || targetFolder.path.hasPrefix(root.path + "/") else { return }

        guard supportedExtensions.contains(sourceURL.pathExtension.lowercased()) else { return }

        var srcIsDir: ObjCBool = false
        guard fm.fileExists(atPath: sourceURL.path, isDirectory: &srcIsDir), !srcIsDir.boolValue else { return }

        if sourceURL.deletingLastPathComponent().path == targetFolder.path { return }

        let dest = uniqueDestination(folder: targetFolder, filename: sourceURL.lastPathComponent)

        do {
            try fm.moveItem(at: sourceURL, to: dest)
        } catch {
            do {
                try fm.copyItem(at: sourceURL, to: dest)
                try? fm.removeItem(at: sourceURL)
            } catch {
                print("Move failed: \(error)")
                return
            }
        }

        if let i = songs.firstIndex(where: { $0.url == sourceURL }) {
            let old = songs[i]
            songs[i] = Song(
                id: dest,
                title: old.title,
                artist: old.artist,
                album: old.album,
                duration: old.duration,
                artwork: old.artwork
            )
        } else if !songs.contains(where: { $0.url == dest }) {
            let s = await Song.load(from: dest)
            if !songs.contains(where: { $0.url == dest }) {
                songs.append(s)
            }
        }

        if let i = playbackQueue.firstIndex(where: { $0.url == sourceURL }) {
            let old = playbackQueue[i]
            playbackQueue[i] = Song(
                id: dest,
                title: old.title,
                artist: old.artist,
                album: old.album,
                duration: old.duration,
                artwork: old.artwork
            )
        }

        if !folders.contains(targetFolder), targetFolder.path != root.path {
            folders.append(targetFolder)
            folders.sort { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
        }

        saveSnapshot()
    }

    private func uniqueDestination(folder: URL, filename: String) -> URL {
        let fm = FileManager.default
        var candidate = folder.appendingPathComponent(filename)
        if !fm.fileExists(atPath: candidate.path) { return candidate }
        let base = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var n = 1
        while true {
            let name = ext.isEmpty ? "\(base) (\(n))" : "\(base) (\(n)).\(ext)"
            candidate = folder.appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            n += 1
        }
    }

    // MARK: - Persistence

    private func saveSnapshot() {
        LibraryStore.shared.save(.init(folderURL: folderURL, songs: songs))
    }

    private func startWatching() {
        stopWatching()
        guard let folder = folderURL else { return }
        let w = FolderWatcher(url: folder) { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in await self.rescan() }
        }
        w.start()
        watcher = w
    }

    private func stopWatching() {
        watcher?.stop()
        watcher = nil
    }

    private func startTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self = self, let p = self.player else { return }
                self.currentTime = p.currentTime
            }
        }
    }
}

extension MusicPlayer: AVAudioPlayerDelegate {
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
        Task { @MainActor in
            self.next()
        }
    }
}
