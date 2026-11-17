import Foundation

/// Ce que l'app écrit pour le widget dans le conteneur partagé (T25) : les minuteurs de la dernière photo, couloir par
/// couloir. Le widget ne lit que ça : aucun calcul de plan, aucun réseau. Un fichier JSON, un dossier d'images à côté.
public struct WidgetEtat: Codable, Equatable, Sendable {
    public static let format = 1
    public var format = WidgetEtat.format
    /// La date de la photo d'où viennent les minuteurs.
    public var photo: Date
    public var postes: [Poste]

    public init(photo: Date, postes: [Poste]) {
        self.photo = photo
        self.postes = postes
    }

    /// Ce qu'un poste fait dans la photo.
    public struct Travail: Codable, Equatable, Sendable {
        public var nom: String
        /// Le niveau que l'amélioration fait atteindre.
        public var niveau: Int
        public var fin: Date
        /// Nom du fichier image dans `dossierImages` ; nil sans image.
        public var image: String?

        public init(nom: String, niveau: Int, fin: Date, image: String?) {
            self.nom = nom
            self.niveau = niveau
            self.fin = fin
            self.image = image
        }
    }

    /// Un couloir : un ouvrier, le labo ou la Maison des familiers.
    public struct Poste: Codable, Equatable, Sendable {
        public var genre: WorkerKind
        /// Numéro dans son poste, à partir de 0.
        public var numero: Int
        /// L'image du poste quand il est libre (la cabane, le labo, la Maison des familiers).
        public var imageLibre: String?
        /// nil : rien ne tourne dans la photo.
        public var travail: Travail?

        public init(genre: WorkerKind, numero: Int, imageLibre: String?, travail: Travail?) {
            self.genre = genre
            self.numero = numero
            self.imageLibre = imageLibre
            self.travail = travail
        }

        public var titre: String {
            switch genre {
            case .builder: "Ouvrier \(numero + 1)"
            case .laboratory: "Labo"
            case .petHouse: "Familiers"
            case .blacksmith: "Forge"
            }
        }
    }

    // MARK: Fichiers

    public static func dossier(dans racine: URL) -> URL { racine.appending(path: "Widget") }
    public static func fichier(dans racine: URL) -> URL { dossier(dans: racine).appending(path: "etat.json") }
    public static func dossierImages(dans racine: URL) -> URL { dossier(dans: racine).appending(path: "images") }

    /// Écrit l'état ; rend faux si l'écriture échoue (le widget garde alors l'état d'avant).
    @discardableResult
    public func ecrire(dans racine: URL) -> Bool {
        let encodeur = JSONEncoder()
        encodeur.dateEncodingStrategy = .iso8601
        encodeur.outputFormatting = [.sortedKeys, .prettyPrinted]
        do {
            try FileManager.default.createDirectory(at: Self.dossier(dans: racine), withIntermediateDirectories: true)
            try encodeur.encode(self).write(to: Self.fichier(dans: racine), options: .atomic)
            return true
        } catch { return false }
    }

    /// nil quand le fichier manque, est abîmé ou d'un autre format.
    public static func lire(dans racine: URL) -> WidgetEtat? {
        let decodeur = JSONDecoder()
        decodeur.dateDecodingStrategy = .iso8601
        guard let donnees = try? Data(contentsOf: fichier(dans: racine)),
              let etat = try? decodeur.decode(WidgetEtat.self, from: donnees), etat.format == Self.format else { return nil }
        return etat
    }

    /// Plus de photo : le widget invite à ouvrir l'app.
    public static func effacer(dans racine: URL) {
        try? FileManager.default.removeItem(at: fichier(dans: racine))
    }
}
