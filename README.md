# RefChecker

<img src="/RefChecker.png">

A macOS app that checks whether the references of a research paper are **correct** and **complete**.

1. **Parse** – opens a PDF (or text file) and removes running headers, footers, page numbers and publisher stamps
   (lines in the top/bottom margin that recur across pages, page numbers, "Downloaded from…", arXiv/IEEE stamps), so a
   reference that continues on the next page is joined correctly. The removed lines can be reviewed under
   *Removed … header/footer lines*. It then finds the *References / Bibliography / Literatur* section and splits it into
   entries (numbered `[1]`, `1.`, alphanumeric `[Smi20]`, or unnumbered author–year lists). Each entry is parsed into
   authors, title, venue, year and DOI (IEEE, ACM, APA/Harvard, Springer LNCS, Vancouver-style heuristics).
2. **Retrieve** – looks each reference up online:
   - a DOI printed in the reference is resolved at **doi.org** (Crossref, DataCite, … DOIs),
   - **Crossref** bibliographic search with the full reference string,
   - **DBLP** (computer science) and **OpenAlex** (all disciplines) as fallbacks,
   - the **AIS eLibrary** (aisel.aisnet.org) for AIS conference papers (see below).

   The search stops at the first convincing hit. Otherwise the best-scoring candidate is used, if it is plausible.
3. **Compare & present** – shows the original reference and the retrieved metadata **side by side**:
   - the original text has the matching parts highlighted **green** and the differing parts **red**,
   - a field table (Title, Authors, Year, Venue/Publisher, Volume, Issue, Pages, DOI) colours each row
     **green** (exact match), **red** (mismatch, or missing from the reference = incomplete) or grey (the provider has no value).

   "Exact" ignores case, accents, ligatures, punctuation and line breaks, so `Ef­ficient` (hyphenated in the PDF) matches `Efficient`.
4. **Output** – *Print…* (⌘P, use *PDF › Save as PDF* in the dialog for a PDF) or *Export Report as HTML…* (⌘E).

## Requirements

- macOS 13 Ventura or later
- Xcode 15+ (or the Xcode Command Line Tools with Swift 5.9+)

## Build & run

```bash
cd RefChecker
./build-app.sh            # creates build/RefChecker.app (ad-hoc signed)
open build/RefChecker.app
```

Or in Xcode: **File › Open…** → select `Package.swift`, choose the `RefChecker` scheme and **My Mac**, then **Run** (⌘R).
Run the unit tests with `swift test` or ⌘U.

## Usage

1. **Open Paper…** (⌘O) or drop a PDF onto the window.
2. Check the extracted reference list on the left. If the heading was not found or the PDF text is messy,
   edit the text or paste the reference list there (one reference per paragraph works best),
   then **Split into References** (⇧⌘R).
3. **Check References** (⌘K). Results appear as they come in. Use the *Problems* filter to see only the references that
   need attention, and ↻ on a card to check one reference again.
4. **Print** or **Export HTML**.

### Marking a reference as resolved

If you have checked a flagged reference yourself (e.g. an accepted venue abbreviation or an online-first year), choose
**Resolve** on its card and optionally give a reason. The reference then counts as verified: green badge and border,
included in the *verified* count, hidden from the *To check* filter. The decision stays visible, though:

- the badge reads **Resolved** together with the automatic verdict (*was: 2 issues*),
- a line states when you resolved it and why,
- the field table, the highlights and the evidence keep their automatic colours,
- the printed/HTML report marks it as *Resolved manually*.

**Reopen** (or *Undo*) restores the automatic verdict. Resolutions are stored by the reference text, ignoring line
breaks and punctuation, so they persist across re-checks, re-splitting and reopening the paper later.

### Editing the reference list

After a paper is opened, or after **Split into References**, the list on the left is laid out like a paper's
reference list: one reference per paragraph, each paragraph's wrapped lines indented (hanging indent), and an
empty line between references. **An empty line always ends a reference.** To split two references that were run
together, put the cursor between them, press Return twice, and choose *Split into References* (⇧⌘R). In a numbered
list, the split-off part gets the label of its predecessor plus a letter ("12b"). If no "References" heading was found,
the full text is left as it is until you split it.

### Is every reference extracted?

