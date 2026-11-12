import ChantierKit
import Foundation

// Outil en ligne de commande : `swift run outils <commande>`.
// Les commandes arrivent avec T02 (anonymiser) et T04 (maj-reference).

let usage = """
    usage : outils <commande>
      anonymiser <entrée> <sortie>
      maj-reference                  (T04)
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
default:
    FileHandle.standardError.write(Data("commande inconnue : \(arguments.first!)\n\(usage)\n".utf8))
    exit(64)
}
