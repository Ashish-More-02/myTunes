import SwiftUI
import AppKit
import UniformTypeIdentifiers

enum NavItem: Hashable {
    case library, queue, settings
}

@MainActor
func confirmTrash(title: String, info: String, perform: () -> Void) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = info
    alert.alertStyle = .warning
    alert.addButton(withTitle: "Move to Trash")
    alert.addButton(withTitle: "Cancel")
    if alert.runModal() == .alertFirstButtonReturn {
        perform()
    }
}

struct ContentView: View {
    @StateObject private var player = MusicPlayer()
    @AppStorage("colorScheme") private var colorSchemeRaw: String = "dark"
    @State private var nav: NavItem = .library
    @State private var keyMonitor: Any?
    @State private var mouseMonitor: Any?

    private var scheme: ColorScheme {
        colorSchemeRaw == "light" ? .light : .dark
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SidebarView(player: player, nav: $nav, scheme: scheme)
                    .frame(width: 280)

                Group {
                    switch nav {
                    case .library:
                        MainView(player: player, scheme: scheme)
                    case .queue:
                        QueueView(player: player, scheme: scheme)
                    case .settings:
                        SettingsView(
                            player: player,
                            colorSchemeRaw: $colorSchemeRaw,
                            scheme: scheme
                        )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            PlayerBar(player: player, scheme: scheme)
                .frame(height: 92)
        }
        .background(Theme.background(scheme))
        .preferredColorScheme(scheme)
        .frame(minWidth: 1200, minHeight: 820)
        .onAppear { installEventMonitors() }
        .onDisappear { removeEventMonitors() }
    }

    private func installEventMonitors() {
        if keyMonitor == nil {
            keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 53, let window = event.window, dropTextFocus(in: window) {
                    return nil
                }
                if event.keyCode == 49 {
                    if let resp = event.window?.firstResponder,
                       resp is NSText || resp is NSTextView {
                        return event
                    }
                    player.togglePlayPause()
                    return nil
                }
                return event
            }
        }
        if mouseMonitor == nil {
            mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
                guard let window = event.window,
                      let resp = window.firstResponder,
                      resp is NSText || resp is NSTextView else {
                    return event
                }
                let hit = window.contentView?.hitTest(event.locationInWindow)
                if !viewIsInsideTextEditor(hit) {
                    window.makeFirstResponder(nil)
                }
                return event
            }
        }
    }

    private func removeEventMonitors() {
        if let m = keyMonitor { NSEvent.removeMonitor(m); keyMonitor = nil }
        if let m = mouseMonitor { NSEvent.removeMonitor(m); mouseMonitor = nil }
    }

    @discardableResult
    private func dropTextFocus(in window: NSWindow) -> Bool {
        guard let resp = window.firstResponder,
              resp is NSText || resp is NSTextView else { return false }
        window.makeFirstResponder(nil)
        return true
    }

    private func viewIsInsideTextEditor(_ view: NSView?) -> Bool {
        var v: NSView? = view
        while let cur = v {
            if cur is NSTextView || cur is NSText { return true }
            v = cur.superview
        }
        return false
    }
}

struct SidebarView: View {
    @ObservedObject var player: MusicPlayer
    @Binding var nav: NavItem
    let scheme: ColorScheme

    @State private var expanded: Set<URL> = []
    @State private var showNewFolder = false
    @State private var newFolderName = ""
    @State private var newFolderParent: URL? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Group {
                    if let logo = NSImage(named: "myTunes_app_image_final") {
                        Image(nsImage: logo)
                            .resizable()
                            .scaledToFit()
                    } else {
                        Image(systemName: "music.note.list")
                            .font(.title2)
                            .foregroundColor(Theme.accent(scheme))
                    }
                }
                .frame(width: 34, height: 34)
                .squircleClip(radius: Theme.R.sm)
                .squircleStroke(Theme.secondaryText(scheme).opacity(0.15), radius: Theme.R.sm)

                Text("myTunes")
                    .font(.title3.bold())
                    .foregroundColor(Theme.text(scheme))
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            VStack(spacing: 4) {
                NavRow(icon: "music.note.house.fill", label: "Library", isActive: nav == .library, scheme: scheme) {
                    nav = .library
                }
                NavRow(
                    icon: "list.bullet.indent",
                    label: player.playbackQueue.isEmpty ? "Queue" : "Queue (\(player.playbackQueue.count))",
                    isActive: nav == .queue,
                    scheme: scheme
                ) {
                    nav = .queue
                }
                NavRow(icon: "gearshape.fill", label: "Settings", isActive: nav == .settings, scheme: scheme) {
                    nav = .settings
                }
            }
            .padding(.horizontal, 12)