After splitting, the list is checked for completeness: every piece of its text belongs to a reference, numbered lists
have no gaps or duplicates, and no entry looks like two references run together or like a fragment. A missing number
does not merge the rest of the list into one reference; the splitter steps over up to three missing numbers. When
something looks wrong, the line under the reference list reads *N references – check the split* in orange; hover
over it for the details.

### Citations in the text

When you open the whole paper, the text before the reference list is searched for citations. Every card shows
**Cited n×** (or **Not cited in text** in orange); click it to see each passage. Numbered papers are matched by
`[3]`, `[2, 5–7]`, `[4, p. 12]`. Author–year papers are matched by the first author's family name followed by the
year within the same citation: "Smith et al. (2020)", "(Smith & Doe, 2020; Jones, 2019)". Suffixes such as 2020a are
respected. For a pasted reference list there is no text to search, and the counts are not shown.

**A reference that is never cited in the text counts as an issue**: the card's verdict gains an issue, the citation
badge turns red, and the reference appears under *with issues*. If the citation is written in a form the app does not
recognise, use *Resolve*.

### Starting over

**Reset All** (toolbar, top right) removes the paper, the reference list, all results and the browser page, after a
confirmation. Settings and the references you marked as resolved are kept.

### Filtering the results

The summary pills (*verified*, *to review*, *with issues*, *not found*) are filters: click one to show only those
references, and click it again to show all. The segmented control offers *All*, *To check* (everything not verified)
and *Verified*.

### Searching the reference list

The search field above the reference list highlights every match (ignoring case and accents) and shows
*n of m*. Use ↩ or the arrows to move between matches. ⌘F inside the text, or *Edit › Find in Reference List…* (⌥⌘F),
opens the standard find bar with *Replace*. On a result card, the magnifier button scrolls the list to that
reference and selects its beginning.

### Browser pane

*View › Show Browser* (⇧⌘B), or the *Browser* toolbar button, opens a browser pane on the right. The **Website** button
on a card opens the record there: the DOI landing page, otherwise the provider's landing page (e.g. the AISeL page).
For a reference that was not found, the button says **Search Scholar** and runs a Google Scholar search for it. The
pane has back/forward, reload and an address field that takes URLs, DOIs or search terms, plus a button that opens the
current page in your default browser. The card shown in the pane is outlined in the accent colour, and the page and
history stay when you hide the pane.

### Settings (⌘,)

