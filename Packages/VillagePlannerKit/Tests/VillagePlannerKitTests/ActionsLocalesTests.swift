import Foundation
import Testing
@testable import VillagePlannerKit

// « Lancé » (T28) : règles L1 à L7, listées en tête de ActionsLocales.swift. Villages à l'HDV 3 (aides `Prio`, `Sim`),
// dates en secondes après `Rest.date` (la photo).

@Suite struct ActionsLocalesTests {
    typealias P = Prio
    typealias S = Sim

    /// Deux canons (niveau 3 : 1 000 s) et un roi, tous chez les ouvriers.
    static let items = [P.item(P.cannon, .defenses, count: 2, [S.lv(10), S.lv(100), S.lv(1_000)]),
                        P.item(P.king, .heroes, section: "heroes", [S.lv(10), S.lv(500), S.lv(500)])]
    static let free = Profile(quietHours: nil)

    static func village(_ sections: [String: [ExportEntry]], huts: Int = 1) -> (Village, ReferenceData) {
        S.village(items, sections, huts: huts)
    }
    static func action(_ id: Int, _ level: Int, at seconds: Int) -> LocalAction {
        LocalAction(itemID: id, level: level, start: S.at(seconds))
    }
    static func upgrading(_ v: Village, _ id: Int) -> [Element] { v.elements.filter { $0.itemID == id && $0.upgrading } }

    // MARK: - L1 : à part, jamais dans la photo

    @Test func L1_lActionNeTouchePasLaPhoto_fichierAPartRelu() throws {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        let historique = HistoryStore(root: dossier.url)
        let texte = exportMinimal(1_000_000, niveauHDV: 3)
        try historique.photos.save(texte)
        let store = LocalActionStore(root: dossier.url)
        let a = Self.action(P.cannon, 3, at: 60)
        let surCouloir = LocalAction(itemID: P.king, level: 2, start: S.at(61), lane: 2)    // le couloir est gardé aussi
        #expect(store.save([a, surCouloir]))
        #expect(store.load() == [a, surCouloir])
        #expect(store.save([a]))
        #expect(store.load() == [a])
        // La photo est relue à l'octet près, et le fichier des actions est à côté du dossier des photos, pas dedans.
        let photo = try #require(historique.photos.list().first)
        #expect(historique.photos.text(of: photo) == texte)
        #expect(FileManager.default.fileExists(atPath: dossier.url.appending(path: "actions-locales.json").path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: historique.photos.directory.path) == [photo.fileName])
        // Le village de la photo ne change pas quand on applique une action : on en rend un autre.
        let (v, r) = Self.village(["buildings": [P.e(P.cannon, 2, 2)]])
        let avant = v.elements
        _ = v.applying([a], reference: r, profile: Self.free)
        #expect(v.elements == avant)
    }

    @Test func L1_fichierAbime_misDeCoteSansEtreEfface() throws {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        try FileManager.default.createDirectory(at: dossier.url, withIntermediateDirectories: true)
        let store = LocalActionStore(root: dossier.url)
        let abime = Data("{\"format\":1,\"actions\":[{\"itemID\":".utf8)
        try abime.write(to: store.url)
        #expect(store.load().isEmpty)
        #expect(try Data(contentsOf: dossier.url.appending(path: "actions-locales-abime.json")) == abime)
        // Un second fichier abîmé ne recouvre pas le premier.
        try abime.write(to: store.url)
        #expect(store.save([Self.action(P.cannon, 3, at: 1)]))
        #expect(FileManager.default.fileExists(atPath: dossier.url.appending(path: "actions-locales-abime-2.json").path))
        #expect(store.load().count == 1)
    }

    // MARK: - L2 : l'exemplaire passe en cours

    @Test func L2_unExemplaireDuGroupePasseEnCours_finEgaleDebutPlusDuree() {
        let (v, r) = Self.village(["buildings": [P.e(P.cannon, 2, 2)]])
        let res = v.applying([Self.action(P.cannon, 3, at: 60)], reference: r, profile: Self.free)
        #expect(res.refused.isEmpty)
        #expect(res.applied == [LocalLaunch(action: Self.action(P.cannon, 3, at: 60), ends: S.at(1_060))])
        let canons = res.village.elements.filter { $0.itemID == P.cannon }
        #expect(canons.map(\.count) == [1, 1])
        #expect(canons.filter(\.upgrading).map(\.upgradeEnds) == [S.at(1_060)])
        // Le plan voit un minuteur, comme ceux de la photo : il occupe l'ouvrier jusqu'à sa fin, et l'écran le retrouve.
        let plan = makePlan(for: res.village, reference: r, advice: AdviceData(), profile: Self.free, now: S.at(120))
        let pas = plan.steps.first { $0.fromSnapshot && $0.step.itemID == P.cannon }
        #expect(pas?.end == S.at(1_060))
        #expect(pas.flatMap { res.launch(of: $0.step) }?.action == Self.action(P.cannon, 3, at: 60))
        #expect(plan.steps.filter { !$0.fromSnapshot }.allSatisfy { $0.start >= S.at(1_060) })   // un seul ouvrier
    }

