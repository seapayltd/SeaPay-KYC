//
//  VesselSheet.swift
//  OceanCheck
//
//  Add vessel: import CoR PDF, scan photo, or enter manually.
//  OCR extracts vessel name, IMO, flag, port from Certificate of Registry.
//

import SwiftUI
import PhotosUI
import Vision
import PDFKit
import UniformTypeIdentifiers
import os.log

private let corLogger = Logger(subsystem: "com.seapay.kyc", category: "CoR")

struct VesselSheet: View {
    @ObservedObject var vm: KYCViewModel
    @Environment(\.dismiss) private var dismiss

    // Mode
    @State private var mode: Mode = .choose
    enum Mode: Int, Comparable {
        case choose, scanning, review
        case stepName, stepType, stepDetails
        static func < (lhs: Mode, rhs: Mode) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    // Vessel being built
    @State private var v = Vessel(name: "")
    @State private var corImage: Data?
    @State private var corPDFData: Data?
    @State private var showCamera = false
    @State private var showFilePicker = false
    @State private var scanSource = ""
    @State private var showFlagPicker = false
    @State private var showExample = false
    @State private var nameSuggestions: [String] = []
    @FocusState private var fieldFocus: Bool

    // Photo prompt after creation
    @State private var showPhotoPrompt = false
    @State private var createdVesselId: String?
    @State private var selectedVesselPhoto: PhotosPickerItem?

    // Maritime flag states — emoji flag + name + ISO3 code + common port
    static let flagStates: [(emoji: String, name: String, code: String, port: String)] = [
        // Top open registries
        ("🇲🇭", "Marshall Islands", "MHL", "Majuro"),
        ("🇵🇦", "Panama", "PAN", "Panama City"),
        ("🇱🇷", "Liberia", "LBR", "Monrovia"),
        ("🇧🇸", "Bahamas", "BHS", "Nassau"),
        ("🇲🇹", "Malta", "MLT", "Valletta"),
        ("🇭🇰", "Hong Kong", "HKG", "Hong Kong"),
        ("🇸🇬", "Singapore", "SGP", "Singapore"),
        ("🇨🇾", "Cyprus", "CYP", "Limassol"),
        // UK Crown Dependencies & Overseas Territories
        ("🇬🇧", "United Kingdom", "GBR", "London"),
        ("🇰🇾", "Cayman Islands", "CYM", "George Town"),
        ("🇧🇲", "Bermuda", "BMU", "Hamilton"),
        ("🇬🇮", "Gibraltar", "GIB", "Gibraltar"),
        ("🇮🇲", "Isle of Man", "IMN", "Douglas"),
        ("🇻🇬", "British Virgin Islands", "VGB", "Road Town"),
        ("🇹🇨", "Turks & Caicos", "TCA", "Cockburn Town"),
        ("🇫🇰", "Falkland Islands", "FLK", "Stanley"),
        // EU member states
        ("🇬🇷", "Greece", "GRC", "Piraeus"),
        ("🇮🇹", "Italy", "ITA", "Genoa"),
        ("🇫🇷", "France", "FRA", "Marseille"),
        ("🇩🇪", "Germany", "DEU", "Hamburg"),
        ("🇳🇱", "Netherlands", "NLD", "Rotterdam"),
        ("🇩🇰", "Denmark", "DNK", "Copenhagen"),
        ("🇧🇪", "Belgium", "BEL", "Antwerp"),
        ("🇪🇸", "Spain", "ESP", "Barcelona"),
        ("🇵🇹", "Portugal", "PRT", "Lisbon"),
        ("🇮🇪", "Ireland", "IRL", "Dublin"),
        ("🇵🇱", "Poland", "POL", "Gdansk"),
        ("🇸🇪", "Sweden", "SWE", "Gothenburg"),
        ("🇫🇮", "Finland", "FIN", "Helsinki"),
        ("🇪🇪", "Estonia", "EST", "Tallinn"),
        ("🇱🇻", "Latvia", "LVA", "Riga"),
        ("🇱🇹", "Lithuania", "LTU", "Klaipeda"),
        ("🇭🇷", "Croatia", "HRV", "Split"),
        ("🇸🇮", "Slovenia", "SVN", "Koper"),
        ("🇧🇬", "Bulgaria", "BGR", "Varna"),
        ("🇷🇴", "Romania", "ROU", "Constanta"),
        ("🇦🇹", "Austria", "AUT", "Vienna"),
        ("🇱🇺", "Luxembourg", "LUX", "Luxembourg"),
        ("🇨🇿", "Czech Republic", "CZE", "Prague"),
        ("🇸🇰", "Slovakia", "SVK", "Bratislava"),
        ("🇭🇺", "Hungary", "HUN", "Budapest"),
        // EEA / EFTA
        ("🇳🇴", "Norway", "NOR", "Bergen"),
        ("🇮🇸", "Iceland", "ISL", "Reykjavik"),
        // Caribbean open registries
        ("🇦🇬", "Antigua & Barbuda", "ATG", "St. John's"),
        ("🇻🇨", "St Vincent & Grenadines", "VCT", "Kingstown"),
        ("🇯🇲", "Jamaica", "JAM", "Kingston"),
        ("🇧🇧", "Barbados", "BRB", "Bridgetown"),
        ("🇧🇿", "Belize", "BLZ", "Belize City"),
        ("🇩🇲", "Dominica", "DMA", "Roseau"),
        ("🇰🇳", "St Kitts & Nevis", "KNA", "Basseterre"),
        ("🇹🇹", "Trinidad & Tobago", "TTO", "Port of Spain"),
        // Pacific open registries
        ("🇨🇰", "Cook Islands", "COK", "Rarotonga"),
        ("🇻🇺", "Vanuatu", "VUT", "Port Vila"),
        ("🇵🇼", "Palau", "PLW", "Koror"),
        ("🇹🇻", "Tuvalu", "TUV", "Funafuti"),
        ("🇹🇴", "Tonga", "TON", "Nuku'alofa"),
        ("🇼🇸", "Samoa", "WSM", "Apia"),
        ("🇫🇯", "Fiji", "FJI", "Suva"),
        ("🇰🇮", "Kiribati", "KIR", "Tarawa"),
        // Asia-Pacific
        ("🇯🇵", "Japan", "JPN", "Tokyo"),
        ("🇰🇷", "South Korea", "KOR", "Busan"),
        ("🇨🇳", "China", "CHN", "Shanghai"),
        ("🇹🇼", "Taiwan", "TWN", "Kaohsiung"),
        ("🇮🇩", "Indonesia", "IDN", "Jakarta"),
        ("🇲🇾", "Malaysia", "MYS", "Port Klang"),
        ("🇹🇭", "Thailand", "THA", "Bangkok"),
        ("🇻🇳", "Vietnam", "VNM", "Ho Chi Minh City"),
        ("🇵🇭", "Philippines", "PHL", "Manila"),
        ("🇲🇲", "Myanmar", "MMR", "Yangon"),
        ("🇧🇩", "Bangladesh", "BGD", "Chittagong"),
        ("🇮🇳", "India", "IND", "Mumbai"),
        ("🇱🇰", "Sri Lanka", "LKA", "Colombo"),
        ("🇦🇺", "Australia", "AUS", "Sydney"),
        ("🇳🇿", "New Zealand", "NZL", "Auckland"),
        // Middle East
        ("🇦🇪", "UAE", "ARE", "Dubai"),
        ("🇸🇦", "Saudi Arabia", "SAU", "Jeddah"),
        ("🇶🇦", "Qatar", "QAT", "Doha"),
        ("🇧🇭", "Bahrain", "BHR", "Manama"),
        ("🇰🇼", "Kuwait", "KWT", "Kuwait City"),
        ("🇴🇲", "Oman", "OMN", "Muscat"),
        ("🇮🇱", "Israel", "ISR", "Haifa"),
        ("🇯🇴", "Jordan", "JOR", "Aqaba"),
        // Africa
        ("🇿🇦", "South Africa", "ZAF", "Cape Town"),
        ("🇳🇬", "Nigeria", "NGA", "Lagos"),
        ("🇰🇪", "Kenya", "KEN", "Mombasa"),
        ("🇹🇿", "Tanzania", "TZA", "Dar es Salaam"),
        ("🇪🇬", "Egypt", "EGY", "Port Said"),
        ("🇲🇦", "Morocco", "MAR", "Casablanca"),
        ("🇬🇭", "Ghana", "GHA", "Tema"),
        ("🇲🇺", "Mauritius", "MUS", "Port Louis"),
        ("🇸🇨", "Seychelles", "SYC", "Victoria"),
        // Americas
        ("🇺🇸", "United States", "USA", "New York"),
        ("🇨🇦", "Canada", "CAN", "Vancouver"),
        ("🇧🇷", "Brazil", "BRA", "Santos"),
        ("🇲🇽", "Mexico", "MEX", "Veracruz"),
        ("🇦🇷", "Argentina", "ARG", "Buenos Aires"),
        ("🇨🇱", "Chile", "CHL", "Valparaiso"),
        ("🇨🇴", "Colombia", "COL", "Cartagena"),
        ("🇪🇨", "Ecuador", "ECU", "Guayaquil"),
        ("🇵🇪", "Peru", "PER", "Callao"),
        // Eastern Europe / Black Sea
        ("🇹🇷", "Turkey", "TUR", "Istanbul"),
        ("🇷🇺", "Russia", "RUS", "St Petersburg"),
        ("🇺🇦", "Ukraine", "UKR", "Odessa"),
        ("🇬🇪", "Georgia", "GEO", "Batumi"),
        // Miscellaneous
        ("🇲🇨", "Monaco", "MCO", "Monaco"),
        ("🇲🇳", "Mongolia", "MNG", "Ulaanbaatar"),
        ("🇧🇴", "Bolivia", "BOL", "La Paz"),
    ]

