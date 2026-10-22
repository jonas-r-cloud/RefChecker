# RefChecker

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

### Settings (⌘,)

- Enable or disable Crossref / DBLP / OpenAlex.
- Contact e-mail: optional. Crossref and OpenAlex route requests that include one to their faster "polite pool".
- Whether a missing DOI counts as an issue, and whether volume/issue/pages are compared.
- Number of parallel lookups (default 3; keep it low to respect the APIs' rate limits).

## AIS conference papers (ICIS, ECIS, AMCIS, PACIS, WI, …)

Most AIS conference papers have no DOI. Crossref then has no record, and Crossref or OpenAlex sometimes file them
under the *Journal of the AIS*. RefChecker therefore reads such papers from their AISeL landing page. The page's
citation meta tags give the title, authors and date, and the collection in the URL (`/icis2020/…`, `/ecis2021_rp/…`,
`/wi2021/…`) gives the conference and year. The venue becomes e.g.
*International Conference on Information Systems (ICIS 2020)*, and the reference counts as matching if it names the
conference in full, as "ICIS 2020" or as "ICIS 2020 Proceedings".

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

## How matching works

| Field | Green when … |
|---|---|
| Title | the retrieved title occurs verbatim (normalised) in the reference; a missing subtitle is red |
| Authors | every retrieved family name occurs as a word in the reference (“et al.” is reported as incomplete) |
| Year | the reference year equals the issued, print or online year |
| Venue | the journal/proceedings name or one of its official abbreviations occurs in the reference |
| Volume / Issue / Pages | the numbers occur in the reference |
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
  ReferenceChecker.swift     lookup strategy per reference
  HTMLReport.swift           printable side-by-side report
  Models.swift, TextUtilities.swift
Sources/RefChecker/          SwiftUI app (PDFKit text extraction, UI, printing)
Tests/RefCheckerCoreTests/   unit tests
Support/Info.plist           app bundle metadata
build-app.sh                 builds build/RefChecker.app
```