    @Test func L2_laReductionDuProfilEnVigueurAuDebutRaccourcitLaFin() {
        let (v, r) = Self.village(["buildings": [P.e(P.cannon, 2, 2)]])
        var profil = Self.free
        profil.builderReduction = Reduction(percent: 20, endsAt: S.at(100))
        let dedans = v.applying([Self.action(P.cannon, 3, at: 60)], reference: r, profile: profil)
        #expect(dedans.applied.first?.ends == S.at(60 + 800))
        let apres = v.applying([Self.action(P.cannon, 3, at: 200)], reference: r, profile: profil)
        #expect(apres.applied.first?.ends == S.at(200 + 1_000))                        // réduction finie au début
    }

    // MARK: - L3 : l'export fait foi

    @Test func L3_actionAvantLaPhoto_pasAppliquee() {
        let (v, r) = Self.village(["buildings": [P.e(P.cannon, 2, 2)]])
        let res = v.applying([Self.action(P.cannon, 3, at: -1)], reference: r, profile: Self.free)
        #expect(res.applied.isEmpty)
        #expect(res.refused.map(\.reason) == [.beforeSnapshot])
        #expect(Self.upgrading(res.village, P.cannon).isEmpty)
    }

    @Test func L3_unImportEffaceLesActionsAnterieures_unImportPlusAncienQueLActionLaGarde() throws {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        let historique = HistoryStore(root: dossier.url)
        let contexte = HistoryContext(reference: Rest.reference, advice: AdviceData(), profile: Profile())
        let store = LocalActionStore(root: dossier.url)
        let t0 = 1_794_000_000
        _ = ResultatImport.importer(exportMinimal(t0, niveauHDV: 3), dans: historique, context: contexte, actions: store)
        let a = LocalAction(itemID: P.cannon, level: 3, start: Date(timeIntervalSince1970: TimeInterval(t0 + 3_600)))
        store.save([a])
        // Un export pris avant l'action (mais après la photo) : l'action reste.
        _ = ResultatImport.importer(exportMinimal(t0 + 1_800, niveauHDV: 3), dans: historique, context: contexte, actions: store)
        #expect(store.load() == [a])
        // Un export refusé ou déjà là ne touche à rien.
        _ = ResultatImport.importer("bonjour", dans: historique, context: contexte, actions: store)
        #expect(store.load() == [a])
        // L'export suivant, pris à la seconde même de l'action ou après : elle est effacée.
        _ = ResultatImport.importer(exportMinimal(t0 + 3_600, niveauHDV: 3), dans: historique, context: contexte, actions: store)
        #expect(store.load().isEmpty)
        #expect(LocalAction.split([a], importedAt: a.start.addingTimeInterval(-1)) == ([], [a]))
    }

    // MARK: - L4 : poste occupé, deux actions sur le même poste

    @Test func L4_posteQueLExportMontreEncoreOccupe_actionRefusee() {
        // Un seul ouvrier, occupé par le roi jusqu'à 500 s : une action à 100 s est refusée, une à 600 s est acceptée.
        let (v, r) = Self.village(["buildings": [P.e(P.cannon, 2, 2)], "heroes": [P.e(P.king, 1, timer: 500)]])
        let tot = v.applying([Self.action(P.cannon, 3, at: 100)], reference: r, profile: Self.free)
        #expect(tot.refused.map(\.reason) == [.postBusy])
        #expect(Self.upgrading(tot.village, P.cannon).isEmpty)
        let tard = v.applying([Self.action(P.cannon, 3, at: 600)], reference: r, profile: Self.free)
        #expect(tard.applied.count == 1)
    }

