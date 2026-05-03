// MARK: – MVVM | View
// Handles both sign-in and sign-up with email + password.
// The mode toggle is at the top; confirm-password row shows only when signing up.
// No Firebase calls yet — stubs marked TODO.

import UIKit

final class EmailAuthViewController: UIViewController {

    // MARK: – State

    private enum Mode { case signIn, signUp }
    private var mode: Mode = .signIn { didSet { applyMode() } }

    // MARK: – UI

    private let modeControl: UISegmentedControl = {
        let sc = UISegmentedControl(items: ["Sign In", "Create Account"])
        sc.selectedSegmentIndex = 0
        sc.selectedSegmentTintColor = Theme.accent
        sc.setTitleTextAttributes([.foregroundColor: UIColor.white,
                                   .font: UIFont.systemFont(ofSize: 14, weight: .semibold)], for: .selected)
        sc.setTitleTextAttributes([.foregroundColor: Theme.accent,
                                   .font: UIFont.systemFont(ofSize: 14, weight: .regular)], for: .normal)
        return sc
    }()

    private let emailField: UITextField = {
        let f = makeField(placeholder: "Email address", keyboard: .emailAddress)
        f.textContentType = .emailAddress
        f.autocapitalizationType = .none
        return f
    }()

    private let passwordField: UITextField = {
        let f = makeField(placeholder: "Password", keyboard: .default)
        f.textContentType = .password
        f.isSecureTextEntry = true
        return f
    }()

    private let confirmField: UITextField = {
        let f = makeField(placeholder: "Confirm password", keyboard: .default)
        f.textContentType = .newPassword
        f.isSecureTextEntry = true
        return f
    }()

    private let confirmRow = UIView()   // wrapper — hidden in sign-in mode

