import AppKit
import ManiculeCore
import SwiftUI

/// Settings, hosted in a plain window (an LSUIElement app has no Settings scene). Created once.
@MainActor
final class SettingsWindowController {
    private let model: AppModel
    let window: NSWindow

    init(model: AppModel) {
        self.model = model
        // Sized before the content attaches: SwiftUI's first layout at zero size logs a negative width.
        window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                          styleMask: [.titled, .closable, .miniaturizable, .resizable],
                          backing: .buffered, defer: true)
        let hosting = NSHostingController(rootView: SettingsView(model: model))
        hosting.sizingOptions = [.minSize]
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 760, height: 540))
        window.title = "Manicule Settings"
        window.isReleasedWhenClosed = false
        window.center()
    }

    /// Rediscovers profiles (so newly granted or created ones appear), then brings the window front.
    /// `activate()` is only a request — the system can refuse it for an accessory app opened from
    /// its status menu, leaving an inactive app's window behind the frontmost one — so the window
    /// is also ordered front regardless of activation.
    func show() {
        model.reload()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }
}

struct SettingsView: View {
    let model: AppModel

    var body: some View {
        TabView {
            TargetsTab(model: model).tabItem { Label("Targets", systemImage: "person.2") }
            RulesTab(model: model).tabItem { Label("Rules", systemImage: "arrow.triangle.branch") }
            DocumentsTab(model: model).tabItem { Label("Documents", systemImage: "doc") }
            GeneralTab(model: model).tabItem { Label("General", systemImage: "gearshape") }
        }
        .padding()
        .frame(minWidth: 680, minHeight: 440)
    }
}

/// A line of text centred over an empty list, so the list keeps its place.
private struct EmptyNote: View {
    let text: String
    var body: some View {
        Text(text).foregroundStyle(.secondary).multilineTextAlignment(.center).padding().frame(maxWidth: 420)
    }
}

// MARK: - Targets

struct TargetsTab: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Pinned profiles appear in the picker in this order; the rest are under ⋯. Drag to reorder.")
                .foregroundStyle(.secondary)
            List {
                let sections = model.browserSections
                ForEach(Array(sections.enumerated()), id: \.element) { index, browser in
                    Section {
                        if let root = model.unreadable.first(where: { $0.browser == browser }) {
                            BrowserAccessRow(root: root, model: model)
                        } else if model.config.targets(of: browser).isEmpty {
                            Text("No \(browser.displayName) profiles found").foregroundStyle(.secondary)
                        }
                        ForEach(model.config.targets(of: browser)) { target in
                            row(target)
                        }
                        .onMove { model.config.moveProfiles(of: browser, fromOffsets: $0, toOffset: $1) }
                    } header: {
                        header(browser, before: sections[safe: index - 1], after: sections[safe: index + 1])
                    }
                }
            }
            .overlay {
                if model.browserSections.isEmpty {
                    EmptyNote(text: "No browser profiles found. Grant access to your browsers under General.")
                }
            }
        }
    }

    /// The section's browser, dragged onto another header to take its place; the arrows do the same a step at a time.
    private func header(_ browser: Browser, before: Browser?, after: Browser?) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal").foregroundStyle(.secondary)
            Text(browser.displayName)
            Spacer()
            Button { if let before { model.config.moveBrowser(browser, to: before) } } label: {
                Label("Move \(browser.displayName) Up", systemImage: "chevron.up")
            }
            .help("Move \(browser.displayName) up")
            .disabled(before == nil)
            Button { if let after { model.config.moveBrowser(browser, to: after) } } label: {
                Label("Move \(browser.displayName) Down", systemImage: "chevron.down")
            }
            .help("Move \(browser.displayName) down")
            .disabled(after == nil)
        }
        .labelStyle(.iconOnly)
        .buttonStyle(.borderless)
        .contentShape(Rectangle())
        .help("Drag to reorder browsers")
        .draggable(browser.rawValue)
        .dropDestination(for: String.self) { items, _ in
            guard let moved = items.first.flatMap(Browser.init(rawValue:)) else { return false }
            model.config.moveBrowser(moved, to: browser)
            return true
        }
    }

    private func row(_ target: Target) -> some View {
        HStack(spacing: 10) {
            Toggle("Pinned", isOn: Binding(
                get: { model.config.visible.contains(target.id) },
                set: { model.config.setVisible(target.id, $0) }))
                .toggleStyle(.checkbox)
            Image(nsImage: ProfileIcon.image(for: target))
                .resizable().frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 2) {
                TextField("Name", text: name(target.id))
                Text(Self.detail(target, found: model.available.contains(target.id)))
                    .font(.caption).foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .padding(.vertical, 2)
    }

    private func name(_ id: Target.ID) -> Binding<String> {
        Binding(
            get: { model.target(id)?.name ?? "" },
            set: { name in
                guard let index = model.config.targets.firstIndex(where: { $0.id == id }) else { return }
                model.config.targets[index].name = name
            })
    }

    static func detail(_ target: Target, found: Bool) -> String {
        var parts = [target.email ?? "No account"]
        if let profile = target.profile { parts.append("Folder: \(profile)") }
        if !found { parts.append("Not found on this Mac") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Rules

struct RulesTab: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Rules are checked top to bottom; the first that matches opens the link without the picker. Drag a rule to reorder.")
                .foregroundStyle(.secondary)
            List {
                let choices = Self.choices(model)
                ForEach($model.config.rules) { $rule in
                    RuleRow(rule: $rule, targets: choices, missingName: model.targetName(rule.target)) {
                        model.config.rules.removeAll { $0.id == rule.id }
                    }
                }
                .onMove { model.config.rules.move(fromOffsets: $0, toOffset: $1) }
            }
            .overlay {
                if model.config.rules.isEmpty {
                    EmptyNote(text: "No rules yet. Add one here, or press ⌥⏎ in the picker to always open that site in the chosen target.")
                }
            }
            HStack {
                Button("Add Rule") {
                    guard let first = model.config.targets.first else { return }
                    model.config.rules.append(.new(target: first.id))
                }
                .disabled(model.config.targets.isEmpty)
                if model.config.targets.isEmpty {
                    Text("A rule needs a target; none have been found.").foregroundStyle(.secondary)
                }
            }
        }
    }

    /// "Opens in": every stored target and flotilla's open groups, in picker order.
    static func choices(_ model: AppModel) -> [Target] { model.routerState.targets }
}

