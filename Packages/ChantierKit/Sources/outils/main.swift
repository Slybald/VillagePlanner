import ChantierKit
import Foundation

// Outil en ligne de commande : `swift run outils <commande>`.
// Les commandes arrivent avec T02 (anonymiser) et T04 (maj-reference).

let usage = """
    usage : outils <commande>
      anonymiser <entrée> <sortie>   (T02)
      maj-reference                  (T04)
    """

let arguments = CommandLine.arguments.dropFirst()
switch arguments.first {
case nil, "aide", "-h", "--help":
    print(usage)
default:
    FileHandle.standardError.write(Data("commande inconnue : \(arguments.first!)\n\(usage)\n".utf8))
    exit(64)
}