            Button(action: { player.pickFolder() }) {
                HStack(spacing: 10) {
                    Image(systemName: "folder.badge.plus")
                    Text("Choose Folder")
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.vertical, 11)
                .padding(.horizontal, 14)
                .foregroundColor(Theme.text(scheme))
                .squircle(Theme.hover(scheme), radius: Theme.R.md)
                .squircleStroke(Theme.secondaryText(scheme).opacity(0.12), radius: Theme.R.md)
                .contentShape(Squircle(radius: Theme.R.md))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)

            Divider()
                .background(Theme.secondaryText(scheme).opacity(0.3))
                .padding(.horizontal, 12)

            HStack {
                Text("FOLDERS").font(.caption.bold())
                Spacer()
                if player.folderURL != nil {
                    ChromeButton(size: 24, radius: Theme.R.xs, scheme: scheme) {
                        newFolderParent = player.folderURL
                        newFolderName = ""
                        showNewFolder = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 11, weight: .bold))
                    }
                    .help("New folder at root")
                }
            }
            .foregroundColor(Theme.secondaryText(scheme))
            .padding(.horizontal, 16)

            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if let tree = player.tree {
                        TreeNodeView(
                            node: tree,
                            depth: 0,
                            player: player,
                            expanded: $expanded,
                            nav: $nav,
                            scheme: scheme,
                            onRequestNewFolder: { parent in
                                newFolderParent = parent
                                newFolderName = ""
                                showNewFolder = true
                            }
                        )
                    } else {
                        Text("No folder selected").font(.caption)
                            .foregroundColor(Theme.secondaryText(scheme))
                            .padding(.horizontal, 16)
                    }
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 12)
            }

            if player.isLoading {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading...")
                        .font(.caption)
                        .foregroundColor(Theme.secondaryText(scheme))
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.panel(scheme))
        .onAppear {
            if let root = player.folderURL {
                expanded.insert(root)
            }
        }
        .alert("New Folder", isPresented: $showNewFolder) {
            TextField("Folder name", text: $newFolderName)
            Button("Create") {
                if let parent = newFolderParent ?? player.folderURL {
                    if let created = player.createSubfolder(in: parent, named: newFolderName) {
                        expanded.insert(parent)
                        expanded.insert(created)
                    }
                }
                newFolderName = ""
            }
            Button("Cancel", role: .cancel) {
                newFolderName = ""
            }
        } message: {
            Text(newFolderParent.map { "Inside \($0.lastPathComponent)" } ?? "")
        }
    }
}

struct NavRow: View {
    let icon: String
    let label: String
    let isActive: Bool
    let scheme: ColorScheme
    let action: () -> Void
    @State private var hover = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 18)
                Text(label)
                    .fontWeight(isActive ? .semibold : .regular)
                Spacer()
            }
            .padding(.vertical, 9)
            .padding(.horizontal, 12)
            .foregroundColor(isActive ? Theme.accent(scheme) : Theme.text(scheme))
            .squircle((isActive || hover) ? Theme.hover(scheme) : Color.clear, radius: Theme.R.md)
            .contentShape(Squircle(radius: Theme.R.md))
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
    }
}

struct TreeNodeView: View {
    let node: FolderNode
    let depth: Int
    @ObservedObject var player: MusicPlayer
    @Binding var expanded: Set<URL>
    @Binding var nav: NavItem
    let scheme: ColorScheme
    let onRequestNewFolder: (URL) -> Void

    @State private var hover = false
    @State private var isTargeted = false

    private var isExpanded: Bool { expanded.contains(node.url) }
    private var hasChildren: Bool { !node.subfolders.isEmpty || !node.songs.isEmpty }

