import FieldKit
import SwiftUI
import UIKit

/// `-FieldSavedHarness YES`: Saved's views on their own, for checking their
/// motion on video before they're wired into the browser. A stand-in new tab
/// (a field on the keyboard, the starred shelf riding above it), a button
/// for Save's sheet, and the shelf's row for the list, all put up the way
/// the browser will (SavedSheets, StarredShelf). Keeps its pages in a folder
/// of its own under tmp, or made up with `-FieldSeedSaved N`; never
/// saved.json. Off in a release build whatever the arguments say.
/// Temporary: goes when the orchestrator wires Saved in.
enum SavedHarness {
    nonisolated static var isOn: Bool {
        #if DEBUG
        let arguments = UserDefaults.standard.volatileDomain(forName: UserDefaults.argumentDomain)
        guard arguments["FieldSavedHarness"] != nil else { return false }
        return UserDefaults.standard.bool(forKey: "FieldSavedHarness")
        #else
        return false
        #endif
    }
}

/// FieldApp's root while the harness is on; nothing in a release build.
struct SavedHarnessView: View {
    var body: some View {
        #if DEBUG
        SavedHarnessScreen()
            .ignoresSafeArea()
            .background { if TouchMarks.isOn { TouchMarksInstaller() } }
        #else
        EmptyView()
        #endif
    }
}

#if DEBUG
/// What the harness shows, which a test can also drive.
final class SavedHarnessStage {
    let store: SavedStore
    var count = 0
    /// The stand-in field, once it's on screen.
    fileprivate weak var field: UITextField?

    init(seed: Int = SavedStore.launchSeed) {
        store = SavedStore(
            directory: FileManager.default.temporaryDirectory.appending(path: "SavedHarness-\(UUID().uuidString)"),
            seed: seed
        )
    }

    /// A page a person might save, in turn, each belonging (or not) to a
    /// folder the suggestion should find.
    func save() {
        let pages = [
            ("https://www.kingarthurbaking.com/recipes/pizza-dough", "Homemade pizza dough"),
            ("https://www.seat61.com/lisbon", "Train from Madrid to Lisbon"),
            ("https://example.com/quarterly", "Quarterly earnings report"),
        ]
        let (address, title) = pages[count % pages.count]
        count += 1
        store.unsave(URL(string: address)!)
        SavedSheets.save(URL(string: address)!, title: title, in: store)
    }

    func showList(_ start: SavedFilter = .all) {
        SavedSheets.showList(store, start: start) { _ in }
    }

    var keyboard: Bool {
        get { field?.isFirstResponder ?? false }
        set { _ = newValue ? field?.becomeFirstResponder() : field?.resignFirstResponder() }
    }

    fileprivate func fill() {
        let pages: [(String, String, String?, Bool)] = [
            ("https://www.seriouseats.com/cookies", "Best chocolate chip cookies", "Recipes", true),
            ("https://www.bonappetit.com/pasta", "Easy weeknight pasta", "Recipes", false),
            ("https://www.bbcgoodfood.com/curry", "Thai green curry", "Recipes", false),
            ("https://www.lonelyplanet.com/lisbon", "Things to do in Lisbon", "Trips", true),
            ("https://www.booking.com/porto", "Hotels in Porto", "Trips", false),
            ("https://swift.org/concurrency", "Swift concurrency explained", "Code", true),
            ("https://developer.apple.com/swiftui", "SwiftUI layout guide", "Code", true),
            ("https://news.ycombinator.com/", "Hacker News", nil, true),
            ("https://github.com/", "GitHub", nil, true),
            ("https://en.wikipedia.org/wiki/Typography", "Typography", nil, false),
        ]
        for (address, title, folder, starred) in pages.reversed() {
            store.save(URL(string: address)!, title: title, folder: folder, starred: starred)
        }
    }
}

/// The stand-in new tab: FieldSurface's layout in miniature. A view whose
/// foot is on the keyboard holds the field and, above it, the shelf.
final class SavedHarnessController: UIViewController, UITextFieldDelegate {
    let stage: SavedHarnessStage
    private let rider = UIView()
    private let field = UITextField()
    private lazy var shelf = StarredShelf(store: stage.store)

    init(stage: SavedHarnessStage = SavedHarnessStage()) {
        self.stage = stage
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Palette.UI.ground

        let save = button("Save a page", id: "harness.save") { [stage] in stage.save() }
        let keys = button("Keyboard", id: "harness.keyboard") { [stage] in stage.keyboard.toggle() }
        [save, keys, rider].forEach {
            $0.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview($0)
        }

        field.placeholder = Bar.placeholder
        field.font = AddressField.font
        field.textColor = Palette.UI.ink
        field.backgroundColor = Palette.UI.raised
        field.layer.cornerRadius = Radius.field
        field.layer.cornerCurve = .continuous
        field.layer.shadowOpacity = 0.1
        field.layer.shadowRadius = 14
        field.layer.shadowOffset = CGSize(width: 0, height: 6)
        field.leftView = UIView(frame: CGRect(x: 0, y: 0, width: 16, height: 1))
        field.leftViewMode = .always
        field.delegate = self
        field.accessibilityIdentifier = "harness.field"
        field.addAction(UIAction { [weak self] _ in self?.showShelf() }, for: [.editingChanged, .editingDidBegin, .editingDidEnd])
        field.translatesAutoresizingMaskIntoConstraints = false
        rider.addSubview(field)
        stage.field = field

        NSLayoutConstraint.activate([
            save.leadingAnchor.constraint(equalTo: view.layoutMarginsGuide.leadingAnchor),
            save.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 8),
            keys.trailingAnchor.constraint(equalTo: view.layoutMarginsGuide.trailingAnchor),
            keys.topAnchor.constraint(equalTo: save.topAnchor),
            rider.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            rider.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            rider.heightAnchor.constraint(equalTo: view.heightAnchor),
            rider.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            field.leadingAnchor.constraint(equalTo: rider.leadingAnchor, constant: FieldSurface.fieldMargin),
            field.trailingAnchor.constraint(equalTo: rider.trailingAnchor, constant: -FieldSurface.fieldMargin),
            field.bottomAnchor.constraint(equalTo: rider.bottomAnchor, constant: -FieldSurface.gap),
            field.heightAnchor.constraint(equalToConstant: Bar.height),
        ])
        shelf.onShowSaved = { [stage] in stage.showList($0) }
        shelf.install(in: self, rider: rider, above: FieldSurface.gap + Bar.height + 12)

        Task {
            await stage.store.load()
            if stage.store.saved.pages.isEmpty { stage.fill() }
            SavedSheets.prepare(stage.store)
        }
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
    }

    /// As on a new tab: while the field is up and nothing's typed.
    private func showShelf() {
        shelf.show(field.isFirstResponder && (field.text ?? "").isEmpty)
    }

    private func button(_ title: String, id: String, action: @escaping () -> Void) -> UIButton {
        var look = UIButton.Configuration.plain()
        look.title = title
        look.baseForegroundColor = Palette.UI.ink
        let button = UIButton(configuration: look, primaryAction: UIAction { _ in action() })
        button.accessibilityIdentifier = id
        return button
    }
}

private struct SavedHarnessScreen: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SavedHarnessController { SavedHarnessController() }
    func updateUIViewController(_ controller: SavedHarnessController, context: Context) {}
}
#endif