struct RuleRow: View {
    @Binding var rule: Rule
    let targets: [Target]
    /// The rule's target's name when `targets` doesn't hold it.
    let missingName: String
    let delete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Toggle("Enabled", isOn: $rule.isEnabled).toggleStyle(.checkbox)
                    .disabled(!rule.isEnabled && !rule.hasCondition)
                TextField("Title", text: $rule.title).font(.headline)
                Button(role: .destructive, action: delete) { Label("Delete Rule", systemImage: "trash") }
            }
            if !rule.hasCondition {
                Text("Fill in a condition to turn this rule on").foregroundStyle(.secondary)
            }
            ForEach(Array(rule.matchers.indices), id: \.self) { index in
                HStack {
                    Picker("Condition", selection: kind(index)) {
                        ForEach(Matcher.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().frame(width: 170)
                    TextField("Value", text: value(index))
                    Button { if rule.matchers.indices.contains(index) { rule.matchers.remove(at: index) } } label: {
                        Label("Remove Condition", systemImage: "minus.circle")
                    }
                }
            }
            HStack {
                Button { rule.matchers.append(.hostSuffix("")) } label: { Label("Add Condition", systemImage: "plus.circle") }
                Spacer()
                Text("From app")
                TextField("Any app (bundle id)", text: sourceApp).frame(width: 220)
                Menu("Running Apps") {
                    Button("Any App") { rule.sourceApp = nil }
                    Divider()
                    ForEach(RunningApp.all(), id: \.bundleID) { app in
                        Button(app.name) { rule.sourceApp = app.bundleID }
                    }
                }
                .fixedSize()
            }
            Picker("Opens in", selection: $rule.target) {
                ForEach(targets) { Text($0.name).tag($0.id) }
                if !targets.contains(where: { $0.id == rule.target }) {
                    Text(missingName).tag(rule.target)
                }
            }
            .frame(maxWidth: 360)
        }
        .padding(.vertical, 6)
    }

    private func kind(_ index: Int) -> Binding<Matcher.Kind> {
        Binding(
            get: { rule.matchers.indices.contains(index) ? rule.matchers[index].kind : .hostSuffix },
            set: { kind in
                guard rule.matchers.indices.contains(index) else { return }
                rule.matchers[index] = Matcher(kind: kind, value: rule.matchers[index].value)
            })
    }

    private func value(_ index: Int) -> Binding<String> {
        Binding(
            get: { rule.matchers.indices.contains(index) ? rule.matchers[index].value : "" },
            set: { value in
                guard rule.matchers.indices.contains(index) else { return }
                rule.matchers[index] = Matcher(kind: rule.matchers[index].kind, value: value)
            })
    }

    private var sourceApp: Binding<String> {
        Binding(
            get: { rule.sourceApp ?? "" },
            set: { rule.sourceApp = $0.trimmingCharacters(in: .whitespaces).isEmpty ? nil : $0 })
    }
}

/// A running app with a bundle id and a Dock presence — the apps links come from.
struct RunningApp {
    let name: String
    let bundleID: String