    private var isSelected: Bool {
        nav == .library &&
        ((node.isRoot && player.selectedFolderURL == nil) ||
         (!node.isRoot && player.selectedFolderURL?.path == node.url.path))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Color.clear.frame(width: CGFloat(depth) * 14, height: 1)

                Group {
                    if hasChildren {
                        ChromeButton(size: 18, radius: Theme.R.xs, scheme: scheme) {
                            toggleExpand()
                        } label: {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundColor(Theme.secondaryText(scheme))
                        }
                    } else {
                        Color.clear.frame(width: 18, height: 18)
                    }
                }

                Image(systemName: node.isRoot ? "music.note.house.fill" : (isExpanded ? "folder.fill" : "folder"))
                    .font(.system(size: 12))
                    .foregroundColor(isSelected ? Theme.accent(scheme) : Theme.secondaryText(scheme))
                    .frame(width: 16)

                Text(node.isRoot ? "All Songs" : node.name)
                    .font(.system(size: 13, weight: isSelected ? .semibold : .regular))
                    .foregroundColor(isSelected ? Theme.accent(scheme) : Theme.text(scheme))
                    .lineLimit(1)

                Spacer(minLength: 4)

                Text("\(node.totalSongCount)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(Theme.secondaryText(scheme))
            }
            .padding(.vertical, 5)
            .padding(.horizontal, 8)
            .squircle(rowBackground, radius: Theme.R.md)
            .squircleStroke(isTargeted ? Theme.accent(scheme) : Color.clear, lineWidth: 1.5, radius: Theme.R.md)
            .contentShape(Squircle(radius: Theme.R.md))
            .onHover { hover = $0 }
            .onTapGesture { selectFolder() }
            .draggable(node.url)
            .dropDestination(for: URL.self) { urls, _ in
                handleDrop(urls)
                return true
            } isTargeted: { isTargeted = $0 }
            .contextMenu {
                Button("New Subfolder…") {
                    onRequestNewFolder(node.url)
                }
                Button("Reveal in Finder") {
                    player.revealInFinder(node.url)
                }
                if !node.isRoot {
                    Divider()
                    Button("Move Up") { player.moveFolderUp(node.url) }
                    Button("Move Down") { player.moveFolderDown(node.url) }
                    Divider()
                    Button("Delete \"\(node.name)\"…", role: .destructive) {
                        confirmTrash(
                            title: "Delete \"\(node.name)\"?",
                            info: "The folder and everything inside it will be moved to the Trash."
                        ) {
                            player.deleteFolder(node.url)
                        }
                    }
                }
            }

            if isExpanded {
                ForEach(node.subfolders) { sub in
                    TreeNodeView(
                        node: sub,
                        depth: depth + 1,
                        player: player,
                        expanded: $expanded,
                        nav: $nav,
                        scheme: scheme,
                        onRequestNewFolder: onRequestNewFolder
                    )
                }
                ForEach(node.songs) { song in
                    SidebarSongRow(
                        song: song,
                        depth: depth + 1,
                        isCurrent: player.currentSong?.url == song.url,
                        isPlaying: player.currentSong?.url == song.url && player.isPlaying,
                        scheme: scheme,
                        player: player
                    ) {
                        let queue = player.songsRecursivelyIn(node.url)
                        if let s = queue.first(where: { $0.url == song.url }) {
                            player.play(s, in: queue)
                        }
                    }
                    .draggable(song.url)
                    .contextMenu {
                        Button("Play") {
                            let queue = player.songsRecursivelyIn(node.url)
                            if let s = queue.first(where: { $0.url == song.url }) {
                                player.play(s, in: queue)
                            }
                        }
                        Button("Add to Queue") {
                            player.addToQueue(song)
                        }
                        Divider()
                        Button("Reveal in Finder") {
                            player.revealInFinder(song.url)
                        }
                        Divider()
                        Button("Delete \"\(song.title)\"…", role: .destructive) {
                            confirmTrash(
                                title: "Delete \"\(song.title)\"?",
                                info: "The file will be moved to the Trash."
                            ) {
                                player.deleteSong(song)
                            }
                        }
                    }
                }
            }
        }
    }

    private var rowBackground: Color {
        if isSelected { return Theme.hover(scheme) }
        if hover { return Theme.hover(scheme).opacity(0.6) }
        return Color.clear
    }

    private func toggleExpand() {
        if isExpanded { expanded.remove(node.url) }
        else { expanded.insert(node.url) }
    }

    private func selectFolder() {
        player.selectedFolderURL = node.isRoot ? nil : node.url
        nav = .library
    }

    private func handleDrop(_ urls: [URL]) {
        let fm = FileManager.default
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                if url.deletingLastPathComponent().path == node.url.deletingLastPathComponent().path,
                   !node.isRoot {
                    player.reorderFolder(url, after: node.url)
                }
            } else {
                let target = node.url
                Task { await player.moveSong(fromURL: url, toFolder: target) }
            }
        }
        expanded.insert(node.url)
    }
}