    private lazy var actionButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.baseBackgroundColor = Theme.accent
        config.baseForegroundColor = .white
        config.cornerStyle = .medium
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attr in
            var a = attr; a.font = UIFont.systemFont(ofSize: 17, weight: .semibold); return a
        }
        let btn = UIButton(configuration: config)
        btn.addTarget(self, action: #selector(actionTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var forgotButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "Forgot password?"
        config.baseForegroundColor = Theme.accent
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attr in
            var a = attr; a.font = UIFont.systemFont(ofSize: 14); return a
        }
        let btn = UIButton(configuration: config)
        btn.addTarget(self, action: #selector(forgotTapped), for: .touchUpInside)
        return btn
    }()

    private let spinner: UIActivityIndicatorView = {
        let s = UIActivityIndicatorView(style: .medium)
        s.color = .white
        s.hidesWhenStopped = true
        return s
    }()

    // MARK: – Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Email"
        view.backgroundColor = .systemBackground
        navigationController?.setNavigationBarHidden(false, animated: true)

        layout()
        applyMode()
        addKeyboardDismissGesture()

        modeControl.addTarget(self, action: #selector(modeChanged), for: .valueChanged)
        [emailField, passwordField, confirmField].forEach {
            $0.addTarget(self, action: #selector(fieldsChanged), for: .editingChanged)
        }
    }

    // MARK: – Mode

    private func applyMode() {
        let isSignUp = mode == .signUp
        UIView.animate(withDuration: 0.2) {
            self.confirmRow.isHidden = !isSignUp
            self.forgotButton.isHidden = isSignUp
        }
        var config = actionButton.configuration
        config?.title = isSignUp ? "Create Account" : "Sign In"
        actionButton.configuration = config
        updateActionEnabled()
    }

    @objc private func modeChanged() {
        mode = modeControl.selectedSegmentIndex == 0 ? .signIn : .signUp
    }

    // MARK: – Validation

    @objc private func fieldsChanged() { updateActionEnabled() }

    private func updateActionEnabled() {
        let emailOK    = !(emailField.text?.trimmingCharacters(in: .whitespaces).isEmpty ?? true)
        let passwordOK = (passwordField.text?.count ?? 0) >= 6
        let confirmOK  = mode == .signIn || confirmField.text == passwordField.text
        actionButton.isEnabled = emailOK && passwordOK && confirmOK
        actionButton.alpha = actionButton.isEnabled ? 1 : 0.5
    }

    // MARK: – Actions

    @objc private func actionTapped() {
        guard let email = emailField.text, let password = passwordField.text else { return }
        setLoading(true)
        // TODO: call FirebaseAuth sign in / create user
        // Auth.auth().signIn(withEmail: email, password: password) { ... }
        // Auth.auth().createUser(withEmail: email, password: password) { ... }
        print("[\(mode)] email=\(email), password length=\(password.count)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.setLoading(false)
            SceneDelegate.current?.showMainApp()
        }
    }

    @objc private func forgotTapped() {
        // TODO: call Auth.auth().sendPasswordReset(withEmail:)
        let alert = UIAlertController(title: "Reset Password",
                                      message: "Enter your email to receive a reset link.",
                                      preferredStyle: .alert)
        alert.addTextField { tf in
            tf.placeholder = "Email address"
            tf.keyboardType = .emailAddress
            tf.autocapitalizationType = .none
        }
        alert.addAction(UIAlertAction(title: "Send", style: .default) { [weak self] _ in
            guard let email = alert.textFields?.first?.text, !email.isEmpty else { return }
            // TODO: Auth.auth().sendPasswordReset(withEmail: email)
            print("Password reset requested for \(email)")
            self?.present(UIAlertController.simpleAlert(title: "Check your inbox",
                                                        message: "A reset link has been sent to \(email)."),
                          animated: true)
        })
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        present(alert, animated: true)
    }

    // MARK: – Loading state

    private func setLoading(_ loading: Bool) {
        loading ? spinner.startAnimating() : spinner.stopAnimating()
        actionButton.isUserInteractionEnabled = !loading
        var config = actionButton.configuration
        config?.title = loading ? "" : (mode == .signUp ? "Create Account" : "Sign In")
        actionButton.configuration = config
    }

    // MARK: – Layout

    private func layout() {
        // Wrap confirmField inside confirmRow so we can hide the row + its spacing
        confirmRow.translatesAutoresizingMaskIntoConstraints = false
        let confirmLabel = UILabel()
        confirmLabel.text = "Confirm password"
        confirmLabel.font = .systemFont(ofSize: 15)
        confirmLabel.setContentHuggingPriority(.required, for: .horizontal)
        let innerRow = UIStackView(arrangedSubviews: [confirmLabel, confirmField])
        innerRow.axis = .horizontal
        innerRow.spacing = 8
        innerRow.alignment = .center
        innerRow.translatesAutoresizingMaskIntoConstraints = false
        confirmRow.addSubview(innerRow)
        NSLayoutConstraint.activate([
            innerRow.topAnchor.constraint(equalTo: confirmRow.topAnchor),
            innerRow.leadingAnchor.constraint(equalTo: confirmRow.leadingAnchor),
            innerRow.trailingAnchor.constraint(equalTo: confirmRow.trailingAnchor),
            innerRow.bottomAnchor.constraint(equalTo: confirmRow.bottomAnchor),
        ])

        // Fields card
        let divider1 = makeDivider()
        let divider2 = makeDivider()
        let fieldStack = UIStackView(arrangedSubviews: [
            makeRow(label: "Email",    field: emailField),
            divider1,
            makeRow(label: "Password", field: passwordField),
            divider2,
            confirmRow
        ])
        fieldStack.axis = .vertical
        fieldStack.spacing = 10

        let card = UIView()
        Theme.applyCardStyle(to: card)
        fieldStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(fieldStack)
        NSLayoutConstraint.activate([
            fieldStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 14),
            fieldStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            fieldStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            fieldStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -14),
        ])

        // Spinner overlaps actionButton
        spinner.translatesAutoresizingMaskIntoConstraints = false
        actionButton.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: actionButton.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: actionButton.centerYAnchor),
        ])
        actionButton.heightAnchor.constraint(equalToConstant: 52).isActive = true

        let root = UIStackView(arrangedSubviews: [modeControl, card, forgotButton, actionButton])
        root.axis = .vertical
        root.spacing = 20
        root.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }

    // MARK: – Helpers

    private static func makeField(placeholder: String, keyboard: UIKeyboardType) -> UITextField {
        let f = UITextField()
        f.placeholder = placeholder
        f.font = .systemFont(ofSize: 15)
        f.keyboardType = keyboard
        f.clearButtonMode = .whileEditing
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return f
    }

    private func makeRow(label text: String, field: UITextField) -> UIView {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: 15)
        label.setContentHuggingPriority(.required, for: .horizontal)
        let row = UIStackView(arrangedSubviews: [label, field])
        row.axis = .horizontal
        row.spacing = 8
        row.alignment = .center
        return row
    }

    private func makeDivider() -> UIView {
        let v = UIView()
        v.backgroundColor = .separator
        v.heightAnchor.constraint(equalToConstant: 0.5).isActive = true
        return v
    }

    private func addKeyboardDismissGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    @objc private func dismissKeyboard() { view.endEditing(true) }
}