    @Test func L4_deuxActionsSurLeMemePoste_laSecondeRefusee() {
        let (v, r) = Self.village(["buildings": [P.e(P.cannon, 2, 2)], "heroes": [P.e(P.king, 1)]])
        let a = Self.action(P.cannon, 3, at: 60), b = Self.action(P.king, 2, at: 120)
        let res = v.applying([b, a], reference: r, profile: Self.free)                 // examinées dans l'ordre des débuts
        #expect(res.applied.map(\.action) == [a])
        #expect(res.refused == [.init(action: b, reason: .postBusy)])
        // Deux ouvriers : les deux passent, sur les deux exemplaires du canon s'il le faut.
        let (v2, r2) = Self.village(["buildings": [P.e(P.cannon, 2, 2)]], huts: 2)
        let deux = v2.applying([a, Self.action(P.cannon, 3, at: 61)], reference: r2, profile: Self.free)
        #expect(deux.applied.count == 2)
        #expect(Self.upgrading(deux.village, P.cannon).reduce(0) { $0 + $1.count } == 2)
    }

    // MARK: - L5 : un exemplaire au repos au bon niveau

    @Test func L5_elementDisparuDansUneFusion_dejaEnCours_ouAuMaximum_refusee() {
        // Les canons ont été fusionnés : la photo n'en a plus au niveau 2.
        let (fusion, r) = Self.village(["buildings": [P.e(P.cannon, 3, 2)]], huts: 2)
        #expect(fusion.applying([Self.action(P.cannon, 3, at: 1)], reference: r, profile: Self.free).refused.map(\.reason) == [.noIdleCopy])
        // Le seul canon au niveau 2 est déjà en cours dans la photo.
        let (encours, r2) = Self.village(["buildings": [P.e(P.cannon, 2, timer: 50), P.e(P.cannon, 3)]], huts: 2)
        #expect(encours.applying([Self.action(P.cannon, 3, at: 1)], reference: r2, profile: Self.free).refused.map(\.reason) == [.noIdleCopy])
        // Au-delà du maximum de l'HDV.
        #expect(fusion.applying([Self.action(P.cannon, 4, at: 1)], reference: r, profile: Self.free).refused.map(\.reason) == [.noIdleCopy])
    }