struct SidebarSongRow: View {
    let song: Song
    let depth: Int
    let isCurrent: Bool
    let isPlaying: Bool
    let scheme: ColorScheme
    let player: MusicPlayer
    let onTap: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Color.clear.frame(width: CGFloat(depth) * 14, height: 1)
            Color.clear.frame(width: 18, height: 18)

            ArtworkView(image: song.artwork, size: 24)

            Text(song.title)
                .font(.system(size: 12, weight: isCurrent ? .semibold : .regular))
                .foregroundColor(isCurrent ? Theme.accent(scheme) : Theme.text(scheme))
                .lineLimit(1)

            Spacer(minLength: 4)

            if isCurrent {
                Image(systemName: isPlaying ? "speaker.wave.2.fill" : "pause.fill")
                    .font(.system(size: 10))
                    .foregroundColor(Theme.accent(scheme))
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 8)
        .squircle(hover ? Theme.hover(scheme).opacity(0.6) : Color.clear, radius: Theme.R.md)
        .contentShape(Squircle(radius: Theme.R.md))
        .onHover { hover = $0 }
        .onTapGesture(perform: onTap)
        .task(id: song.url) {
            await player.ensureArtworkLoaded(for: song)
        }
    }
}

struct MainView: View {
    @ObservedObject var player: MusicPlayer
    let scheme: ColorScheme
    @State private var searchText = ""
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            SearchBar(text: $searchText, focused: $searchFocused, scheme: scheme)
                .padding(.horizontal, 32)
                .padding(.top, 24)
                .padding(.bottom, searchText.isEmpty ? 8 : 16)

            if searchText.isEmpty {
                libraryContent
            } else {
                SearchResultsView(player: player, query: searchText, scheme: scheme) {
                    searchText = ""
                    searchFocused = false
                }
            }
        }
    }

    private var libraryContent: some View {
        let displayed = player.displayedSongs
        return ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .bottom, spacing: 24) {
                    ArtworkView(image: player.currentSong?.artwork, size: 200)
                        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(headerEyebrow)
                            .font(.caption.bold())
                            .foregroundColor(Theme.secondaryText(scheme))
                        Text(headerTitle)
                            .font(.system(size: 48, weight: .bold))
                            .foregroundColor(Theme.text(scheme))
                            .lineLimit(2)
                            .minimumScaleFactor(0.5)
                        Text(headerSubtitle)
                            .font(.title3)
                            .foregroundColor(Theme.secondaryText(scheme))
                            .lineLimit(1)
                    }
                    Spacer()
                }
                .padding(.horizontal, 32)
                .padding(.top, 32)

                if !displayed.isEmpty {
                    VStack(spacing: 0) {
                        HStack {
                            Text("#").frame(width: 32, alignment: .leading)
                            Text("TITLE")
                            Spacer()
                            Text("DURATION").frame(width: 90, alignment: .trailing)
                        }
                        .font(.caption.bold())
                        .foregroundColor(Theme.secondaryText(scheme))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        Divider().background(Theme.secondaryText(scheme).opacity(0.2))

                        ForEach(Array(displayed.enumerated()), id: \.element.id) { index, song in
                            SongRow(
                                index: index,
                                song: song,
                                isCurrent: player.currentSong?.url == song.url,
                                isPlaying: player.currentSong?.url == song.url && player.isPlaying,
                                scheme: scheme,
                                player: player
                            ) {
                                if player.currentSong?.url == song.url {
                                    player.togglePlayPause()
                                } else {
                                    player.play(song, in: displayed)
                                }
                            }
                            .draggable(song.url)
                            .contextMenu {
                                Button("Play") {
                                    player.play(song, in: displayed)
                                }
                                Button("Add to Queue") {
                                    player.addToQueue(song)
                                }
                                Divider()
                                Button("Move Up") {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        player.moveSongUp(song, scopeKey: player.displayedScopeKey)
                                    }
                                }
                                .disabled(index == 0)
                                Button("Move Down") {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        player.moveSongDown(song, scopeKey: player.displayedScopeKey)
                                    }
                                }
                                .disabled(index == displayed.count - 1)
                                Divider()
                                Button("Reveal in Finder") {
                                    player.revealInFinder(song.url)
                                }
                                Divider()
                                Button("Delete \"\(song.title)\"…", role: .destructive) {
                                    confirmTrash(
                                        title: "Delete \"\(song.title)\"?",
                                        info: "The file will be moved to the Trash."
                                    ) {
                                        player.deleteSong(song)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                } else if player.folderURL != nil {
                    Text("No songs in this folder. Drop audio files onto a folder in the sidebar to add them.")
                        .font(.title3)
                        .foregroundColor(Theme.secondaryText(scheme))
                        .padding(32)
                }
            }
        }
    }

    private var headerEyebrow: String {
        if player.currentSong != nil { return "NOW PLAYING" }
        if player.selectedFolderURL != nil { return "FOLDER" }
        return "WELCOME"
    }

    private var headerTitle: String {
        if let s = player.currentSong { return s.title }
        if let name = player.selectedFolderName { return name }
        if player.folderURL != nil { return "All Songs" }
        return "Pick a folder to get started"
    }

    private var headerSubtitle: String {
        if let s = player.currentSong {
            return s.album.isEmpty ? s.artist : "\(s.artist) • \(s.album)"
        }
        if player.folderURL != nil {
            return "\(player.displayedSongs.count) songs"
        }
        return "Use the sidebar to choose your music folder"
    }
}

