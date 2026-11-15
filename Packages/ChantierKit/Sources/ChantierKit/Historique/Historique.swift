import Foundation

/// Les photos et leur index. UN SEUL point de configuration : `root` (le conteneur partagé ou Application Support : voir `Stockage`).
/// Photos dans `root/Photos`, index dans `root/index.json`. Aucune horloge.
public struct HistoryStore: Sendable {
    public let root: URL

    public init(root: URL) {
        self.root = root
    }

    public var photos: SnapshotStore { SnapshotStore(directory: root.appending(path: "Photos")) }
    var indexURL: URL { root.appending(path: "index.json") }

    public struct Listing: Sendable, Equatable {
        /// Les résumés, de la photo la plus ancienne à la plus récente.
        public let entries: [PhotoSummary]
        /// Les photos qui ne se relisent pas : signalées, ignorées, jamais supprimées.
        public let unreadable: [Snapshot]
    }

    public enum HistoryError: Error, Equatable { case cannotDelete }

    /// Remet l'index d'accord avec les photos et le contexte, et le renvoie. Un index absent, abîmé ou d'une autre
    /// version est reconstruit en entier ; sinon seules les photos nouvelles sont calculées. Jamais d'erreur :
    /// si l'index ne s'écrit pas, on le recalculera au prochain appel.
    public func refresh(_ context: HistoryContext) -> Listing {
        let store = photos
        let snapshots = store.list()
        let old = readIndex()
        let reusable = old?.key == context.key ? old?.entries ?? [] : []
        let wanted = Set(snapshots.map { Int($0.date.timeIntervalSince1970) })
        // Un fichier dont la taille ou la date a changé depuis le calcul est relu (il a pu s'abîmer).
        var entries = reusable.filter { entry in
            wanted.contains(entry.timestamp)
                && FileStamp(of: store.directory.appending(path: Snapshot(date: entry.date).fileName)) == entry.fileStamp
        }
        let known = Set(entries.map(\.timestamp))
        let todo = snapshots.filter { !known.contains(Int($0.date.timeIntervalSince1970)) }

        let results = Résultats<PhotoSummary>(count: todo.count)
        // Les plans coûtent : une reconstruction complète se fait sur tous les cœurs.
        DispatchQueue.concurrentPerform(iterations: todo.count) { i in
            let stamp = FileStamp(of: store.directory.appending(path: todo[i].fileName))
            guard let stamp, let text = store.text(of: todo[i]), let export = try? VillageExport.parse(text) else { return }
            results.set(i, PhotoSummary(snapshot: todo[i], export: export, stamp: stamp, context: context))
        }
        let computed = results.values
        let unreadable = zip(todo, computed).filter { $1 == nil }.map(\.0)
        entries = (entries + computed.compactMap { $0 }).sorted { $0.timestamp < $1.timestamp }

        let index = HistoryIndex(key: context.key, entries: entries)
        if old != index { writeIndex(index) }
        return Listing(entries: entries, unreadable: unreadable)
    }

    /// Enregistre la photo (T07) puis met l'index à jour. Une photo plus ancienne que la dernière s'insère à sa place.
    @discardableResult
    public func add(_ text: String, context: HistoryContext) throws(SnapshotStore.SaveError)
        -> (outcome: SnapshotStore.Outcome, listing: Listing) {
        let outcome = try photos.save(text)
        return (outcome, refresh(context))
    }

    /// Supprime la photo (suppression explicite demandée par l'utilisateur) et met l'index à jour.
    public func delete(_ snapshot: Snapshot, context: HistoryContext) throws(HistoryError) -> Listing {
        do { try FileManager.default.removeItem(at: photos.directory.appending(path: snapshot.fileName)) }
        catch { throw .cannotDelete }
        return refresh(context)
    }

    /// Ce qui a changé entre deux photos ; nil si l'une des deux ne se relit pas.
    public func difference(from old: Snapshot, to new: Snapshot, context: HistoryContext) -> PhotoDiff? {
        let listing = refresh(context)
        return diff(old, new, in: listing, context: context)
    }

    /// Le ticket de chantier : ce qui a changé depuis la photo lisible précédente ; nil pour la première photo.
    public func ticket(for snapshot: Snapshot, context: HistoryContext) -> PhotoDiff? {
        let listing = refresh(context)
        guard let previous = listing.entries.last(where: { $0.timestamp < Int(snapshot.date.timeIntervalSince1970) })
        else { return nil }
        return diff(Snapshot(date: previous.date), snapshot, in: listing, context: context)
    }

    private func diff(_ old: Snapshot, _ new: Snapshot, in listing: Listing, context: HistoryContext) -> PhotoDiff? {
        func load(_ s: Snapshot) -> (Village, PhotoSummary?)? {
            guard let text = photos.text(of: s), let export = try? VillageExport.parse(text) else { return nil }
            let summary = listing.entries.first { $0.timestamp == Int(s.date.timeIntervalSince1970) }
            return (Village(export: export, reference: context.reference), summary)
        }
        guard let (a, sa) = load(old), let (b, sb) = load(new) else { return nil }
        return PhotoDiff(old: a, oldSummary: sa, new: b, newSummary: sb)
    }

    // MARK: - Fichier d'index

    private func readIndex() -> HistoryIndex? {
        guard let data = try? Data(contentsOf: indexURL),
              let index = try? JSONDecoder().decode(HistoryIndex.self, from: data),
              index.format == HistoryIndex.currentFormat else { return nil }
        return index
    }

    private func writeIndex(_ index: HistoryIndex) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .prettyPrinted]
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try encoder.encode(index).write(to: indexURL, options: .atomic)
        } catch {}   // cache : une écriture ratée n'est pas une erreur
    }
}

/// Un tableau rempli depuis plusieurs fils.
private final class Résultats<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [T?]
    init(count: Int) { storage = Array(repeating: nil, count: count) }
    func set(_ i: Int, _ value: T) { lock.withLock { storage[i] = value } }
    var values: [T?] { lock.withLock { storage } }
}