- Enable or disable Crossref / DBLP / OpenAlex.
- Contact e-mail: optional. Crossref and OpenAlex route requests that include one to their faster "polite pool".
- Whether a missing DOI counts as an issue, and whether volume/issue/pages are compared.
- Whether a missing article number counts as an issue (an article number that is given is always compared).
- Text size of the reference list and of the results panel (*Text size*).
- Number of parallel lookups (default 3; keep it low to respect the APIs' rate limits).

## AIS conference papers (ICIS, ECIS, AMCIS, PACIS, WI, …)

Most AIS conference papers have no DOI. Crossref then has no record, and Crossref or OpenAlex sometimes file them
under the *Journal of the AIS*. RefChecker therefore reads such papers from their AISeL landing page. The page's
citation meta tags give the title, authors and date, and the collection in the URL (`/icis2020/…`, `/ecis2021_rp/…`,
`/wi2021/…`) gives the conference and year. The venue becomes e.g.
*International Conference on Information Systems (ICIS 2020)*, and the reference counts as matching if it names the
conference in full, as "ICIS 2020" or as "ICIS 2020 Proceedings".

AISeL pages sometimes list a university or company as a co-author, or append it to an author's name
("Smith, John, University of Bamberg"). RefChecker separates these affiliations from the authors:

- An entry that AISeL itself tags as an institution (`bepress_citation_author_institution`) is dropped with certainty,
  so the Authors field can still be green.
- An entry recognised only by its wording ("University", "Institut", "GmbH", "SAP SE", …) is dropped too, but the
  Authors field becomes amber, because the decision is a heuristic.
- People whose surname is such a word ("Bank, Michael") stay authors.
- If every author of a record would be dropped on wording alone, nothing is dropped.

The Authors row says what was ignored and why.

The same applies to **Crossref, doi.org and OpenAlex** records. Some publishers deposit affiliations as authors; the
Journal of the AIS, for example, lists "Dorothy E. Leidner", "Baylor University, USA", "Olgerta Tona",
"University of Gothenburg, Sweden". An affiliation is set aside **for certain** when the record's own affiliation data
names it, or when an organisation word comes with a country ("…University, USA"), also when the record splits it into
two entries ("Baylor University" + "USA"). Otherwise it is set aside on wording alone, and the field stays amber
unless an independent source (e.g. DBLP) lists exactly the reference's authors. DBLP is not filtered, because its
author data is curated.

**References that repeat the error** are flagged red. When a reference's own author list contains affiliations
("Dorothy E. Leidner, Baylor University, USA, Olgerta Tona, …"), the Authors field is red with *The reference lists
affiliations as authors: "Baylor University, USA", … – remove them*, and those passages are highlighted red. A corporate
author standing alone (e.g. "American Psychological Association") is not flagged.

AISeL is also searched for any reference to a conference on information systems that has **no link**
("…European Conference on Information Systems…", ICIS, ECIS, AMCIS, PACIS, WI, ACIS, MCIS, UKAIS, Bled, …). The routes, in
order: AISeL links in DBLP/OpenAlex records, the AISeL site search (title phrase, then plain words), and a web search
restricted to aisel.aisnet.org. If the parsed title is unusable, the longest sentence of the reference is used. When
nothing is found, the card lists every route tried and its result.

AISeL is consulted when
- the reference names an AIS conference or AISeL,
- the best generic record is attributed to an AIS outlet that the reference does not name, or
- no record was found anywhere.

The app finds the AISeL page in this order: an AISeL link in the reference itself, then AISeL links in DBLP/OpenAlex
records, then the AISeL site search. If the AISeL record replaces a record from another provider, the card shows a note
such as *"OpenAlex attributes this paper to 'Journal of the Association for Information Systems'; the AIS eLibrary
record was used instead."* You can switch this off in Settings.

## What green guarantees

Green means **confirmed**, and a field is green only if all three conditions hold:

1. **The right work was found.** *Certain*: the DOI or AISeL link printed in the reference leads to the record.
   *High confidence*: title, every author and the year agree. Otherwise, e.g. when only the title fits, which happens
   with the journal version of a conference paper, no field can be green.
2. **The value is backed by a trustworthy source.** Either a publisher-registered record (DOI metadata at doi.org/Crossref,
   or the paper's AIS eLibrary page), or two independent databases (DBLP, OpenAlex) that agree. If a publisher-registered
   source disagrees, the field is not green.
3. **The reference says exactly the same.** Only capitalisation, accents, punctuation and line breaks are ignored, and
   the evidence column says when that was needed. Volume, issue and pages must appear in a recognisable place
   (`vol. 12`, `12(3)`, `45–67`), not merely somewhere in the text.

**Amber** (*unconfirmed*) means the value matches but one condition is not met. **Red** means it differs or is missing.
**Grey** means no source has the field. If two equally trustworthy sources disagree, a red field becomes amber.

Every card says how the record was identified and which sources were asked (✓ found the work, – did not), and it has an
*Open record* link to the source. Every field has an evidence column that explains its colour and lists what each source
says (✓ agrees with the reference, ✗ differs, – no value). The popover *What does green guarantee?* above the results
and the legend at the top of the printed/HTML report state the same rules.

To gather this evidence, the app asks the remaining sources too whenever the record is not publisher-registered or
was not identified with certainty, so checking takes a little longer than before.

Green cannot catch errors in the publisher's own metadata.

## Article numbers

Many journals (e.g. Elsevier's) have no page numbers but an article number, with or without an issue:
*Expert Systems with Applications, 243, 122886* or *Information and Organization, 35(3), 100582*. Providers often
put that number in the page field. RefChecker keeps it as a separate **Article no.** field: a single value with five
or more digits, or of the form `e1234`, counts as an article number, not a page. It is green when it follows the
volume or issue or a marker like "Article"/"Art. No.", and the volume counts as placed when an issue, article number
or first page follows it.

## Journal abbreviations

If the reference does not contain the journal's full name, RefChecker looks for its abbreviation:

1. **Official short forms:** the Crossref short title, the ISSN register's abbreviated key title (via OpenAlex), and,
   when the full name is missing, the **NLM Catalog** (MEDLINE abbreviation and ISO abbreviation, looked up by ISSN or
   exact title and cached per journal). A match is as good as the full name and can be green.
2. **ISO 4:** RefChecker abbreviates the full name by the ISO 4 rules (articles, prepositions and conjunctions dropped,
   subtitles omitted, single-word titles unabbreviated, words abbreviated by the LTWA), e.g. *Expert Systems with
   Applications* → *Expert Syst. Appl.* and *Journal of the Association for Information Systems* → *J. Assoc. Inf.
   Syst.* Only the LTWA entries common in scholarly titles are built in. A match on this generated form is **amber**,
   because no official list confirms it.

Besides the current ISO 4 form, variants with earlier LTWA abbreviations that are still widely used are tried, e.g.
*Acad. Manag. Rev.* and *Acad. Manage. Rev.* for *Academy of Management Review*. When a record has an ISSN, the ISSN
register's abbreviated key title is fetched from OpenAlex if the reference's form is not yet explained.

DOIs and URLs are never taken for a venue, title, author or number: before fields are matched they are blanked out,
so "amr" in `10.5465/amr.2011.0396` or "icis2020" in an AISeL link does not count. The DOI field is still checked.

Full stops and spacing are ignored, so the NLM style (*Expert Syst Appl*) matches too. An abbreviation must stand on its
own: it has to be followed by a number, volume/issue/page wording, a DOI/URL or the end of the reference, and it must
not continue a longer abbreviation. So *Inf. Syst.* (Information Systems) does not match *Inf. Syst. Res.*
(Information Systems Research). The Venue row names the abbreviation and its source, and lists the abbreviations
tried when none matched. The NLM lookup can be switched off in Settings.

## How matching works

| Field | Green when … |
|---|---|
| Title | the retrieved title occurs verbatim (normalised) in the reference; a missing subtitle is red |
| Authors | every retrieved family name occurs as a word in the reference (“et al.” is reported as incomplete) |
| Year | the reference year equals the issued, print or online year |
| Venue | the journal/proceedings name or one of its official abbreviations occurs in the reference |
| Volume / Issue / Pages / Article no. | the numbers appear in a recognisable place: `vol. 12`, `12(3)`, `45–67`, `243, 122886`, `35(3), 100582`, `Article 122886` |
| DOI | the reference gives the same DOI |

If a title or venue differs, the app shows the most similar passage of the reference, highlighted red, next to the
retrieved value, together with a similarity score.

## Limitations

- PDFs without a text layer (scans) need OCR first.
- Two-column PDFs sometimes come out of PDFKit with lines in the wrong order. If a reference looks wrong, fix it in the left pane.
- Volume/issue/page checks only test that the numbers are present, so a coincidental number can show as green.
- Venue names are compared literally: a reference that writes "CHI '19" where Crossref has the full proceedings title is shown red.
  This is intended, but read those rows with judgement.
- The AISeL site search parses the repository's HTML search page. If AISeL changes that page, the search step stops
  finding papers, but links in the reference and in DBLP/OpenAlex records still work.
- References without a DOI that are not indexed by any provider (grey literature, web pages, some books) are reported as *Not found*.

## Project layout

```
Package.swift
Sources/RefCheckerCore/      platform-independent logic
  ReferenceParser.swift      section extraction, splitting, field parsing
  MetadataProviders.swift    doi.org, Crossref, DBLP, OpenAlex clients
  Comparator.swift           field comparison, highlighting, candidate scoring
  PageCleaner.swift          header/footer removal for PDF text
  AISeL.swift                AIS eLibrary landing pages, conference detection
  Affiliations.swift         separating affiliations listed as authors
  ISO4.swift                 ISO 4 / LTWA journal title abbreviation
  NLMCatalog.swift           NLM Catalog abbreviation lookup
  ReferenceChecker.swift     lookup strategy per reference
  HTMLReport.swift           printable side-by-side report
  Models.swift, TextUtilities.swift
Sources/RefChecker/          SwiftUI app (PDFKit text extraction, UI, printing,
                             searchable reference list, browser pane)
Tests/RefCheckerCoreTests/   unit tests
Support/Info.plist           app bundle metadata
build-app.sh                 builds build/RefChecker.app
```