struct SongRow: View {
    let index: Int
    let song: Song
    let isCurrent: Bool
    let isPlaying: Bool
    let scheme: ColorScheme
    let player: MusicPlayer
    let onTap: () -> Void
    @State private var hover = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                if hover {
                    Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                        .foregroundColor(Theme.text(scheme))
                } else if isCurrent {
                    Image(systemName: "waveform")
                        .foregroundColor(Theme.accent(scheme))
                } else {
                    Text("\(index + 1)")
                        .foregroundColor(Theme.secondaryText(scheme))
                        .font(.callout.monospacedDigit())
                }
            }
            .frame(width: 32, alignment: .leading)

            ArtworkView(image: song.artwork, size: 44)

            VStack(alignment: .leading, spacing: 3) {
                Text(song.title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(isCurrent ? Theme.accent(scheme) : Theme.text(scheme))
                    .lineLimit(1)
                Text(song.artist)
                    .font(.system(size: 13))
                    .foregroundColor(Theme.secondaryText(scheme))
                    .lineLimit(1)
            }
            Spacer()
            Text(formatTime(song.duration))
                .font(.system(size: 13).monospacedDigit())
                .foregroundColor(Theme.secondaryText(scheme))
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .squircle(hover ? Theme.hover(scheme) : Color.clear, radius: Theme.R.lg)
        .contentShape(Squircle(radius: Theme.R.lg))
        .onHover { hover = $0 }
        .onTapGesture(perform: onTap)
        .task(id: song.url) {
            await player.ensureArtworkLoaded(for: song)
        }
    }
}

struct SearchBar: View {
    @Binding var text: String
    var focused: FocusState<Bool>.Binding
    let scheme: ColorScheme

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(Theme.secondaryText(scheme))
            TextField("Search all songs by title, artist, or album", text: $text)
                .textFieldStyle(.plain)
                .focused(focused)
                .foregroundColor(Theme.text(scheme))
                .font(.system(size: 15))
            if !text.isEmpty {
                ChromeButton(size: 22, radius: 11, scheme: scheme) {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 14))
                        .foregroundColor(Theme.secondaryText(scheme))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .squircle(Theme.panel(scheme), radius: Theme.R.lg)
        .squircleStroke(Theme.secondaryText(scheme).opacity(0.18), radius: Theme.R.lg)
    }
}

struct SearchResultsView: View {
    @ObservedObject var player: MusicPlayer
    let query: String
    let scheme: ColorScheme
    let onDismiss: () -> Void

    private var results: [Song] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return [] }
        return player.songs.filter { s in
            s.title.lowercased().contains(q)
                || s.artist.lowercased().contains(q)
                || s.album.lowercased().contains(q)
        }
    }

    var body: some View {
        let list = results
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(list.isEmpty ? "No results" : "\(list.count) result\(list.count == 1 ? "" : "s")")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Theme.secondaryText(scheme))
                Spacer()
                Button("Close") { onDismiss() }
                    .buttonStyle(CapsulePillButtonStyle(variant: .accent, scheme: scheme))
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 12)

            Divider().background(Theme.secondaryText(scheme).opacity(0.2))

            if list.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 36))
                        .foregroundColor(Theme.secondaryText(scheme).opacity(0.6))
                    Text("Nothing matches \"\(query)\"")
                        .font(.title3)
                        .foregroundColor(Theme.secondaryText(scheme))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.element.id) { index, song in
                            SongRow(
                                index: index,
                                song: song,
                                isCurrent: player.currentSong?.url == song.url,
                                isPlaying: player.currentSong?.url == song.url && player.isPlaying,
                                scheme: scheme,
                                player: player
                            ) {
                                player.play(song, in: list)
                            }
                            .draggable(song.url)
                            .contextMenu {
                                Button("Play") { player.play(song, in: list) }
                                Button("Add to Queue") { player.addToQueue(song) }
                                Divider()
                                Button("Reveal in Finder") { player.revealInFinder(song.url) }
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.vertical, 8)
                }
            }
        }
        .background(Theme.background(scheme))
    }
}

