import Foundation

/// Journal title abbreviation by the ISO 4 rules: articles, prepositions and conjunctions are
/// dropped, single-word titles stay whole, and each word is abbreviated by the LTWA (List of
/// Title Word Abbreviations, ISSN International Centre). Only the LTWA entries common in scholarly
/// titles are included; words not in the list are kept unabbreviated, as ISO 4 prescribes.
/// NLM abbreviations follow the same rules without full stops, so the comparison (which ignores
/// punctuation) covers both.
public enum ISO4 {
    /// Dropped words (ISO 4 § 6.1.3): articles, prepositions, conjunctions in common title languages.
    static let dropped: Set<String> = [
        "a", "an", "the", "of", "and", "for", "in", "on", "at", "to", "with", "by", "from", "into", "&", "+",
        "und", "der", "die", "das", "des", "dem", "den", "für", "fur", "im", "zur", "zum", "über",
        "de", "la", "le", "les", "du", "et", "en", "y", "el", "los", "las", "di", "e", "del", "della", "per"
    ]

    /// LTWA entries: whole words, and stems ending in "-" that match any word beginning with them.
    static let ltwa: [(word: String, abbreviation: String)] = [
        ("abstract", "abstr."), ("academ-", "acad."), ("accounting", "account."), ("acoust-", "acoust."),
        ("administrat-", "adm."), ("advanc-", "adv."), ("affair-", "aff."), ("agricultur-", "agric."),
        ("america-", "am."), ("analy-", "anal."), ("annal-", "ann."), ("annual", "annu."),
        ("anthropolog-", "anthropol."), ("applica-", "appl."), ("applied", "appl."), ("architect-", "archit."),
        ("archive-", "arch."), ("artificial", "artif."), ("association", "assoc."), ("automat-", "autom."),
        ("behavio-", "behav."), ("biolog-", "biol."), ("british", "br."), ("bulletin", "bull."),
        ("business", "bus."), ("canad-", "can."), ("center", "cent."), ("centre", "cent."), ("chemi-", "chem."),
        ("clinic-", "clin."), ("cognit-", "cogn."), ("collaborat-", "collab."), ("commerc-", "commer."),
        ("communica-", "commun."), ("comparat-", "comp."), ("computa-", "comput."), ("comput-", "comput."),
        ("conference", "conf."), ("consum-", "consum."), ("contemporary", "contemp."), ("cybernet-", "cybern."),
        ("decision", "decis."), ("design", "des."), ("develop-", "dev."), ("digital", "digit."),
        ("dynamic-", "dyn."), ("ecolog-", "ecol."), ("econom-", "econ."), ("educat-", "educ."),
        ("electrical", "electr."), ("electronic-", "electron."), ("empiric-", "empir."), ("engineer-", "eng."),
        ("enterprise", "enterp."), ("entrepreneur-", "entrep."), ("environment-", "environ."),
        ("ergonom-", "ergon."), ("europ-", "eur."), ("evaluat-", "eval."), ("experiment-", "exp."),
        ("financial", "financ."), ("forecast-", "forecast."), ("foundation", "found."), ("frontier", "front."),
        ("futur-", "futur."), ("general", "gen."), ("geograph-", "geogr."), ("global", "glob."),
        ("govern-", "gov."), ("graphic-", "graph."), ("healthcare", "healthc."), ("histor-", "hist."),
        ("hospital-", "hosp."), ("human-", "hum."), ("industr-", "ind."), ("informatics", "inform."),
        ("information", "inf."), ("innovat-", "innov."), ("institut-", "inst."), ("instrument-", "instrum."),
        ("integrat-", "integr."), ("intelligen-", "intell."), ("interact-", "interact."),
        ("interdisciplinary", "interdiscip."), ("international", "int."), ("investigat-", "investig."),
        ("journal", "j."), ("knowledge", "knowl."), ("laborator-", "lab."), ("language-", "lang."),
        ("learning", "learn."), ("letter-", "lett."), ("librar-", "libr."), ("linguist-", "linguist."),
        ("logist-", "logist."), ("machine-", "mach."), ("magazine", "mag."), ("manag-", "manag."),
        ("manufactur-", "manuf."), ("market-", "mark."), ("material-", "mater."), ("mathemat-", "math."),
        ("measur-", "meas."), ("mechan-", "mech."), ("medic-", "med."), ("methodolog-", "methodol."),
        ("model-", "model."), ("monograph-", "monogr."), ("multimedia", "multimed."), ("national", "natl."),
        ("natur-", "nat."), ("network-", "netw."), ("operation-", "oper."), ("optimi-", "optim."),
        ("organi-", "organ."), ("pacific", "pac."), ("perform-", "perform."), ("personal-", "pers."),
        ("perspective-", "perspect."), ("philosoph-", "philos."), ("physic-", "phys."), ("planning", "plann."),
        ("politic-", "polit."), ("practic-", "pract."), ("proceedings", "proc."), ("process-", "process."),
        ("product-", "prod."), ("professional", "prof."), ("program-", "program."), ("psycholog-", "psychol."),
        ("publication-", "publ."), ("quarterly", "q."), ("quantitat-", "quant."), ("record-", "rec."),
        ("regional", "reg."), ("reliab-", "reliab."), ("report-", "rep."), ("research-", "res."),
        ("resource-", "resour."), ("retail-", "retail."), ("review-", "rev."), ("robot-", "robot."),
        ("scandinavia-", "scand."), ("scien-", "sci."), ("security", "secur."), ("semantic-", "semant."),
        ("series", "ser."), ("servic-", "serv."), ("simulat-", "simul."), ("social", "soc."),
        ("societ-", "soc."), ("sociolog-", "sociol."), ("software", "softw."), ("special-", "spec."),
        ("statistic-", "stat."), ("strateg-", "strateg."), ("studies", "stud."), ("study", "stud."),
        ("sustainab-", "sustain."), ("symposium", "symp."), ("system-", "syst."), ("technical", "tech."),
        ("technique-", "tech."), ("technolog-", "technol."), ("telecommunica-", "telecommun."),
        ("theoretical", "theor."), ("tourism", "tour."), ("transaction-", "trans."), ("transport-", "transp."),
        ("universit-", "univ."), ("visual-", "vis."), ("yearbook", "yearb.")
    ]