    @MainActor static func all() -> [RunningApp] {
        var seen = Set<String>()
        return NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .compactMap { app -> RunningApp? in
                guard let id = app.bundleIdentifier, seen.insert(id).inserted else { return nil }
                return RunningApp(name: app.localizedName ?? id, bundleID: id)
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}

// MARK: - Documents

struct DocumentsTab: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Google files you picked a target for open there again without the picker.")
                .foregroundStyle(.secondary)
            List {
                ForEach(model.config.rememberedDocuments.keys.sorted(), id: \.self) { fileID in
                    HStack {
                        Text(fileID).font(.body.monospaced()).textSelection(.enabled).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        let target = model.config.rememberedDocuments[fileID] ?? ""
                        Text(model.targetName(target))
                        Button(role: .destructive) { model.config.rememberedDocuments[fileID] = nil } label: {
                            Label("Forget", systemImage: "trash")
                        }
                    }
                }
            }
            .overlay {
                if model.config.rememberedDocuments.isEmpty {
                    EmptyNote(text: "No remembered documents. Picking a target for a Google Docs, Sheets, Slides or Drive link adds it here.")
                }
            }
            HStack {
                Spacer()
                if model.config.rememberedDocuments.isEmpty {
                    Text("Nothing to clear.").foregroundStyle(.secondary)
                }
                Button("Clear All", role: .destructive) { model.config.rememberedDocuments.removeAll() }
                    .disabled(model.config.rememberedDocuments.isEmpty)
            }
        }
    }
}

// MARK: - General

struct GeneralTab: View {
    let model: AppModel
    @State private var current = DefaultBrowser.current
    @State private var failure: String?
    @State private var importNote: String?
    @State private var loginStatus = LoginItem.status
    @State private var loginFailure: String?

    static func saveProblem(_ refusal: String?) -> String? {
        refusal.map { "Settings can't be saved: \($0)" }
    }

    var body: some View {
        Form {
            if let problem = Self.saveProblem(model.saveRefusal) {
                Section { Text(problem).foregroundStyle(.red).textSelection(.enabled) }
            }
            Section("Import") {
                HStack {
                    Button("Import rules from Velja") { importNote = model.importVeljaRules() }
                        .disabled(!AppModel.veljaInstalled)
                    if !AppModel.veljaInstalled {
                        Text("Velja isn't installed").foregroundStyle(.secondary)
                    } else if let importNote {
                        Text(importNote).foregroundStyle(.secondary)
                    }
                }
            }
            Section("Default browser") {
                LabeledContent("Current default browser", value: DefaultBrowser.name(of: current))
                HStack {
                    Button("Make Manicule the Default Browser") {
                        failure = nil
                        DefaultBrowser.makeManicule { error in
                            failure = error?.localizedDescription
                            current = DefaultBrowser.current
                        }
                    }
                    .disabled(DefaultBrowser.isManicule(current))
                    if DefaultBrowser.isManicule(current) {
                        Text("Manicule is the default browser").foregroundStyle(.secondary)
                    }
                }
                if let failure { Text(failure).foregroundStyle(.red) }
            }
            Section("Startup") {
                Toggle("Open at login", isOn: Binding(
                    get: { LoginItem.isOn(loginStatus) },
                    set: { on in
                        loginFailure = nil
                        do { try LoginItem.set(on) } catch { loginFailure = error.localizedDescription }
                        loginStatus = LoginItem.status
                    }
                ))
                if let note = LoginItem.note(loginStatus) {
                    HStack {
                        Text(note).foregroundStyle(.secondary)
                        if loginStatus == .requiresApproval {
                            Spacer()
                            Button("Open Login Items…") { LoginItem.openSettings() }
                        }
                    }
                }
                if let loginFailure { Text(loginFailure).foregroundStyle(.red) }
            }
            Section("Browser access") {
                if model.unreadable.isEmpty {
                    Text("Manicule can read all your browsers' profiles.")
                } else {
                    ForEach(model.unreadable, id: \.browser) { BrowserAccessRow(root: $0, model: model) }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            current = DefaultBrowser.current
            loginStatus = LoginItem.status
        }
        .onAppear {
            current = DefaultBrowser.current
            loginStatus = LoginItem.status
        }
    }
}

/// A browser whose profiles can't be read yet, with the grant beside it (General and Targets).
struct BrowserAccessRow: View {
    let root: BrowserRoot
    let model: AppModel

    static func label(_ browser: Browser) -> String { "Can't read \(browser.displayName)'s profiles yet" }

    var body: some View {
        HStack {
            Text(Self.label(root.browser))
            Spacer()
            Button("Grant Access…") { BrowserAccess.grant(root, model: model) }
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// macOS lets Manicule read a browser's profile file only after the user picks that exact folder
/// in an open panel (the folder's `com.apple.macl` list); the parent folder doesn't count.
@MainActor
enum BrowserAccess {
    static func panel(for root: BrowserRoot) -> NSOpenPanel {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = root.folder
        panel.message = "Click Open to let Manicule read your \(root.browser.displayName) profiles."
        panel.prompt = "Open"
        return panel
    }

    static func grant(_ root: BrowserRoot, model: AppModel) {
        if panel(for: root).runModal() == .OK { model.reload() }
    }
}