struct QueueView: View {
    @ObservedObject var player: MusicPlayer
    let scheme: ColorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("UP NEXT")
                        .font(.caption.bold())
                        .foregroundColor(Theme.secondaryText(scheme))
                    Text("Queue")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundColor(Theme.text(scheme))
                    Text(player.playbackQueue.isEmpty
                         ? "Nothing queued"
                         : "\(player.playbackQueue.count) song\(player.playbackQueue.count == 1 ? "" : "s")")
                        .font(.title3)
                        .foregroundColor(Theme.secondaryText(scheme))
                }
                Spacer()
                if !player.playbackQueue.isEmpty {
                    Button {
                        player.clearQueue()
                    } label: {
                        Label("Clear Queue", systemImage: "trash")
                    }
                    .buttonStyle(SquircleButtonStyle(variant: .destructive, scheme: scheme))
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 32)
            .padding(.bottom, 16)

            if player.playbackQueue.isEmpty {
                VStack(spacing: 10) {
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 40))
                        .foregroundColor(Theme.secondaryText(scheme).opacity(0.6))
                    Text("Play a song or use \"Add to Queue\" to fill the queue.")
                        .font(.title3)
                        .foregroundColor(Theme.secondaryText(scheme))
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(32)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        HStack {
                            Text("#").frame(width: 32, alignment: .leading)
                            Text("TITLE")
                            Spacer()
                            Text("DURATION").frame(width: 90, alignment: .trailing)
                        }
                        .font(.caption.bold())
                        .foregroundColor(Theme.secondaryText(scheme))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 10)

                        Divider().background(Theme.secondaryText(scheme).opacity(0.2))

                        ForEach(Array(player.playbackQueue.enumerated()), id: \.element.id) { index, song in
                            SongRow(
                                index: index,
                                song: song,
                                isCurrent: player.currentIndex == index,
                                isPlaying: player.currentIndex == index && player.isPlaying,
                                scheme: scheme,
                                player: player
                            ) {
                                if player.currentIndex == index {
                                    player.togglePlayPause()
                                } else {
                                    player.playQueueItem(at: index)
                                }
                            }
                            .draggable(song.url)
                            .contextMenu {
                                Button("Play") { player.playQueueItem(at: index) }
                                Divider()
                                Button("Move Up") {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        player.moveQueueItemUp(at: index)
                                    }
                                }
                                .disabled(index == 0)
                                Button("Move Down") {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        player.moveQueueItemDown(at: index)
                                    }
                                }
                                .disabled(index == player.playbackQueue.count - 1)
                                Divider()
                                Button("Remove from Queue", role: .destructive) {
                                    withAnimation(.easeInOut(duration: 0.18)) {
                                        player.removeFromQueue(at: index)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 32)
                    .padding(.bottom, 32)
                }
            }
        }
    }
}

struct PlayerBar: View {
    @ObservedObject var player: MusicPlayer
    let scheme: ColorScheme

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                ArtworkView(image: player.currentSong?.artwork, size: 56)
                VStack(alignment: .leading, spacing: 2) {
                    Text(player.currentSong?.title ?? "—")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Theme.text(scheme))
                        .lineLimit(1)
                    Text(player.currentSong?.artist ?? "")
                        .font(.caption)
                        .foregroundColor(Theme.secondaryText(scheme))
                        .lineLimit(1)
                }
            }
            .frame(width: 260, alignment: .leading)

            VStack(spacing: 6) {
                HStack(spacing: 14) {
                    ChromeButton(size: 36, radius: Theme.R.md, scheme: scheme) {
                        player.previous()
                    } label: {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 15, weight: .semibold))
                    }

                    PlayPauseButton(player: player, scheme: scheme)

                    ChromeButton(size: 36, radius: Theme.R.md, scheme: scheme) {
                        player.next()
                    } label: {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 15, weight: .semibold))
                    }
                }

                HStack(spacing: 8) {
                    Text(formatTime(player.currentTime))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(Theme.secondaryText(scheme))
                        .frame(width: 40, alignment: .trailing)
                    Slider(
                        value: Binding(
                            get: { player.currentTime },
                            set: { player.seek(to: $0) }
                        ),
                        in: 0...max(0.01, player.currentSong?.duration ?? 0.01)
                    )
                    .tint(Theme.accent(scheme))
                    .disabled(player.currentSong == nil)
                    Text(formatTime(player.currentSong?.duration ?? 0))
                        .font(.caption2.monospacedDigit())
                        .foregroundColor(Theme.secondaryText(scheme))
                        .frame(width: 40, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)

            HStack(spacing: 8) {
                Image(systemName: player.volume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .foregroundColor(Theme.secondaryText(scheme))
                Slider(value: Binding(
                    get: { Double(player.volume) },
                    set: { player.volume = Float($0) }
                ), in: 0...1)
                .tint(Theme.text(scheme))
                .frame(width: 100)
            }
            .frame(width: 160, alignment: .trailing)
        }
        .padding(.horizontal, 16)
        .frame(maxHeight: .infinity)
        .background(Theme.barBackground(scheme))
    }
}

