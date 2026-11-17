import VillagePlannerKit
import SwiftUI

/// « À propos » : version, date des données, mention non officielle de Supercell (PLAN §9) et crédits.
struct EcranAPropos: View {
    @Environment(ModeleApp.self) private var modele

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Espace.xl) {
                VStack(spacing: Theme.Espace.s) {
                    Image(.iconeAPropos)
                        .resizable().scaledToFit()
                        .frame(width: 128, height: 128)
                        .clipShape(RoundedRectangle(cornerRadius: 128 * 0.225, style: .continuous))
                        .shadow(color: Theme.Couleur.ombre, radius: 8, y: 4)
                        .accessibilityHidden(true)
                    Text("Village Planner").font(Theme.Police.titre).foregroundStyle(Theme.Couleur.texte)
                }
                .frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 0) {
                    ligne("Version", version)
                    Filet()
                    ligne("Données de référence", modele.reference.map { Self.jour($0.source.date) } ?? "illisibles")
                    Filet()
                    ligne("Données de conseil", Self.jour(modele.dateConseils))
                }
                .padding(.horizontal, Theme.Espace.m)
                .tuilePlanner()
                MentionLegale()
            }
            .padding(.horizontal, Theme.Espace.marge)
            .padding(.vertical, Theme.Espace.l)
        }
        .pagePlanner()
        .navigationTitle("À propos")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let v = info?["CFBundleShortVersionString"] as? String ?? "?"
        return (info?["CFBundleVersion"] as? String).map { "\(v) (\($0))" } ?? v
    }

    private func ligne(_ nom: String, _ valeur: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { Text(nom); Spacer(); Text(valeur).foregroundStyle(Theme.Couleur.texteDoux) }
            VStack(alignment: .leading, spacing: Theme.Espace.xs) { Text(nom); Text(valeur).foregroundStyle(Theme.Couleur.texteDoux) }
        }
        .font(Theme.Police.texte)
        .padding(.vertical, Theme.Espace.m)
        .accessibilityElement(children: .combine)
    }

    /// « 9 novembre 2026 » depuis une date ISO 8601, avec ou sans heure ; le texte tel quel si elle est illisible.
    private static func jour(_ iso: String) -> String {
        guard let date = try? Date(String(iso.prefix(10)), strategy: Date.ISO8601FormatStyle().year().month().day()) else {
            return iso.isEmpty ? "inconnue" : iso
        }
        return date.formatted(Date.FormatStyle(date: .long, time: .omitted, locale: Locale(identifier: "fr_FR"),
                                               timeZone: TimeZone(identifier: "UTC")!))
    }
}