    private var selectedFlag: (emoji: String, name: String, code: String, port: String)? {
        Self.flagStates.first { $0.code == v.flagState }
    }

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .choose: chooseView
                case .scanning: scanningView
                case .review: reviewFormView
                case .stepName: stepNameView
                case .stepType: stepTypeView
                case .stepDetails: stepDetailsView
                }
            }
            .animation(.smooth(duration: 0.3), value: mode)
            .background(Color.surface.ignoresSafeArea())
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button { goBack() } label: {
                        Image(systemName: mode == .choose ? "xmark" : "chevron.left").foregroundStyle(.secondary)
                    }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraCapture(result: $corImage).ignoresSafeArea()
            }
            .sheet(isPresented: $showFilePicker) {
                PDFDocumentPicker { url in
                    showFilePicker = false
                    guard let url else { return }
                    withAnimation { mode = .scanning }
                    scanSource = "pdf"
                    Task { await extractFromPDF(url) }
                }
            }
            .sheet(isPresented: $showFlagPicker) {
                FlagStatePicker(flags: Self.flagStates, selected: v.flagState) { selected in
                    v.flagState = selected.code
                    if v.portOfRegistry.isEmpty { v.portOfRegistry = selected.port }
                    showFlagPicker = false
                }
            }
            .onChange(of: corImage) { _, newValue in
                if let data = newValue {
                    withAnimation { mode = .scanning }
                    scanSource = "photo"
                    Task { await extractFromImage(data) }
                }
            }
            .sheet(isPresented: $showPhotoPrompt) {
                vesselPhotoPrompt
            }
        }
    }

    // MARK: - Photo Prompt (after creation)

    private var vesselPhotoPrompt: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Spacer()
                VStack(spacing: 24) {
                    Image(systemName: "camera.circle").font(.system(size: 56)).foregroundStyle(.quaternary)
                    Text("Add a photo of your vessel?").font(Typo.context)
                    Text("It will appear on the vessel card and detail screen").font(Typo.meta).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center).padding(.horizontal, 32)

                    PhotosPicker(selection: $selectedVesselPhoto, matching: .images) {
                        Text("Choose Photo")
                    }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 48)
                    .onChange(of: selectedVesselPhoto) { _, item in
                        guard let item else { return }
                        Task {
                            if let data = try? await item.loadTransferable(type: Data.self),
                               let vid = createdVesselId {
                                await MainActor.run {
                                    vm.saveVesselPhoto(vesselId: vid, imageData: data)
                                    showPhotoPrompt = false
                                    dismiss()
                                }
                            }
                        }
                    }

                    Button {
                        showPhotoPrompt = false
                        dismiss()
                    } label: {
                        Text("Skip").font(Typo.meta).foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .background(Color.surface.ignoresSafeArea())
        }
        .presentationDetents([.medium])
        .interactiveDismissDisabled()
    }

    // MARK: - Choose Method

    private var chooseView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 28) {
                Image(systemName: "ferry").font(.system(size: 44)).foregroundStyle(.quaternary)
                Text("Add Vessel").font(Typo.context)

                VStack(spacing: 10) {
                    choiceButton(
                        icon: "doc.richtext",
                        title: "Import CoR (PDF)",
                        subtitle: "Upload Certificate of Registry",
                        primary: true
                    ) { showFilePicker = true }

                    choiceButton(
                        icon: "camera",
                        title: "Scan CoR (Photo)",
                        subtitle: "Take a photo of the certificate",
                        primary: false
                    ) { showCamera = true }

                    Button { withAnimation(.smooth(duration: 0.25)) { mode = .stepName } } label: {
                        Text("Enter manually").font(Typo.meta).foregroundStyle(.secondary)
                    }
                    .padding(.top, 2)
                }
                .padding(.horizontal, 32)

                // Example reference
                Button { showExample = true } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "eye").font(Typo.meta)
                        Text("What does a CoR look like?").font(Typo.meta)
                    }
                    .foregroundStyle(.tertiary)
                }
            }
            Spacer()
        }
        .sheet(isPresented: $showExample) { CoRExampleSheet() }
    }

    private func choiceButton(icon: String, title: String, subtitle: String, primary: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon).font(.system(size: 20)).frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(Typo.body).fontWeight(.medium)
                    Text(subtitle).font(Typo.meta).opacity(primary ? 0.7 : 1)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).opacity(0.4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(primary ? Color.primary : Color.surfaceMuted)
            .foregroundStyle(primary ? Color.surface : .primary)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    // MARK: - Scanning

    private var scanningView: some View {
        VStack(spacing: 24) {
            Spacer()

            if let data = corImage, let img = UIImage(data: data) {
                Image(uiImage: img).resizable().scaledToFit()
                    .frame(maxHeight: 180)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.primary.opacity(0.1), lineWidth: 1))
                    .padding(.horizontal, 40)
            } else {
                Image(systemName: scanSource == "pdf" ? "doc.richtext" : "camera")
                    .font(.system(size: 40)).foregroundStyle(.quaternary)
            }

            VStack(spacing: 8) {
                ProgressView().controlSize(.regular)
                Text(extractionMethod.isEmpty ? (scanSource == "pdf" ? "Reading PDF..." : "Reading certificate...") : extractionMethod)
                    .font(Typo.body).foregroundStyle(.secondary)
                    .animation(.smooth(duration: 0.2), value: extractionMethod)
            }

            Spacer()
        }
    }

    // MARK: - Sequential Manual Entry

    // Step 1: Name
    private var stepNameView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                Text("Vessel name").font(Typo.context)

                TextField("MV Pacific Star", text: $v.name)
                    .font(.system(size: 24, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .focused($fieldFocus)
                    .submitLabel(.next)
                    .onSubmit { if !v.name.trimmingCharacters(in: .whitespaces).isEmpty { advance() } }
                    .padding(.horizontal, 40)

                Button { advance() } label: { Text("Next") }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: !v.name.trimmingCharacters(in: .whitespaces).isEmpty))
                    .disabled(v.name.trimmingCharacters(in: .whitespaces).isEmpty)
                    .padding(.horizontal, 48)
            }
            Spacer()
        }
        .onAppear { fieldFocus = true }
    }

    // Step 2: Type
    private var stepTypeView: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                Text("Vessel type").font(Typo.context)
                Text(v.name).font(Typo.meta).foregroundStyle(.secondary)

                VStack(spacing: 8) {
                    ForEach(VesselType.allCases) { vt in
                        Button {
                            withAnimation(.spring(response: 0.2)) { v.vesselType = vt }
                            // Auto-advance after brief pause
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { advance() }
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: vt.icon).font(.system(size: 16)).frame(width: 24)
                                Text(vt.rawValue).font(Typo.body)
                                Spacer()
                                if v.vesselType == vt {
                                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                                }
                            }
                            .padding(.horizontal, 16).padding(.vertical, 13)
                            .background(v.vesselType == vt ? Color.primary.opacity(0.06) : Color.surfaceMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .foregroundStyle(.primary)
                    }
                }
                .padding(.horizontal, 32)
            }
            Spacer()
        }
    }

    // Step 3: Details (flag, IMO, port)
    private var stepDetailsView: some View {
        ScrollView {
            VStack(spacing: 24) {
                Spacer(minLength: 24)

                // Context
                VStack(spacing: 4) {
                    Text(v.name).font(Typo.context)
                    if let vt = v.vesselType { Text(vt.rawValue).font(Typo.meta).foregroundStyle(.secondary) }
                }

                VStack(spacing: 16) {
                    // Flag State — tappable picker
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Flag State").font(Typo.meta).foregroundStyle(.secondary)
                        Button { showFlagPicker = true } label: {
                            HStack {
                                if let f = selectedFlag {
                                    Text("\(f.emoji) \(f.name)").font(Typo.body)
                                } else {
                                    Text("Select flag state").font(Typo.body).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.down").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                            }
                            .padding(14)
                            .background(Color.surfaceMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .foregroundStyle(.primary)
                    }

                    // IMO Number
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("IMO Number").font(Typo.meta).foregroundStyle(.secondary)
                            Spacer()
                            if !v.imoNumber.isEmpty {
                                if v.imoNumber.count == 7 && v.imoNumber.allSatisfy(\.isNumber) {
                                    Image(systemName: "checkmark.circle.fill").font(Typo.meta).foregroundStyle(Color.clear_)
                                } else {
                                    Text("7 digits").font(Typo.meta).foregroundStyle(.tertiary)
                                }
                            }
                        }
                        TextField("1234567", text: $v.imoNumber)
                            .font(.system(size: 18, weight: .medium, design: .monospaced))
                            .keyboardType(.numberPad)
                            .padding(14)
                            .background(Color.surfaceMuted)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .onChange(of: v.imoNumber) { _, new in
                                v.imoNumber = String(new.filter(\.isNumber).prefix(7))
                            }
                    }

                    // Port of Registry
                    field("Port of Registry", text: $v.portOfRegistry, prompt: selectedFlag?.port ?? "Port")

                    // Gross Tonnage — critical for compliance thresholds
                    field("Gross Tonnage (GT)", text: $v.grossTonnage, prompt: "e.g. 280")

                    // Year Built — needed for LY2/LY3 determination
                    field("Year Built", text: $v.yearBuilt, prompt: "e.g. 2019")
                }
                .padding(.horizontal, 32)

                Button { save() } label: { Text("Save Vessel") }
                    .buttonStyle(PrimaryButtonStyle())
                    .padding(.horizontal, 32)

                Spacer(minLength: 32)
            }
        }
    }

    // MARK: - Review Form (after OCR/PDF extraction)

    private var reviewFormView: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Certificate thumbnail + status
                if let data = corImage, let img = UIImage(data: data) {
                    VStack(spacing: 8) {
                        Image(uiImage: img).resizable().scaledToFit().frame(maxHeight: 120)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.primary.opacity(0.06), lineWidth: 1))
                        if !extractionMethod.isEmpty {
                            Label(extractionMethod, systemImage: extractionMethod.contains("Claude") ? "brain" : "eye")
                                .font(Typo.meta).foregroundStyle(extractionMethod.contains("fail") ? Color.review : Color.clear_)
                        }
                    }
                    .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 12)
                }

                // Vessel name — hero field
                VStack(spacing: 4) {
                    TextField("Vessel Name", text: $v.name)
                        .font(.system(size: 22, weight: .semibold))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    if let desc = v.vesselDescription.isEmpty ? nil : v.vesselDescription {
                        Text(desc).font(Typo.meta).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 8)

                // Identity
                reviewSection("Identity") {
                    reviewRow(label: "Official No.", value: $v.officialNumber, prompt: "18634")
                    Divider()
                    reviewRow(label: "Call Sign", value: $v.callSign, prompt: "9HB5447")
                    Divider()
                    reviewRow(label: "IMO", value: $v.imoNumber, prompt: "1234567")
                }

                // Registration
                reviewSection("Registration") {
                    Button { showFlagPicker = true } label: {
                        HStack {
                            Text("Flag State").font(Typo.meta).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
                            Spacer()
                            if let f = selectedFlag { Text("\(f.emoji) \(f.name)").font(Typo.body) }
                            else if !v.flagState.isEmpty { Text(v.flagState).font(Typo.body) }
                            else { Text("Select").font(Typo.body).foregroundStyle(.tertiary) }
                            Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(.quaternary)
                        }.padding(.vertical, 10)
                    }.foregroundStyle(.primary)
                    Divider()
                    reviewRow(label: "Port", value: $v.portOfRegistry, prompt: "Valletta")
                    Divider()
                    // Vessel type
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Type").font(Typo.meta).foregroundStyle(.secondary).padding(.top, 8)
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 6) {
                            ForEach(VesselType.allCases) { vt in
                                Button { withAnimation(.spring(response: 0.2)) { v.vesselType = vt } } label: {
                                    Text(vt.rawValue).font(Typo.meta).lineLimit(1).minimumScaleFactor(0.8)
                                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                                        .background(v.vesselType == vt ? Color.primary : Color.surface)
                                        .foregroundStyle(v.vesselType == vt ? Color.surface : .primary)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                }
                            }
                        }
                        .padding(.bottom, 6)
                    }
                }

                // Construction
                if !v.builder.isEmpty || !v.grossTonnage.isEmpty || !v.yearBuilt.isEmpty {
                    reviewSection("Construction") {
                        if !v.builder.isEmpty { reviewRow(label: "Builder", value: $v.builder); Divider() }
                        rowPair(reviewRow(label: "Year", value: $v.yearBuilt, prompt: "2018"), reviewRow(label: "Hull", value: $v.hullMaterial, prompt: "GRP"))
                        if !v.grossTonnage.isEmpty { Divider(); rowPair(reviewRow(label: "GT", value: $v.grossTonnage), reviewRow(label: "NT", value: $v.netTonnage)) }
                        if !v.lengthOverall.isEmpty { Divider(); rowPair(reviewRow(label: "LOA", value: $v.lengthOverall), reviewRow(label: "Beam", value: $v.breadth)) }
                    }
                }

                // Propulsion
                if !v.engineMaker.isEmpty || !v.propulsionPower.isEmpty {
                    reviewSection("Propulsion") {
                        if !v.engineMaker.isEmpty { reviewRow(label: "Engines", value: $v.engineMaker); Divider() }
                        rowPair(reviewRow(label: "Power", value: $v.propulsionPower), reviewRow(label: "Speed", value: $v.estimatedSpeed))
                    }
                }

                // Ownership
                if !v.registeredOwner.isEmpty || !v.certificateExpiry.isEmpty {
                    reviewSection("Ownership") {
                        if !v.registeredOwner.isEmpty { reviewRow(label: "Owner", value: $v.registeredOwner); Divider() }
                        if !v.certificateExpiry.isEmpty { reviewRow(label: "Expires", value: $v.certificateExpiry) }
                    }
                }

                // Save
                Button { save() } label: { Text("Save Vessel") }
                    .buttonStyle(PrimaryButtonStyle(isEnabled: canSave))
                    .disabled(!canSave)
                    .padding(.horizontal, 24).padding(.top, 20)

                Spacer(minLength: 40)
            }
        }
        .background(Color.surface)
    }

    // MARK: - Review Form Components

    private func reviewSection(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(Typo.meta).foregroundStyle(.secondary).padding(.leading, 4).padding(.top, 20)
            VStack(spacing: 1) { content() }
                .padding(.vertical, 4).padding(.horizontal, 14)
                .background(Color.surfaceMuted.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .padding(.horizontal, 16)
    }

    private func rowPair(_ left: some View, _ right: some View) -> some View {
        HStack(spacing: 8) { left; right }
    }

    private func reviewRow(label: String, value: Binding<String>, prompt: String = "") -> some View {
        HStack {
            Text(label).font(Typo.meta).foregroundStyle(.secondary).frame(width: 80, alignment: .leading)
            TextField(prompt, text: value).font(Typo.body).multilineTextAlignment(.trailing)
        }
        .padding(.vertical, 10)
    }

    // MARK: - Helpers

    private static func isNotName(_ text: String) -> Bool {
        let up = text.uppercased().trimmingCharacters(in: .whitespaces)
        // Check against known non-name words
        for word in notNameWords {
            if up == word || up.contains(word) { return true }
        }
        // Too long to be a vessel name
        if up.count > 40 { return true }
        // Contains too many words (vessel names are typically 1-4 words)
        if up.split(separator: " ").count > 5 { return true }
        return false
    }

    @MainActor
    private func applyClaudeResult(_ r: ClaudeService.CoRExtraction) {
        if let n = r.vesselName { v.name = n }
        if let n = r.officialNumber { v.officialNumber = n }
        if let n = r.callSign { v.callSign = n }
        if let n = r.imoNumber { v.imoNumber = n }
        if let n = r.flagStateCode { v.flagState = n }
        else if let n = r.flagState {
            if let m = Self.flagStates.first(where: { $0.name.lowercased() == n.lowercased() }) { v.flagState = m.code } else { v.flagState = n }
        }
        if let n = r.portOfRegistry { v.portOfRegistry = n }
        if let n = r.certificateNumber { v.certificateNumber = n }
        if let n = r.builder { v.builder = n }
        if let n = r.yearBuilt { v.yearBuilt = n }
        if let n = r.hullMaterial { v.hullMaterial = n }
        if let n = r.vesselDescription { v.vesselDescription = n }
        if let n = r.lengthOverall { v.lengthOverall = n }
        if let n = r.registeredLength { v.registeredLength = n }
        if let n = r.breadth { v.breadth = n }
        if let n = r.depth { v.depth = n }
        if let n = r.draught { v.draught = n }
        if let n = r.grossTonnage { v.grossTonnage = n }
        if let n = r.netTonnage { v.netTonnage = n }
        if let n = r.propulsionType { v.propulsionType = n }
        if let n = r.engineDescription { v.engineDescription = n }
        if let n = r.engineMaker { v.engineMaker = n }
        if let n = r.propulsionPower { v.propulsionPower = n }
        if let n = r.estimatedSpeed { v.estimatedSpeed = n }
        if let n = r.registeredOwner { v.registeredOwner = n }
        if let n = r.ownerAddress { v.ownerAddress = n }
        if let n = r.registrationDate { v.registrationDate = n }
        if let n = r.certificateExpiry { v.certificateExpiry = n }

        if let desc = r.vesselType ?? r.vesselDescription {
            let up = desc.uppercased()
            if up.contains("COMMERCIAL YACHT") { v.vesselType = .megayachtCharter }
            else if up.contains("PLEASURE") || up.contains("YACHT") { v.vesselType = .megayachtPrivate }
            else if up.contains("OIL TANKER") { v.vesselType = .tankerOil }
            else if up.contains("CHEMICAL") { v.vesselType = .tankerChemical }
            else if up.contains("GAS") || up.contains("LNG") { v.vesselType = .tankerGas }
            else if up.contains("PASSENGER") { v.vesselType = .passenger }
            else if up.contains("OFFSHORE") { v.vesselType = .offshore }
            else if up.contains("CARGO") || up.contains("BULK") { v.vesselType = .commercialCargo }
        }
    }

    private var canSave: Bool { !v.name.trimmingCharacters(in: .whitespaces).isEmpty }

    private func advance() {
        withAnimation(.smooth(duration: 0.25)) {
            switch mode {
            case .stepName: mode = .stepType
            case .stepType: mode = .stepDetails
            default: break
            }
        }
    }

    private func goBack() {
        withAnimation(.smooth(duration: 0.25)) {
            switch mode {
            case .choose: dismiss()
            case .stepName: mode = .choose; resetFields()
            case .stepType: mode = .stepName
            case .stepDetails: mode = .stepType
            case .review: mode = .choose; resetFields()
            case .scanning: mode = .choose; resetFields()
            }
        }
    }

    private func resetFields() {
        v = Vessel(name: ""); corImage = nil; nameSuggestions = []
    }

    private func save() {
        v.name = v.name.trimmingCharacters(in: .whitespaces)
        v.flagState = v.flagState.uppercased().trimmingCharacters(in: .whitespaces)
        let created = vm.createVessel(name: v.name, imoNumber: v.imoNumber, flagState: v.flagState, portOfRegistry: v.portOfRegistry, vesselType: v.vesselType)
        // Copy all extended fields
        var full = created
        full.officialNumber = v.officialNumber; full.callSign = v.callSign
        full.certificateNumber = v.certificateNumber
        full.builder = v.builder; full.yearBuilt = v.yearBuilt
        full.hullMaterial = v.hullMaterial; full.vesselDescription = v.vesselDescription
        full.lengthOverall = v.lengthOverall; full.breadth = v.breadth
        full.depth = v.depth; full.draught = v.draught
        full.grossTonnage = v.grossTonnage; full.netTonnage = v.netTonnage
        full.propulsionType = v.propulsionType; full.engineDescription = v.engineDescription
        full.engineMaker = v.engineMaker; full.propulsionPower = v.propulsionPower
        full.estimatedSpeed = v.estimatedSpeed
        full.registeredOwner = v.registeredOwner; full.ownerAddress = v.ownerAddress
        full.registrationDate = v.registrationDate; full.certificateExpiry = v.certificateExpiry
        vm.updateVessel(full)
        if let data = corImage {
            try? data.write(to: vm.imagesDir.appendingPathComponent("\(full.id)_cor.jpg"))
        }
        createdVesselId = full.id
        showPhotoPrompt = true
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(Typo.meta).foregroundStyle(.secondary)
            TextField(prompt, text: text)
                .font(Typo.body)
                .padding(14)
                .background(Color.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - PDF Extraction

    private func extractFromPDF(_ url: URL) async {
        guard url.startAccessingSecurityScopedResource() else {
            await MainActor.run { withAnimation { mode = .stepName } }
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        // Read raw PDF bytes — keep them for Claude
        guard let rawPDF = try? Data(contentsOf: url) else {
            await MainActor.run { withAnimation { mode = .stepName } }
            return
        }
        guard let pdfDoc = PDFDocument(data: rawPDF) else {
            await MainActor.run { withAnimation { mode = .stepName } }
            return
        }

        // Render thumbnail for display
        let thumbnail = renderPDFPage(pdfDoc.page(at: 0))
        await MainActor.run {
            if let t = thumbnail { corImage = t }
            corPDFData = rawPDF
        }

        // 1. Try Claude with RAW PDF (best quality — no rendering loss)
        if await extractWithClaudePDF(rawPDF) { return }

        // 2. Try embedded text (digital PDFs)
        var allText = ""
        for i in 0..<min(pdfDoc.pageCount, 3) {
            if let page = pdfDoc.page(at: i), let text = page.string { allText += text + "\n" }
        }
        if allText.trimmingCharacters(in: .whitespacesAndNewlines).count > 20 {
            await parseExtractedText(allText); return
        }

        // 3. Fall back to Vision OCR
        var combinedText = ""
        for i in 0..<min(pdfDoc.pageCount, 3) {
            guard let page = pdfDoc.page(at: i) else { continue }
            guard let imageData = renderPDFPage(page) else { continue }
            let pageText = await ocrImage(imageData)
            combinedText += pageText + "\n"
        }
        await parseExtractedText(combinedText)
    }

    private func renderPDFPage(_ page: PDFPage?) -> Data? {
        guard let page else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 3.0 // Higher resolution for better OCR/Claude extraction
        let size = CGSize(width: bounds.width * scale, height: bounds.height * scale)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
            ctx.cgContext.translateBy(x: 0, y: size.height)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
        return image.jpegData(compressionQuality: 0.95)
    }

    // MARK: - Photo Extraction

    private func extractFromImage(_ imageData: Data) async {
        // Try Claude first (intelligent extraction), fall back to Vision OCR
        if await extractWithClaude(imageData) { return }
        let text = await ocrImage(imageData)
        await parseExtractedText(text)
    }

    // MARK: - Claude AI Extraction (primary)

    @State private var extractionMethod = ""

    /// Send raw PDF to Claude (best quality — no image conversion)
    private func extractWithClaudePDF(_ pdfData: Data) async -> Bool {
        let key = KeychainService.get(.claudeAPIKey)
        guard let key, !key.isEmpty else { return false }

        #if DEBUG
        corLogger.debug("Sending raw PDF to Claude (\(pdfData.count) bytes)")
        #endif
        await MainActor.run { extractionMethod = "Reading certificate..." }

        do {
            let result = try await ClaudeService.shared.extractCoR(pdfData: pdfData)
            await MainActor.run {
                applyClaudeResult(result)
                extractionMethod = "Claude AI"
                nameSuggestions = []
                withAnimation { mode = .review }
            }
            return true
        } catch {
            corLogger.error("Claude PDF extraction failed: \(error.localizedDescription)")
            await MainActor.run { extractionMethod = "Claude failed: \(error.localizedDescription.prefix(40))" }
            return false
        }
    }

    private func extractWithClaude(_ imageData: Data) async -> Bool {
        let key = KeychainService.get(.claudeAPIKey)
        guard let key, !key.isEmpty else {
            #if DEBUG
            corLogger.debug("No Claude API key, falling back to Vision OCR")
            #endif
            await MainActor.run { extractionMethod = "Vision OCR (no Claude key)" }
            return false
        }

        #if DEBUG
        corLogger.debug("Claude API key found, calling Claude...")
        #endif
        await MainActor.run { extractionMethod = "Calling Claude..." }

        do {
            let result = try await ClaudeService.shared.extractCoR(imageData: imageData)
            await MainActor.run {
                applyClaudeResult(result)
                extractionMethod = "Claude AI"; nameSuggestions = []
                withAnimation { mode = .review }
            }
            return true
        } catch {
            corLogger.error("Claude image extraction failed: \(error.localizedDescription)")
            await MainActor.run { extractionMethod = "OCR (\(error.localizedDescription.prefix(40)))" }
            return false
        }
    }

    // MARK: - OCR (on-device Vision with column-aware layout reconstruction)

    struct OCRBlock {
        let text: String
        let x: CGFloat      // normalized 0-1, left edge
        let y: CGFloat      // normalized 0-1, top edge (0 = top)
        let width: CGFloat
        let height: CGFloat
        let centerX: CGFloat
    }

    private func ocrImage(_ imageData: Data) async -> String {
        guard let uiImage = UIImage(data: imageData), let cgImage = uiImage.cgImage else { return "" }
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        guard let results = request.results, !results.isEmpty else { return "" }

        // Collect all text blocks with spatial positions
        var blocks: [OCRBlock] = []
        for obs in results {
            guard let top = obs.topCandidates(1).first else { continue }
            let box = obs.boundingBox
            let y = 1 - box.origin.y - box.height
            blocks.append(OCRBlock(
                text: top.string, x: box.origin.x, y: y,
                width: box.width, height: box.height,
                centerX: box.origin.x + box.width / 2
            ))
        }

        #if DEBUG
        corLogger.debug("OCR total blocks: \(blocks.count)")
        #endif

        // ── COLUMN DETECTION ──
        // Group blocks into columns by their X center position.
        // Maltese CoR typically has 3-4 columns in the header table.
        // Two blocks are in the same column if their center X positions are within 15% of page width.
        let columnThreshold: CGFloat = 0.15
        var columns: [[OCRBlock]] = []

        let sortedByX = blocks.sorted { $0.centerX < $1.centerX }
        for block in sortedByX {
            var placed = false
            for ci in columns.indices {
                let colAvgX = columns[ci].map(\.centerX).reduce(0, +) / CGFloat(columns[ci].count)
                if abs(block.centerX - colAvgX) < columnThreshold {
                    columns[ci].append(block)
                    placed = true; break
                }
            }
            if !placed { columns.append([block]) }
        }

        // Sort each column top-to-bottom
        for ci in columns.indices { columns[ci].sort { $0.y < $1.y } }
        // Sort columns left-to-right
        columns.sort { ($0.first?.x ?? 0) < ($1.first?.x ?? 0) }

        #if DEBUG
        corLogger.debug("OCR detected \(columns.count) columns")
        #endif

        // ── FIND VESSEL NAME via column structure ──
        // Look for "Name of Ship" in any column, then the value below it in the SAME column
        var spatialName = ""
        for col in columns {
            for (bi, block) in col.enumerated() {
                let up = block.text.uppercased()
                if up.contains("NAME OF SHIP") || up.contains("VESSEL NAME") || up == "NAME OF SHIP" {
                    // The next block(s) in THIS COLUMN are the vessel name
                    for j in (bi+1)..<min(bi+4, col.count) {
                        let candidate = col[j].text.trimmingCharacters(in: .whitespaces)
                        if candidate.count >= 2 && !Self.isNotName(candidate) {
                            spatialName = candidate
                            #if DEBUG
                            corLogger.debug("Column-aware name: '\(candidate)'")
                            #endif
                            break
                        }
                    }
                    if !spatialName.isEmpty { break }
                }
            }
            if !spatialName.isEmpty { break }
        }

        // ── Build text output ──
        // Read column by column (not left-to-right across rows)
        // This preserves label→value relationships within each column
        var columnText = columns.flatMap { col in col.map(\.text) }.joined(separator: "\n")

        // Inject the spatial name at the top if found
        if !spatialName.isEmpty {
            columnText = "Name of Ship\n\(spatialName)\n" + columnText
            #if DEBUG
            corLogger.debug("Injected column-detected name: '\(spatialName)'")
            #endif
        }

        return columnText
    }

    // MARK: - Text Parsing (shared by PDF text extraction and OCR)

    // Words/phrases that are NEVER vessel names
    private static let notNameWords: Set<String> = [
        // Propulsion & engines
        "MOTOR SHIP", "MOTOR VESSEL", "SAILING VESSEL", "TWIN SCREW", "SINGLE SCREW",
        "MOTOR", "DIESEL", "STEAM", "TURBINE", "PROPULSION",
        "INTERNAL COMBUSTION", "COMBUSTION DIESEL", "COMBUSTION",
        // Engine counts
        "ONE", "TWO", "THREE", "FOUR", "FIVE", "SIX",
        "IWO", "IWIN", // common OCR misreads of "TWO" and "TWIN"
        // Vessel types (descriptions, not names)
        "PLEASURE YACHT", "COMMERCIAL YACHT", "PLEASURE CRAFT",
        "MOTOR YACHT", "SAILING YACHT",
        // Structure & materials
        "GRP", "STEEL", "ALUMINIUM", "ALUMINUM", "WOOD", "FIBERGLASS",
        // Dimensions
        "METRES", "METERS", "LENGTH", "BREADTH", "DEPTH", "DRAUGHT", "MOULDED",
        // Labels & headers
        "CERTIFICATE", "REGISTRY", "REGISTRATION", "OFFICIAL", "NUMBER",
        "PORT", "GROSS", "TONNAGE", "FLAG", "IMO", "ISSUED", "DATE",
        "INTERNATIONAL", "DOCUMENT", "REPUBLIC", "GOVERNMENT", "AUTHORITY",
        "MERCHANT", "SHIPPING", "ARTICLE", "FORM", "CERTIFICATE NO",
        "FRAMEWORK", "DESCRIPTION", "PARTICULARS", "ENGINE",
        "CALL SIGN", "WHEN AND WHERE BUILT", "ACCOMMODATION",
        "REGISTRAR", "MALTESE SHIPS", "UNDERSIGNED", "HEREBY CERTIFY",
        "SURVEYED", "RENEWAL", "RENEWING", "PROVISIONALLY",
        "NAME OF SHIP", "VESSEL NAME", "SHIP'S NAME",
        // Ownership
        "SOLE OWNER", "JOINT OWNER", "OWNER", "RESIDENT AGENT",
        // Units & values
        "KNOTS", "KW", "COMBINED", "ESTIMATED", "SPEED",
        // Countries (these are flag states, not vessel names)
        "MALTA", "VALLETTA", "ITALY", "GERMANY", "FRANCE", "SWEDEN",
        "UNITED KINGDOM", "SINGAPORE", "PANAMA", "LIBERIA",
    ]

    private func parseExtractedText(_ fullText: String) async {
        let lines = fullText.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        let upper = fullText.uppercased()

        #if DEBUG
        corLogger.debug("OCR lines: \(lines.count)")
        #endif

        var extractedName = ""
        var extractedIMO = ""
        var extractedFlag = ""
        var extractedPort = ""
        var guessedType: VesselType?

        // ── VESSEL NAME ──
        // Approach: collect ALL candidates, score them, pick the best one.
        // This handles multi-column OCR where label and value aren't adjacent.

        var nameCandidates: [(text: String, score: Int)] = []
        var nameOfShipIndex: Int? = nil

        for (i, line) in lines.enumerated() {
            let up = line.uppercased()

            // Track where "Name of Ship" label appears
            if up.contains("NAME OF SHIP") || up.contains("VESSEL NAME") || up.contains("NAME OF VESSEL") || up.contains("SHIP'S NAME") {
                nameOfShipIndex = i
                // Check for inline value after colon
                if let colonRange = line.range(of: ":") {
                    let after = line[colonRange.upperBound...].trimmingCharacters(in: .whitespaces)
                    if after.count > 2 && !Self.isNotName(after) {
                        nameCandidates.append((after, 100))
                    }
                }
                continue
            }

            // Skip if it's a known non-name
            if Self.isNotName(line) { continue }
            let t = line.trimmingCharacters(in: .whitespaces)
            // Skip numbers, very short, or very long
            if t.count < 3 || t.count > 35 { continue }
            if t.allSatisfy(\.isNumber) { continue }
            if t.range(of: #"^\d"#, options: .regularExpression) != nil { continue }
            // Skip lines with too many words (addresses, descriptions)
            if t.split(separator: " ").count > 4 { continue }

            var score = 0

            // High confidence: near "Name of Ship" label
            if let nsi = nameOfShipIndex, abs(i - nsi) <= 3 { score += 50 }
            // High confidence: has vessel prefix
            let prefixes = ["MV ", "MY ", "MT ", "SY ", "M/V ", "M/Y ", "M/T ", "S/Y ", "SS "]
            if prefixes.contains(where: { up.hasPrefix($0) }) { score += 60 }
            // Medium: single word, ALL CAPS, letters only (typical vessel name)
            let words = t.split(separator: " ")
            if words.count == 1 && t == t.uppercased() && t.allSatisfy(\.isLetter) && t.count >= 4 { score += 30 }
            else if words.count <= 2 && t == t.uppercased() && t.first?.isLetter == true { score += 15 }
            // Penalty: contains numbers mixed with letters (references, IDs, passport numbers)
            if t.contains(where: \.isNumber) && t.contains(where: \.isLetter) { score -= 40 }
            // Penalty: contains punctuation (addresses, references)
            if t.contains(":") || t.contains(".") || t.contains(",") { score -= 30 }
            // Penalty: more than 2 words (likely an address or description)
            if words.count > 2 { score -= 20 }
            // Penalty: looks like a person's name (3+ capitalized words)
            if words.count >= 2 && words.allSatisfy({ $0.first?.isUppercase == true && $0.count > 1 }) { score -= 10 }

            if score > 0 { nameCandidates.append((t, score)) }
        }

        // Pick the highest-scoring candidate, but only if confident enough
        nameCandidates.sort { $0.score > $1.score }
        if let best = nameCandidates.first, best.score >= 25 {
            extractedName = best.text
            #if DEBUG
            corLogger.debug("Name: '\(best.text)' (score \(best.score))")
            #endif
        } else {
            #if DEBUG
            corLogger.debug("Name: low confidence, leaving empty")
            #endif
        }

        // ── IMO NUMBER ──
        // Strategy 1: Explicit "IMO" label with 7-digit number
        if let range = upper.range(of: #"IMO[\s.:#No]*(\d{7})"#, options: .regularExpression) {
            let digits = String(upper[range]).filter(\.isNumber)
            if digits.count >= 7 { extractedIMO = String(digits.prefix(7)) }
        }
        // Strategy 2: "Official No." followed by a number on same or next line
        if extractedIMO.isEmpty {
            for (i, line) in lines.enumerated() {
                let up = line.uppercased()
                if up.contains("OFFICIAL NO") || up.contains("OFFICIAL NUMBER") {
                    // Same line: "Official No. 18634" or "18634"
                    let sameLineNums = line.filter(\.isNumber)
                    if sameLineNums.count >= 4 && sameLineNums.count <= 7 {
                        extractedIMO = sameLineNums; break
                    }
                    // Next lines
                    for j in (i+1)..<min(i+3, lines.count) {
                        let nums = lines[j].filter(\.isNumber)
                        if nums.count >= 4 && nums.count <= 7 {
                            extractedIMO = nums; break
                        }
                    }
                    if !extractedIMO.isEmpty { break }
                }
            }
        }
        // Strategy 3: Standalone 5-7 digit number early in the document (often Official No. without label)
        if extractedIMO.isEmpty {
            for line in lines.prefix(15) {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.count >= 4 && t.count <= 7 && t.allSatisfy(\.isNumber) {
                    extractedIMO = t; break
                }
            }
        }

        // ── FLAG STATE ──
        // Strategy 1: "CERTIFICATE OF [COUNTRY] REGISTRY"
        if let range = upper.range(of: #"CERTIFICATE OF (\w[\w\s]+?) REGISTRY"#, options: .regularExpression) {
            let match = String(upper[range])
                .replacingOccurrences(of: "CERTIFICATE OF ", with: "")
                .replacingOccurrences(of: " REGISTRY", with: "")
                .trimmingCharacters(in: .whitespaces)
            // Look up in flag states
            for fs in Self.flagStates {
                if fs.name.uppercased() == match || fs.name.uppercased().contains(match) { extractedFlag = fs.code; break }
            }
        }
        // Strategy 2: Match country names anywhere
        if extractedFlag.isEmpty {
            for fs in Self.flagStates {
                if upper.contains(fs.name.uppercased()) { extractedFlag = fs.code; break }
            }
        }
        // Strategy 3: Alternate names
        if extractedFlag.isEmpty {
            let alternates: [(String, String)] = [
                ("GREAT BRITAIN", "GBR"), ("ENGLAND", "GBR"), ("BRITISH", "GBR"),
                ("ANTIGUA", "ATG"), ("ST VINCENT", "VCT"), ("SAINT VINCENT", "VCT"),
                ("KOREA", "KOR"), ("REPUBLIC OF KOREA", "KOR"),
                ("PEOPLE'S REPUBLIC OF CHINA", "CHN"), ("PRC", "CHN"),
                ("UNITED ARAB EMIRATES", "ARE"), ("EMIRATES", "ARE"),
                ("DUTCH", "NLD"), ("HOLLAND", "NLD"),
            ]
            for (p, c) in alternates { if upper.contains(p) { extractedFlag = c; break } }
        }

        // ── PORT OF REGISTRY ──
        // Strategy 1: Labeled "Port of Registry" / "Home Port"
        for line in lines {
            let up = line.uppercased()
            if up.contains("PORT OF REGISTRY") || up.contains("PORT OF REGISTRATION") || up.contains("HOME PORT") {
                if let colonRange = line.range(of: ":") {
                    let after = line[colonRange.upperBound...].trimmingCharacters(in: .whitespaces)
                    if !after.isEmpty { extractedPort = after; break }
                }
            }
        }
        // Strategy 2: Maltese format — port appears after "NNN IN YYYY" line (e.g. "658 IN 2018" then "VALLETTA")
        if extractedPort.isEmpty {
            for (i, line) in lines.enumerated() {
                let up = line.uppercased()
                // Match "NNN IN YYYY" pattern (Maltese registration number format)
                if up.range(of: #"\d+ IN \d{4}"#, options: .regularExpression) != nil {
                    // Next line is the port
                    if i + 1 < lines.count {
                        let nextLine = lines[i + 1].trimmingCharacters(in: .whitespaces)
                        if nextLine.count > 2 && nextLine.count < 30 && !nextLine.contains("When") && !nextLine.contains("Framework") {
                            extractedPort = nextLine; break
                        }
                    }
                }
                // Direct match for known Maltese ports
                if ["VALLETTA", "MARSAMXETT", "MARSAXLOKK", "BIRGU", "SENGLEA", "COSPICUA"].contains(up) {
                    extractedPort = line; break
                }
            }
        }
        // Strategy 3: Use default port for detected flag
        if extractedPort.isEmpty, let flagData = selectedFlag ?? Self.flagStates.first(where: { $0.code == extractedFlag }) {
            extractedPort = flagData.port
        }

        // ── VESSEL TYPE ──
        // Scan individual lines for vessel description keywords (more reliable than full-text search)
        for line in lines {
            let up = line.uppercased()
            if up.contains("PLEASURE YACHT") || up.contains("PLEASURE CRAFT") { guessedType = .megayachtPrivate; break }
            if up.contains("COMMERCIAL YACHT") { guessedType = .megayachtCharter; break }
        }
        // Fallback: full-text search
        if guessedType == nil && upper.contains("COMMERCIAL YACHT") { guessedType = .megayachtCharter }
        else if upper.contains("YACHT") && (upper.contains("CHARTER") || upper.contains("COMMERCIAL")) { guessedType = .megayachtCharter }
        else if upper.contains("YACHT") || upper.contains("PLEASURE") || upper.contains("PLEASURE CRAFT") { guessedType = .megayachtPrivate }
        else if upper.contains("OIL TANKER") || upper.contains("CRUDE OIL") { guessedType = .tankerOil }
        else if upper.contains("CHEMICAL TANKER") || upper.contains("CHEMICAL CARRIER") { guessedType = .tankerChemical }
        else if upper.contains("GAS CARRIER") || upper.contains("LNG") || upper.contains("LPG") { guessedType = .tankerGas }
        else if upper.contains("PASSENGER") || upper.contains("CRUISE") || upper.contains("RO-PAX") { guessedType = .passenger }
        else if upper.contains("OFFSHORE") || upper.contains("SUPPLY VESSEL") || upper.contains("PLATFORM") || upper.contains("AHTS") { guessedType = .offshore }
        else if upper.contains("CARGO") || upper.contains("BULK") || upper.contains("CONTAINER") || upper.contains("GENERAL CARGO") || upper.contains("RO-RO") { guessedType = .commercialCargo }

        // ── FALLBACK NAME ──
        if extractedName.isEmpty {
            let skip = ["CERTIFICATE", "REGISTRY", "REGISTRATION", "OFFICIAL", "NUMBER",
                        "PORT", "GROSS", "TONNAGE", "FLAG", "IMO", "ISSUED", "DATE",
                        "INTERNATIONAL", "DOCUMENT", "REPUBLIC", "GOVERNMENT", "AUTHORITY",
                        "MERCHANT", "SHIPPING", "ARTICLE", "FORM NO", "CERTIFICATE NO",
                        "FRAMEWORK", "DESCRIPTION", "PARTICULARS", "PROPULSION", "ENGINE"]
            for line in lines {
                let t = line.trimmingCharacters(in: .whitespaces)
                let up = t.uppercased()
                if t.count > 2 && t.count < 40 && !skip.contains(where: { up.contains($0) }) && !t.allSatisfy(\.isNumber) {
                    extractedName = t; break
                }
            }
        }

        // ── EXTENDED FIELDS ──
        var callSign = "", certNo = "", builder = "", yearBuilt = ""
        var hullMaterial = "", grossTonnage = "", netTonnage = ""
        var engineMaker = "", propPower = "", speed = ""
        var owner = "", regDate = "", certExpiry = ""

        for (i, line) in lines.enumerated() {
            let up = line.uppercased(); let t = line.trimmingCharacters(in: .whitespaces)

            // Call Sign
            if up.contains("CALL SIGN") && callSign.isEmpty {
                for j in (i+1)..<min(i+3, lines.count) {
                    let c = lines[j].trimmingCharacters(in: .whitespaces)
                    if c.count >= 4 && c.count <= 10 && c.allSatisfy({ $0.isLetter || $0.isNumber }) { callSign = c; break }
                }
            }
            // Certificate number
            if up.contains("CERTIFICATE NO") && certNo.isEmpty {
                let nums = t.filter(\.isNumber)
                if nums.count >= 4 { certNo = nums }
            }
            // Gross tonnage
            if up.contains("GROSS") && up.contains("TONNAGE") && grossTonnage.isEmpty {
                for j in i..<min(i+3, lines.count) {
                    if let m = lines[j].range(of: #"\d+[\.,]?\d*"#, options: .regularExpression) {
                        grossTonnage = String(lines[j][m]); break
                    }
                }
            }
            // Net tonnage
            if up.contains("NET") && up.contains("TONNAGE") && netTonnage.isEmpty {
                for j in i..<min(i+3, lines.count) {
                    if let m = lines[j].range(of: #"\d+[\.,]?\d*"#, options: .regularExpression) {
                        netTonnage = String(lines[j][m]); break
                    }
                }
            }
            // Engine maker
            if up.contains("ENGINE MAKERS") || up.contains("ENGINE MAKER") { if i+1 < lines.count { engineMaker = lines[i+1] } }
            // Propulsion power
            if up.contains("KW") { if let m = t.range(of: #"\d+"#, options: .regularExpression) { propPower = "KW \(String(t[m]))" } }
            // Speed
            if up.contains("KNOTS") { if let m = t.range(of: #"\d+"#, options: .regularExpression) { speed = "\(String(t[m])) knots" } }
            // Builder (When and Where Built)
            if up.contains("WHEN AND WHERE BUILT") || up.contains("WHERE BUILT") {
                if i+1 < lines.count { builder = lines[i+1] }
            }
            // Year built (from builder line or standalone 4-digit year in builder context)
            if !builder.isEmpty && yearBuilt.isEmpty {
                if let m = builder.range(of: #"\b(19|20)\d{2}\b"#, options: .regularExpression) { yearBuilt = String(builder[m]) }
            }
            // Hull material
            if ["GRP", "STEEL", "ALUMINIUM", "ALUMINUM", "WOOD", "FIBERGLASS", "COMPOSITE"].contains(up) && hullMaterial.isEmpty { hullMaterial = t }
            // Owner
            if up.contains("OWNERS") && up.contains("FOLLOWS") { // "...Owners and the proportion in which they are interested...are as follows"
                // Next non-label line is the owner
                for j in (i+1)..<min(i+5, lines.count) {
                    let c = lines[j].trimmingCharacters(in: .whitespaces)
                    if c.count > 3 && !c.uppercased().contains("SOLE") && !c.uppercased().contains("JOINT") {
                        owner = c; break
                    }
                }
            }
            // Dates
            if up.contains("REGISTERED ON") || up.contains("REGISTRATION DATE") {
                if let m = t.range(of: #"\d{1,2}\s+\w+\s+\d{4}"#, options: .regularExpression) { regDate = String(t[m]) }
            }
            if up.contains("EXPIRES ON") || up.contains("CERTIFICATE EXPIRES") || up.contains("EXPIRY") {
                if let m = t.range(of: #"\d{1,2}\s+\w+\s+\d{4}"#, options: .regularExpression) { certExpiry = String(t[m]) }
            }
        }

        // Vessel description (the type line: "PLEASURE YACHT", "COMMERCIAL YACHT", etc.)
        var vesselDesc = ""
        let descPatterns = ["PLEASURE YACHT", "COMMERCIAL YACHT", "MOTOR YACHT", "SAILING YACHT",
                           "OIL TANKER", "CHEMICAL TANKER", "GAS CARRIER", "BULK CARRIER",
                           "CONTAINER SHIP", "GENERAL CARGO", "PASSENGER", "OFFSHORE"]
        for line in lines {
            let up = line.uppercased()
            if descPatterns.contains(where: { up.contains($0) }) { vesselDesc = line.trimmingCharacters(in: .whitespaces); break }
        }

        // Collect top name suggestions
        let suggestions = Array(Set(nameCandidates.prefix(8).map(\.text))).prefix(5)
        #if DEBUG
        corLogger.debug("RESULT: name='\(extractedName)', imo='\(extractedIMO)', flag='\(extractedFlag)'")
        #endif

        await MainActor.run {
            if !extractedName.isEmpty { v.name = extractedName }
            if !extractedIMO.isEmpty { v.imoNumber = extractedIMO }
            if !extractedFlag.isEmpty { v.flagState = extractedFlag }
            if !extractedPort.isEmpty { v.portOfRegistry = extractedPort }
            if let vt = guessedType { v.vesselType = vt }
            if !callSign.isEmpty { v.callSign = callSign }
            if !certNo.isEmpty { v.certificateNumber = certNo }
            if !builder.isEmpty { v.builder = builder }
            if !yearBuilt.isEmpty { v.yearBuilt = yearBuilt }
            if !hullMaterial.isEmpty { v.hullMaterial = hullMaterial }
            if !vesselDesc.isEmpty { v.vesselDescription = vesselDesc }
            if !grossTonnage.isEmpty { v.grossTonnage = grossTonnage }
            if !netTonnage.isEmpty { v.netTonnage = netTonnage }
            if !engineMaker.isEmpty { v.engineMaker = engineMaker }
            if !propPower.isEmpty { v.propulsionPower = propPower }
            if !speed.isEmpty { v.estimatedSpeed = speed }
            if !owner.isEmpty { v.registeredOwner = owner }
            if !regDate.isEmpty { v.registrationDate = regDate }
            if !certExpiry.isEmpty { v.certificateExpiry = certExpiry }
            nameSuggestions = Array(suggestions)
            withAnimation { mode = .review }
        }
    }
}

// MARK: - PDF Document Picker

struct PDFDocumentPicker: UIViewControllerRepresentable {
    let onPick: (URL?) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.pdf])
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }

    func updateUIViewController(_ vc: UIDocumentPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) { onPick(urls.first) }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) { onPick(nil) }
    }
}

// MARK: - CoR Example Sheet

struct CoRExampleSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var tab = 0

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    // Tab: Commercial / Private
                    Picker("", selection: $tab) {
                        Text("Commercial").tag(0)
                        Text("Private").tag(1)
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 20).padding(.top, 8)

                    // Example certificate
                    let pdfName = tab == 0 ? "example_cor_malta" : "example_cor_malta_private"
                    let label = tab == 0 ? "MY Zulu 3 — Commercial Yacht, Malta" : "MY Everdeen — Pleasure Yacht, Malta"

                    if let img = renderPDFPage(named: pdfName) {
                        VStack(spacing: 6) {
                            Image(uiImage: img)
                                .resizable().scaledToFit()
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08), lineWidth: 1))
                            Text(label).font(Typo.meta).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 16)
                    }

                    // Field guide
                    VStack(alignment: .leading, spacing: 12) {
                        Text("What OceanCheck extracts").font(Typo.body).fontWeight(.medium)

                        fieldGuide("Vessel Name", "'Name of Ship' field", "doc.text")
                        fieldGuide("Flag State", "From certificate header (e.g. 'Certificate of Malta Registry')", "flag")
                        fieldGuide("Official / IMO No.", "5-7 digit registration number", "number")
                        fieldGuide("Port of Registry", "Home port (e.g. Valletta)", "mappin")
                        fieldGuide("Vessel Type", "'Commercial Yacht', 'Pleasure Yacht', 'Tanker', etc.", "ferry")
                        fieldGuide("Owner", "Registered owner name and address", "building.2")
                    }
                    .padding(.horizontal, 20)

                    // Note
                    VStack(spacing: 6) {
                        Text("All flag state certificates supported")
                            .font(Typo.meta).fontWeight(.medium)
                        Text("OCR runs entirely on-device. No data is sent externally during certificate scanning.")
                            .font(Typo.meta).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                    .padding(.horizontal, 24)

                    Spacer(minLength: 32)
                }
            }
            .background(Color.surface.ignoresSafeArea())
            .navigationTitle("Certificate of Registry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }

    private func renderPDFPage(named: String) -> UIImage? {
        guard let url = Bundle.main.url(forResource: named, withExtension: "pdf"),
              let doc = PDFKit.PDFDocument(url: url),
              let page = doc.page(at: 0) else { return nil }
        let bounds = page.bounds(for: .mediaBox)
        let scale: CGFloat = 2.0
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: bounds.width * scale, height: bounds.height * scale))
        return renderer.image { ctx in
            UIColor.white.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: bounds.width * scale, height: bounds.height * scale)))
            ctx.cgContext.translateBy(x: 0, y: bounds.height * scale)
            ctx.cgContext.scaleBy(x: scale, y: -scale)
            page.draw(with: .mediaBox, to: ctx.cgContext)
        }
    }

    private func fieldGuide(_ title: String, _ description: String, _ icon: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(Typo.body).foregroundStyle(.secondary).frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Typo.body).fontWeight(.medium)
                Text(description).font(Typo.meta).foregroundStyle(.secondary)
            }
        }
    }
}