struct PlayPauseButton: View {
    @ObservedObject var player: MusicPlayer
    let scheme: ColorScheme
    @State private var hover = false
    @State private var pressed = false

    var body: some View {
        Button {
            player.togglePlayPause()
        } label: {
            ZStack {
                Circle()
                    .fill(Theme.accent(scheme))
                    .shadow(color: Theme.accent(scheme).opacity(hover ? 0.45 : 0.25),
                            radius: hover ? 10 : 6, y: 2)
                Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(scheme == .dark ? Theme.navy : Theme.cream)
                    .offset(x: player.isPlaying ? 0 : 1)
            }
            .frame(width: 44, height: 44)
            .scaleEffect(pressed ? 0.93 : (hover ? 1.04 : 1))
            .animation(.easeOut(duration: 0.12), value: hover)
            .animation(.easeOut(duration: 0.1), value: pressed)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressed = true }
                .onEnded { _ in pressed = false }
        )
    }
}

struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat

    private var cornerRadius: CGFloat {
        if size > 150 { return Theme.R.hero }
        if size > 100 { return Theme.R.xxl }
        if size > 40 { return Theme.R.md }
        return Theme.R.xs
    }

    private var iconScale: CGFloat {
        size > 100 ? 0.35 : 0.55
    }

    var body: some View {
        Group {
            if let img = image {
                Image(nsImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    LinearGradient(
                        colors: [Theme.navy, Theme.slate],
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                    Image(systemName: "music.note")
                        .font(.system(size: size * iconScale, weight: .bold))
                        .foregroundColor(Theme.amber.opacity(0.9))
                }
            }
        }
        .frame(width: size, height: size)
        .squircleClip(radius: cornerRadius)
    }
}

struct SettingsView: View {
    @ObservedObject var player: MusicPlayer
    @Binding var colorSchemeRaw: String
    let scheme: ColorScheme

    @AppStorage(MusicPlayer.defaultVolumeKey) private var defaultVolume: Double = 0.8

    private var appVersion: String {
        (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "1.0"
    }
    private var appBuild: String {
        (Bundle.main.infoDictionary?["CFBundleVersion"] as? String) ?? "1"
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Text("Settings")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(Theme.text(scheme))

                section("Appearance") {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Theme").foregroundColor(Theme.text(scheme))
                            Text("Choose between dark and light mode")
                                .font(.caption)
                                .foregroundColor(Theme.secondaryText(scheme))
                        }
                        Spacer()
                        SquircleSegmented(
                            selection: $colorSchemeRaw,
                            options: [
                                (value: "dark", label: "Dark", icon: "moon.fill"),
                                (value: "light", label: "Light", icon: "sun.max.fill")
                            ],
                            scheme: scheme
                        )
                        .frame(width: 220)
                    }
                }