    @Test func L5_minuteurDeLaPhotoFiniAuDebut_leNiveauSuivantSeMarque() {
        // Photo du test S0 : roi en cours vers 2 (7 200 s). Huit jours plus tard, le plan conseille roi 3 maintenant.
        let items = [P.item(P.king, .heroes, section: "heroes", [S.lv(10), S.lv(50), S.lv(50)])]
        let (v, r) = S.village(items, ["heroes": [P.e(P.king, 1, timer: 7_200)]])
        let now = S.at(8 * 86_400)
        let conseil = makePlan(for: v, reference: r, advice: AdviceData(), profile: Self.free, now: now)
            .steps.first { !$0.fromSnapshot && $0.step.itemID == P.king }
        #expect(conseil?.step.level == 3 && conseil?.start == now)
        let res = v.applying([LocalAction(itemID: P.king, level: 3, start: now)], reference: r, profile: Self.free)
        #expect(res.refused.isEmpty)
        #expect(res.village.elements.filter { $0.itemID == P.king } ==
                [Element(itemID: P.king, level: 2, count: 1, maxLevel: 3, baseLevel: 3, upgradeEnds: now.addingTimeInterval(50))])
        // Avant la fin du minuteur, le roi n'est pas encore au niveau 2 : refusée (L5 avant L4).
        #expect(v.applying([LocalAction(itemID: P.king, level: 3, start: S.at(7_000))], reference: r, profile: Self.free)
                    .refused.map(\.reason) == [.noIdleCopy])
    }

    @Test func L5_deuxMarquesSuccessivesSurLeMemeHeros_enChaine() {
        let (v, r) = Self.village(["heroes": [P.e(P.king, 1)]])
        let a = Self.action(P.king, 2, at: 10), b = Self.action(P.king, 3, at: 600)   // roi 2 fini à 510
        let res = v.applying([a, b], reference: r, profile: Self.free)
        #expect(res.refused.isEmpty)
        #expect(res.applied.map(\.ends) == [S.at(510), S.at(1_100)])
        #expect(res.village.elements.filter { $0.itemID == P.king }.map { "\($0.level)\($0.upgrading)" } == ["2true"])
        // Un groupe de deux canons : l'un fini, l'autre au repos au niveau 1 : la seconde marque prend celui qui a monté.
        let (v2, r2) = Self.village(["buildings": [P.e(P.cannon, 1, 2)]], huts: 1)
        let c1 = Self.action(P.cannon, 2, at: 10), c2 = Self.action(P.cannon, 3, at: 200)
        let res2 = v2.applying([c1, c2], reference: r2, profile: Self.free)
        #expect(res2.refused.isEmpty)
        #expect(Set(res2.village.elements.filter { $0.itemID == P.cannon }.map { "\($0.level)x\($0.count)\($0.upgrading)" })
                == ["1x1false", "2x1true"])
    }

    @Test func L4_minuteurIllisible_posteTenuJusquALaFinLaPlusTardive() {
        // Roi en cours, minuteur illisible : il tient l'ouvrier jusqu'à photo + 500 s (durée complète du niveau 2).
        let (v, r) = Self.village(["buildings": [P.e(P.cannon, 2, 2)],
                                   "heroes": [ExportEntry(id: P.king, level: 1, extras: ["timer": .string("?")])]])
        #expect(v.applying([Self.action(P.cannon, 3, at: 499)], reference: r, profile: Self.free).refused.map(\.reason) == [.postBusy])
        #expect(v.applying([Self.action(P.cannon, 3, at: 500)], reference: r, profile: Self.free).applied.count == 1)
    }

    // MARK: - L8 : les couloirs affichés

    @Test func L8_proprietes_villagesAleatoires_marquesSurLesCouloirsLibres() {
        var acceptees = 0, refusees: [String] = []
        let postes: [WorkerKind] = [.builder, .laboratory, .petHouse]
        for seed in UInt64(1)...200 {
            let (v, r, profile, now) = Aleatoire.village(seed)
            let plan0 = makePlan(for: v, reference: r, advice: AdviceData(), profile: profile, now: now)
            /// Les minuteurs de la photo de chaque couloir, sans marque : (type, niveau, fin) triés.
            func minuteurs(_ ls: [[ScheduledStep]], _ res: LocalActionsResult?) -> [[String]] {
                ls.map { $0.filter { $0.fromSnapshot && res?.launch(of: $0.step) == nil }
                    .map { "\($0.step.itemID)/\($0.step.level)/\(Int($0.end.timeIntervalSince1970))" }.sorted() }
            }
            var actions: [LocalAction] = []
            var res = v.applying([], reference: r, profile: profile)
            // Comme le bouton : on marque le conseil d'un couloir libre, on recalcule, on recommence.
            marquage: for _ in 0..<12 {
                let plan = makePlan(for: res.village, reference: r, advice: AdviceData(), profile: profile, now: now)
                for w in postes {
                    let ls = displayLanes(of: plan, worker: w, posts: v.workers[w] ?? 0, launches: res)
                    let photo = plan0.steps.filter { $0.worker == w && $0.fromSnapshot }.count
                    #expect(ls.count <= max(v.workers[w] ?? 0, photo), "graine \(seed) : couloirs en trop")
                    let base = minuteurs(displayLanes(of: plan0, worker: w, posts: v.workers[w] ?? 0, launches: nil), nil)
                    // Un minuteur fini qu'une marque a remplacé (enchaînement) disparaît ; les autres restent dans leur couloir.
                    let apres = minuteurs(ls, res)
                    #expect(apres.count == base.count && zip(apres, base).allSatisfy { Set($0).isSubset(of: $1) },
                            "graine \(seed) : un minuteur de la photo a changé de couloir")
                    for (i, l) in ls.enumerated() {
                        let debut = { (s: ScheduledStep) in res.launch(of: s.step)?.action.start ?? s.start }
                        let tries = l.sorted { (debut($0), $0.end) < (debut($1), $1.end) }
                        #expect(zip(tries, tries.dropFirst()).allSatisfy { debut($1) >= $0.end }, "graine \(seed) : chevauchement")
                        // Les marques de ce couloir sont celles qu'on y a touchées (exemplaires identiques comptés ensemble).
                        let ici = l.compactMap { res.launch(of: $0.step).map { "\($0.action.itemID)/\($0.action.level)" } }.sorted()
                        let touchees = res.applied.filter { $0.action.lane == i }
                            .filter { a in plan.steps.contains { $0.worker == w && $0.step.itemID == a.action.itemID } }
                            .map { "\($0.action.itemID)/\($0.action.level)" }.sorted()
                        #expect(ici == touchees, "graine \(seed) : marque hors de son couloir")
                    }
                }
                for w in postes {
                    let ls = displayLanes(of: plan, worker: w, posts: v.workers[w] ?? 0, launches: res)
                    for (i, l) in ls.enumerated() where !l.contains(where: { $0.fromSnapshot && $0.end > now }) {
                        guard let conseil = l.first(where: { !$0.fromSnapshot }), conseil.start <= now else { continue }
                        let a = LocalAction(itemID: conseil.step.itemID, level: conseil.step.level, start: now, lane: i)
                        let essai = v.applying(actions + [a], reference: r, profile: profile)
                        if let refus = essai.refused.first(where: { $0.action == a }) {
                            refusees.append("graine \(seed) \(a.itemID)→\(a.level) \(refus.reason)")
                            continue
                        }
                        actions.append(a)
                        res = essai
                        acceptees += 1
                        continue marquage
                    }
                }
                break
            }
        }
        print("L8 : \(acceptees) marques acceptées, \(refusees.count) refusées")
        #expect(acceptees > 100)
        #expect(refusees.isEmpty, "\(refusees.prefix(5))")
    }

    // MARK: - Action annulée

    @Test func actionAnnulee_leVillageRedevientLaPhoto() {
        let dossier = DossierTemporaire(); defer { dossier.supprimer() }
        let store = LocalActionStore(root: dossier.url)
        let (v, r) = Self.village(["buildings": [P.e(P.cannon, 2, 2)]])
        let a = Self.action(P.cannon, 3, at: 60)
        store.save([a])
        store.save(store.load().filter { $0 != a })                                     // retirée d'un geste
        let res = v.applying(store.load(), reference: r, profile: Self.free)
        #expect(res.applied.isEmpty && res.refused.isEmpty)
        #expect(res.village.elements == v.elements)
        // Remise (« Annuler ») : la même action revient avec la même fin.
        store.save(store.load() + [a])
        #expect(v.applying(store.load(), reference: r, profile: Self.free).applied.first?.ends == S.at(1_060))
    }

    // MARK: - L6 : changement de profil après l'action

    @Test func L6_changementDeProfilApresLAction_laFinEstRecalculee() {
        let (v, r) = Self.village(["buildings": [P.e(P.cannon, 2, 2)]])
        let a = Self.action(P.cannon, 3, at: 60)
        #expect(v.applying([a], reference: r, profile: Self.free).applied.first?.ends == S.at(1_060))
        var corrige = Self.free
        corrige.builderReduction = Reduction(percent: 50, endsAt: .distantFuture)       // ajoutée après coup
        #expect(v.applying([a], reference: r, profile: corrige).applied.first?.ends == S.at(560))
        // La clé du conseil change avec les actions.
        func cle(_ actions: [LocalAction]) -> String {
            CleConseil.make(photo: v.date, profil: Self.free, actionsLocales: actions.map(\.adviceKey), referenceCommit: "c",
                            conseilsDate: "d", etatDuPlan: "e", now: S.at(100), timeZone: S.utc)
        }
        #expect(cle([]) != cle([a]))
        #expect(cle([a]) == cle([a]))
        #expect(cle([a]) != cle([Self.action(P.cannon, 3, at: 61)]))
    }

    // MARK: - L7 : les écarts du ticket

    @Test func L7_ecarts_marqueeMaisPasEnCours_enCoursMaisPasMarquee() {
        let (avant, _) = Self.village(["buildings": [P.e(P.cannon, 2, 2)], "heroes": [P.e(P.king, 1)]], huts: 2)
        // Marqués : un canon vers 3 et le roi vers 2. L'export montre le roi en cours et les deux canons en cours.
        let (apres, _) = Self.village(["buildings": [P.e(P.cannon, 2, 2, timer: 900)], "heroes": [P.e(P.king, 1, timer: 400)]], huts: 2)
        let marques = [Self.action(P.cannon, 3, at: 60), Self.action(P.king, 2, at: 70)]
        #expect(launchGaps(erased: marques, old: avant, new: apres) ==
                [LaunchGap(kind: .runningNotMarked, itemID: P.cannon, level: 3, count: 1)])
        // L'export ne montre rien : les deux marques sont des écarts.
        #expect(launchGaps(erased: marques, old: avant, new: avant) ==
                [LaunchGap(kind: .markedNotRunning, itemID: P.cannon, level: 3, count: 1),
                 LaunchGap(kind: .markedNotRunning, itemID: P.king, level: 2, count: 1)])
        // Marquée puis déjà finie dans l'export (le roi est au niveau 2) : pas d'écart.
        let (fini, _) = Self.village(["buildings": [P.e(P.cannon, 2, 2)], "heroes": [P.e(P.king, 2)]], huts: 2)
        #expect(launchGaps(erased: [Self.action(P.king, 2, at: 70)], old: avant, new: fini).isEmpty)
        // Rien n'était marqué : pas de reproche.
        #expect(launchGaps(erased: [], old: avant, new: apres).isEmpty)
    }
}
