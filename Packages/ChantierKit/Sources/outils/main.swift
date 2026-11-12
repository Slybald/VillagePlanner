import ChantierKit
import Foundation

// Outil en ligne de commande : `swift run outils <commande>`.

let usage = """
    usage : outils <commande>
      anonymiser <entrée> <sortie>
      maj-reference [--cache]        télécharge les sources, écrit reference.json et le rapport
                                     (--cache : sans réseau, depuis le dernier téléchargement)
      maj-images                     télécharge les illustrations manquantes dans App/Ressources/Illustrations
    """

let arguments = CommandLine.arguments.dropFirst()
switch arguments.first {
case nil, "aide", "-h", "--help":
    print(usage)
case "anonymiser":
    let a = Array(arguments.dropFirst())
    guard a.count == 2 else { print(usage); exit(64) }
    do { try Anonymiser.lancer(entrée: a[0], sortie: a[1]) } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
case "maj-reference":
    let a = Array(arguments.dropFirst())
    guard a.isEmpty || a == ["--cache"] else { print(usage); exit(64) }
    do { try MajReference.lancer(horsLigne: a == ["--cache"]) } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
case "maj-images":
    guard arguments.count == 1 else { print(usage); exit(64) }
    do { try MajImages.lancer() } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
default:
    FileHandle.standardError.write(Data("commande inconnue : \(arguments.first!)\n\(usage)\n".utf8))
    exit(64)
}