                section("Library") {
                    row("Current folder", player.folderURL?.path ?? "Not selected")
                    row("Songs scanned", "\(player.songs.count)")
                    row("Folders", "\(player.folders.count)")
                    row("Cache file", LibraryStore.shared.storagePath)
                    Divider().background(Theme.secondaryText(scheme).opacity(0.2))
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Auto-detect new files").foregroundColor(Theme.text(scheme))
                            Text("Watches the folder and rescans when songs are added or removed")
                                .font(.caption)
                                .foregroundColor(Theme.secondaryText(scheme))
                        }
                        Spacer()
                        Toggle("", isOn: $player.autoWatchEnabled)
                            .labelsHidden()
                            .toggleStyle(.switch)
                    }
                    HStack(spacing: 12) {
                        Button("Rescan Now") {
                            Task { await player.rescan() }
                        }
                        .buttonStyle(SquircleButtonStyle(variant: .prominent, scheme: scheme))
                        .disabled(player.folderURL == nil)

                        Button("Choose Different Folder") {
                            player.pickFolder()
                        }
                        .buttonStyle(SquircleButtonStyle(variant: .tinted, scheme: scheme))

                        Button("Forget Library") {
                            player.forgetLibrary()
                        }
                        .buttonStyle(SquircleButtonStyle(variant: .tinted, scheme: scheme))
                        .disabled(player.folderURL == nil)
                    }
                }

                section("Keyboard") {
                    row("Play / Pause", "Space")
                }

                section("Playback") {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Default volume").foregroundColor(Theme.text(scheme))
                            Text("Volume applied each time the app launches. Changing the player bar slider doesn't change this.")
                                .font(.caption)
                                .foregroundColor(Theme.secondaryText(scheme))
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 4) {
                            HStack(spacing: 8) {
                                Image(systemName: defaultVolume < 0.01 ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                    .foregroundColor(Theme.secondaryText(scheme))
                                Slider(value: $defaultVolume, in: 0...1)
                                    .tint(Theme.accent(scheme))
                                    .frame(width: 160)
                            }
                            Text("\(Int(defaultVolume * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(Theme.secondaryText(scheme))
                        }
                    }
                    HStack(spacing: 12) {
                        Button("Apply Now") {
                            player.volume = Float(defaultVolume)
                        }
                        .buttonStyle(SquircleButtonStyle(variant: .prominent, scheme: scheme))
                        Button("Save Current as Default") {
                            defaultVolume = Double(player.volume)
                        }
                        .buttonStyle(SquircleButtonStyle(variant: .tinted, scheme: scheme))
                    }
                }

                section("Audio") {
                    row("Engine", "AVFoundation · AVAudioPlayer")
                    row("Playback quality", "Lossless · plays files at their original bitrate")
                    row("Supported formats", "mp3, m4a, aac, wav, aiff, aif, flac")
                    row("Output device", "System default (change via System Settings → Sound)")
                    row("Sample rate / bit depth", "Inherited from source file")
                }

                section("Features") {
                    feature("Expandable folder tree in the sidebar (click songs to play)")
                    feature("Drag songs between folders — files are physically moved on disk")
                    feature("Drop audio files from Finder onto a folder to add them")
                    feature("Create new folders inline; reorder via drag or context menu")
                    feature("Recursive folder scanning across subdirectories")
                    feature("Auto-advance through your queue, stop at the end")
                    feature("Embedded album artwork & ID3 metadata (title, artist, album)")
                    feature("Play / pause, previous, next, seek and volume controls")
                    feature("Spacebar for quick play/pause")
                    feature("File-system watcher — auto-detects new songs in the folder")
                    feature("Library cache — remembers your folder across launches")
                    feature("Dark and light themes")
                    feature("Offline only — no network, no telemetry")
                }

                section("About") {
                    row("App", "myTunes")
                    row("Version", appVersion)
                    row("Build", appBuild)
                    row("Tagline", "Bring Your Own Music")
                    row("Platform", "macOS 13.0 or later")
                    row("Built with", "SwiftUI · AVFoundation · FSEvents")
                }
            }
            .padding(32)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title.uppercased())
                .font(.caption.bold())
                .foregroundColor(Theme.accent(scheme))
                .tracking(1)
            VStack(alignment: .leading, spacing: 14) {
                content()
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .squircle(Theme.panel(scheme), radius: Theme.R.xxl)
            .squircleStroke(Theme.divider(scheme), radius: Theme.R.xxl)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundColor(Theme.secondaryText(scheme))
                .frame(width: 160, alignment: .leading)
            Text(value)
                .foregroundColor(Theme.text(scheme))
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
            Spacer()
        }
        .font(.callout)
    }

    private func feature(_ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .foregroundColor(Theme.accent(scheme))
            Text(text).foregroundColor(Theme.text(scheme))
        }
    }
}

func formatTime(_ seconds: TimeInterval) -> String {
    guard seconds.isFinite, !seconds.isNaN, seconds >= 0 else { return "0:00" }
    let t = Int(seconds)
    return String(format: "%d:%02d", t / 60, t % 60)
}
