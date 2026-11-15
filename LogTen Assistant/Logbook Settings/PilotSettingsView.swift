import LogbookModel
import SwiftUI

/// Logbook Settings ▸ Pilot: the certificates and preferences that decide which regulations
/// apply.
struct PilotSettingsView: View {
  private static let timeZoneIdentifiers = TimeZone.knownTimeZoneIdentifiers.sorted()

  @Binding var pilot: PilotProfile
  let people: [Person]

  @State private var isLookingUpAirman = false

  var body: some View {
    Form {
      Section("Logbook") {
        Picker("Owner", selection: $pilot.ownerPersonID) {
          Text("None").tag(RecordID?.none)
          ForEach(people) { person in
            Text(person.name).tag(RecordID?.some(person.id))
          }
        }
        .accessibilityIdentifier("pilot.owner")
        Picker("Home Time Zone", selection: $pilot.homeTimeZone) {
          ForEach(Self.timeZoneIdentifiers, id: \.self) { identifier in
            if let zone = TimeZone(identifier: identifier) {
              Text(identifier.replacing("_", with: " ")).tag(zone)
            }
          }
        }
        .accessibilityIdentifier("pilot.timeZone")
        Toggle("Ignore instruction activity", isOn: $pilot.ignoresInstructionActivity)
          .spotlightTarget(.pilot(.ignoresInstructionActivity))
          .accessibilityIdentifier("pilot.ignoresInstruction")
      }

      Section("Certificates") {
        Picker("Certificate", selection: $pilot.certificateLevel) {
          ForEach(CertificateLevel.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        .spotlightTarget(.pilot(.certificate))
        .accessibilityIdentifier("pilot.certificate")
        LabeledContent {
          Button("Look Up…") { isLookingUpAirman = true }
            .accessibilityIdentifier("pilot.airmenLookup")
        } label: {
          Text("FAA Airmen Database")
          Text("Fills in your certificate and ratings from the FAA’s records.")
        }
      }

      RatingSection(
        title: "Category and Class Ratings",
        ratings: CategoryClassRating.allCases,
        selection: $pilot.categoryClassRatings,
        name: \.title,
        identifierPrefix: "pilot.categoryClass"
      )
      RatingSection(
        title: "Instrument Ratings",
        ratings: InstrumentRating.allCases,
        selection: $pilot.instrumentRatings,
        name: \.title,
        identifierPrefix: "pilot.instrument",
        target: .instrumentRatings
      )
      RatingSection(
        title: "Flight Instructor Ratings",
        ratings: InstructorRating.allCases,
        selection: $pilot.instructorRatings,
        name: \.title,
        identifierPrefix: "pilot.instructor",
        target: .instructorRatings
      )

      Section {
        TypeRatingsField(typeRatings: $pilot.typeRatings)
      } header: {
        Text("Type Ratings")
      } footer: {
        Text("ICAO type designators, separated by commas, such as SF50, C510.")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .sheet(isPresented: $isLookingUpAirman) {
      AirmenLookupView(pilot: $pilot)
    }
  }
}

/// A set of ratings, one checkbox each, in two columns.
private struct RatingSection<Rating: Hashable & RawRepresentable<String>>: View {
  private static var columns: [GridItem] {
    [GridItem(.flexible(), alignment: .leading), GridItem(.flexible(), alignment: .leading)]
  }

  let title: LocalizedStringKey
  let ratings: [Rating]
  @Binding var selection: Set<Rating>
  let name: KeyPath<Rating, String>

  /// The prefix of each checkbox's accessibility identifier, followed by the rating's raw value.
  let identifierPrefix: String

  /// The pilot setting the section is, if a page can point it out.
  var target: PilotSetting?

  var body: some View {
    Section(title) {
      LazyVGrid(columns: Self.columns, alignment: .leading) {
        ForEach(ratings, id: \.self) { rating in
          Toggle(rating[keyPath: name], isOn: isOn(rating))
            .toggleStyle(.checkbox)
            .accessibilityIdentifier("\(identifierPrefix).\(rating.rawValue)")
        }
      }
      .modifier(OptionalSpotlightTarget(target: target.map(SettingsTarget.pilot)))
    }
  }

  private func isOn(_ rating: Rating) -> Binding<Bool> {
    Binding {
      selection.contains(rating)
    } set: { isOn in
      if isOn { selection.insert(rating) } else { selection.remove(rating) }
    }
  }
}

/// Marks content as a setting its page can point out, when it is one.
private struct OptionalSpotlightTarget: ViewModifier {
  let target: SettingsTarget?

  func body(content: Content) -> some View {
    if let target { content.spotlightTarget(target) } else { content }
  }
}

/// Type ratings as comma-separated designators.
private struct TypeRatingsField: View {
  @Binding var typeRatings: Set<String>

  @State private var text = ""

  var body: some View {
    TextField("Type Ratings", text: $text)
      .labelsHidden()
      .onAppear { text = typeRatings.sorted().joined(separator: ", ") }
      .onChange(of: text) { typeRatings = Self.designators(in: text) }
      .accessibilityIdentifier("pilot.typeRatings")
  }

  private static func designators(in text: String) -> Set<String> {
    Set(
      text.split(separator: ",")
        .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
        .filter { !$0.isEmpty }
    )
  }
}

#Preview("Ratings", traits: .sampleSession { $0.logbookSettingsPage = .pilot }) {
  @Environment(LogbookSession.self)
  @Previewable var session
  LogbookSettingsSheet(session: session)
    .defaultScrollAnchor(.bottom)
}

#Preview(
  "Instrument Ratings Pointed Out",
  traits: .sampleSession { session in
    session.spotlitSettings = [.pilot(.instrumentRatings)]
    session.logbookSettingsPage = .pilot
  }
) {
  @Environment(LogbookSession.self)
  @Previewable var session
  LogbookSettingsSheet(session: session)
}
