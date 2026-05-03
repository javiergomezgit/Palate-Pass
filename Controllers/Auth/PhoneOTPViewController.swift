// MARK: – MVVM | View
// Step 2 of phone auth: 6-digit OTP entry.
// Receives the verificationID from PhoneAuthViewController.
// No Firebase calls yet — stub marked TODO.

import UIKit

final class PhoneOTPViewController: UIViewController {

    // MARK: – Init

    private let phoneNumber:    String
    private let verificationID: String

    init(phoneNumber: String, verificationID: String) {
        self.phoneNumber    = phoneNumber
        self.verificationID = verificationID
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: – UI

    private let subtitleLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.numberOfLines = 0
        return l
    }()

    // Six individual digit boxes
    private lazy var digitFields: [UITextField] = (0..<6).map { _ in Self.makeDigitField() }

    private let hiddenField: UITextField = {
        let f = UITextField()
        f.keyboardType = .numberPad
        f.isHidden = true
        return f
    }()

    private lazy var verifyButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Verify"
        config.baseBackgroundColor = Theme.accent
        config.baseForegroundColor = .white
        config.cornerStyle = .medium
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attr in
            var a = attr; a.font = UIFont.systemFont(ofSize: 17, weight: .semibold); return a
        }
        let btn = UIButton(configuration: config)
        btn.isEnabled = false
        btn.alpha = 0.5
        btn.addTarget(self, action: #selector(verifyTapped), for: .touchUpInside)
        return btn
    }()

    private lazy var resendButton: UIButton = {
        var config = UIButton.Configuration.plain()
        config.title = "Resend code"
        config.baseForegroundColor = Theme.accent
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attr in
            var a = attr; a.font = UIFont.systemFont(ofSize: 14); return a
        }
        let btn = UIButton(configuration: config)
        btn.addTarget(self, action: #selector(resendTapped), for: .touchUpInside)
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
        title = "Verify Phone"
        view.backgroundColor = .systemBackground

        subtitleLabel.text = "Enter the 6-digit code sent to\n\(phoneNumber)"

        layout()
        hiddenField.addTarget(self, action: #selector(codeChanged), for: .editingChanged)
        // Tap anywhere on the digit row to open keyboard
        let tap = UITapGestureRecognizer(target: self, action: #selector(focusInput))
        view.addGestureRecognizer(tap)
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        hiddenField.becomeFirstResponder()
    }

    // MARK: – Actions

    @objc private func focusInput() { hiddenField.becomeFirstResponder() }

    @objc private func codeChanged() {
        let digits = (hiddenField.text ?? "").filter { $0.isNumber }.prefix(6)
        let arr = Array(digits)

        for (i, field) in digitFields.enumerated() {
            field.text = i < arr.count ? String(arr[i]) : ""
            field.layer.borderColor = i < arr.count
                ? Theme.accent.cgColor
                : UIColor.systemGray4.cgColor
        }

        let complete = digits.count == 6
        verifyButton.isEnabled = complete
        verifyButton.alpha = complete ? 1 : 0.5
    }

    @objc private func verifyTapped() {
        guard let code = hiddenField.text, code.count == 6 else { return }
        setLoading(true)
        // TODO: let credential = PhoneAuthProvider.provider().credential(withVerificationID: verificationID, verificationCode: code)
        // TODO: Auth.auth().signIn(with: credential) { result, error in ... }
        print("Verifying OTP \(code) with ID \(verificationID)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.setLoading(false)
            SceneDelegate.current?.showMainApp()
        }
    }

    @objc private func resendTapped() {
        hiddenField.text = ""
        codeChanged()
        // TODO: re-call PhoneAuthProvider.provider().verifyPhoneNumber(phoneNumber, uiDelegate: nil)
        print("Resending OTP to \(phoneNumber)")
        present(UIAlertController.simpleAlert(title: "Code Resent",
                                              message: "A new code has been sent to \(phoneNumber)."),
                animated: true)
    }

    // MARK: – Loading

    private func setLoading(_ loading: Bool) {
        loading ? spinner.startAnimating() : spinner.stopAnimating()
        verifyButton.isUserInteractionEnabled = !loading
        var config = verifyButton.configuration
        config?.title = loading ? "" : "Verify"
        verifyButton.configuration = config
    }

    // MARK: – Layout

    private func layout() {
        let digitStack = UIStackView(arrangedSubviews: digitFields)
        digitStack.axis = .horizontal
        digitStack.spacing = 10
        digitStack.distribution = .fillEqually

        spinner.translatesAutoresizingMaskIntoConstraints = false
        verifyButton.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: verifyButton.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: verifyButton.centerYAnchor),
        ])
        verifyButton.heightAnchor.constraint(equalToConstant: 52).isActive = true

        view.addSubview(hiddenField)

        let root = UIStackView(arrangedSubviews: [subtitleLabel, digitStack, verifyButton, resendButton])
        root.axis = .vertical
        root.spacing = 24
        root.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 32),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
            digitStack.heightAnchor.constraint(equalToConstant: 56),
        ])
    }

    // MARK: – Factory

    private static func makeDigitField() -> UITextField {
        let f = UITextField()
        f.textAlignment = .center
        f.font = .systemFont(ofSize: 24, weight: .semibold)
        f.textColor = Theme.accentDeep
        f.isUserInteractionEnabled = false     // keyboard handled by hiddenField
        f.layer.cornerRadius = 10
        f.layer.borderWidth  = 1.5
        f.layer.borderColor  = UIColor.systemGray4.cgColor
        f.backgroundColor    = .secondarySystemBackground
        return f
    }
}