import PDFKit

// MARK: - Flag State Picker

struct FlagStatePicker: View {
    let flags: [(emoji: String, name: String, code: String, port: String)]
    let selected: String
    let onSelect: ((emoji: String, name: String, code: String, port: String)) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""

    private var filtered: [(emoji: String, name: String, code: String, port: String)] {
        if search.isEmpty { return flags }
        let q = search.lowercased()
        return flags.filter { $0.name.lowercased().contains(q) || $0.code.lowercased().contains(q) }
    }

    // Common maritime flags shown at top
    // Top 12 flags by global fleet tonnage
    private let popularCodes = ["PAN", "MHL", "LBR", "HKG", "SGP", "MLT", "BHS", "CHN", "GRC", "JPN", "CYM", "GBR"]

    var body: some View {
        NavigationStack {
            List {
                // Popular flags
                Section("Popular") {
                    ForEach(flags.filter { popularCodes.contains($0.code) }, id: \.code) { f in
                        flagRow(f)
                    }
                }

                // All flags (filtered)
                Section("All") {
                    ForEach(filtered, id: \.code) { f in
                        flagRow(f)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Flag State")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $search, prompt: "Search countries")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
    }

    private func flagRow(_ f: (emoji: String, name: String, code: String, port: String)) -> some View {
        Button {
            onSelect(f)
        } label: {
            HStack(spacing: 12) {
                Text(f.emoji).font(.system(size: 24))
                VStack(alignment: .leading, spacing: 1) {
                    Text(f.name).font(Typo.body)
                    Text(f.code).font(Typo.meta).foregroundStyle(.secondary)
                }
                Spacer()
                if f.code == selected {
                    Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(Color.clear_)
                }
            }
        }
        .foregroundStyle(.primary)
    }
}