    private static let exact: [String: String] = Dictionary(
        ltwa.filter { !$0.word.hasSuffix("-") }.map { ($0.word, $0.abbreviation) }, uniquingKeysWith: { a, _ in a })
    private static let stems: [(String, String)] = ltwa.filter { $0.word.hasSuffix("-") }
        .map { (String($0.word.dropLast()), $0.abbreviation) }
        .sorted { $0.0.count > $1.0.count }

    /// Abbreviations from earlier LTWA editions that are still in wide use
    /// ("Acad. Manage. Rev." next to the current "Acad. Manag. Rev.").
    static let earlierForms: [(stem: String, abbreviation: String)] = [
        ("manag", "manage."), ("information", "inform."), ("system", "sys."), ("organi", "organiz."),
        ("technolog", "tech."), ("international", "intl.")
    ]

    /// The current ISO 4 abbreviation first, then variants with earlier LTWA forms (at most eight).
    public static func variants(_ title: String) -> [String] {
        guard let primary = abbreviate(title) else { return [] }
        let main = title.components(separatedBy: ":").first ?? title
        let words = main.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
            .filter { !dropped.contains($0.lowercased()) }
        let options: [[String]] = words.map { word in
            let current = abbreviateWord(word)
            let earlier = earlierForms.first { word.lowercased().hasPrefix($0.stem) }
                .map { $0.abbreviation.prefix(1).uppercased() + $0.abbreviation.dropFirst() }
            return earlier.map { $0 == current ? [current] : [current, $0] } ?? [current]
        }
        var results = [""]
        for choices in options {
            results = results.flatMap { prefix in choices.map { prefix.isEmpty ? $0 : prefix + " " + $0 } }
            if results.count > 8 { results = Array(results.prefix(8)) }
        }
        return [primary] + results.filter { $0 != primary }
    }

    /// "Expert Systems with Applications" → "Expert Syst. Appl.";
    /// "Journal of the Association for Information Systems" → "J. Assoc. Inf. Syst.".
    /// Nil when nothing would be abbreviated (e.g. single-word titles).
    public static func abbreviate(_ title: String) -> String? {
        // Subtitles are omitted.
        let main = title.components(separatedBy: ":").first ?? title
        let words = main.split(whereSeparator: { $0.isWhitespace || $0 == "," }).map(String.init)
            .filter { !dropped.contains($0.lowercased()) }
        guard words.count > 1 else { return nil }
        let abbreviated = words.map(abbreviateWord)
        let result = abbreviated.joined(separator: " ")
        return result == words.joined(separator: " ") ? nil : result
    }

    static func abbreviateWord(_ word: String) -> String {
        // Hyphenated words are abbreviated part by part; acronyms ("MIS", "IEEE") stay.
        if word.contains("-") {
            return word.split(separator: "-").map { abbreviateWord(String($0)) }.joined(separator: "-")
        }
        if word.count > 1, word.allSatisfy({ $0.isUppercase || $0.isNumber }) { return word }
        let lower = word.lowercased()
        let abbreviation = exact[lower] ?? stems.first { lower.hasPrefix($0.0) }?.1
        guard let abbreviation, abbreviation.count - 1 < word.count else { return word }
        return abbreviation.prefix(1).uppercased() + abbreviation.dropFirst()
    }
}
