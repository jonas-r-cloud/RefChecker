import SwiftUI

struct SettingsView: View {
    @AppStorage(SettingsKey.contactEmail) private var contactEmail = ""
    @AppStorage(SettingsKey.useCrossref) private var useCrossref = true
    @AppStorage(SettingsKey.useDBLP) private var useDBLP = true
    @AppStorage(SettingsKey.useOpenAlex) private var useOpenAlex = true
    @AppStorage(SettingsKey.useAISeL) private var useAISeL = true
    @AppStorage(SettingsKey.requireDOI) private var requireDOI = true
    @AppStorage(SettingsKey.checkVolumeIssuePages) private var checkVolumeIssuePages = true
    @AppStorage(SettingsKey.parallelRequests) private var parallelRequests = 3

    var body: some View {
        Form {
            Section("Metadata providers") {
                Toggle("Crossref (journals, proceedings, books with DOIs)", isOn: $useCrossref)
                Toggle("DBLP (computer science)", isOn: $useDBLP)
                Toggle("OpenAlex (all disciplines)", isOn: $useOpenAlex)
                Toggle("AIS eLibrary (ICIS, ECIS, AMCIS, PACIS, WI, …)", isOn: $useAISeL)
                Text("AIS conference papers are read from their aisel.aisnet.org page, which also corrects records that other providers file under the Journal of the AIS.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("DOIs printed in a reference are always resolved at doi.org first.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField("Contact e-mail (optional)", text: $contactEmail)
                Text("Sent to Crossref and OpenAlex to use their faster “polite pool”.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Stepper("Parallel lookups: \(parallelRequests)", value: $parallelRequests, in: 1...8)
            }
            Section("Completeness checks") {
                Toggle("Report a missing DOI as an issue", isOn: $requireDOI)
                Toggle("Compare volume, issue and pages", isOn: $checkVolumeIssuePages)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480)
        .padding(.vertical, 8)
    }
}
