import SwiftUI

/// Un libellé et sa valeur : côte à côte quand ils tiennent sur une ligne, l'un sous l'autre sinon
/// (très grande police : la valeur ne se coupe plus en pleine syllabe).
struct LigneEtiquetee<Gauche: View, Droite: View>: View {
    @ViewBuilder let gauche: Gauche
    @ViewBuilder let droite: Droite

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Theme.Espace.xs) {
                gauche
                Spacer(minLength: Theme.Espace.m)
                droite
            }
            VStack(alignment: .leading, spacing: Theme.Espace.xs) {
                gauche
                droite
            }
        }
    }
}
