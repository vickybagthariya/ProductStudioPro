import UIKit

enum EditorUnsavedChangesAlert {
    static func present(
        on viewController: UIViewController,
        title: String = "Unsaved changes",
        message: String,
        onDiscard: @escaping () -> Void,
        onSave: @escaping () -> Void
    ) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "Keep Editing", style: .cancel))
        alert.addAction(UIAlertAction(title: "Discard", style: .destructive) { _ in onDiscard() })
        alert.addAction(UIAlertAction(title: "Save", style: .default) { _ in onSave() })
        viewController.present(alert, animated: true)
    }
}
