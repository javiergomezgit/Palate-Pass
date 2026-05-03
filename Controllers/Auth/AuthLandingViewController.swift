// MARK: – MVVM | View
// Entry point for unauthenticated users. Presents the three sign-in methods
// and hands off to the appropriate child controller. No Firebase calls here yet.

import UIKit
import AuthenticationServices

final class AuthLandingViewController: UIViewController {

    // MARK: – UI

    private let iconLabel: UILabel = {
        let l = UILabel()
        l.text = "🍽️"
        l.font = .systemFont(ofSize: 72)
        l.textAlignment = .center
        return l
    }()

    private let titleLabel: UILabel = {
        let l = UILabel()
        l.text = "Palate Pass"
        l.font = .systemFont(ofSize: 36, weight: .bold)
        l.textColor = Theme.accentDeep
        l.textAlignment = .center
        return l
    }()

    private let taglineLabel: UILabel = {
        let l = UILabel()
        l.text = "Your personal food & drink journal"
        l.font = .systemFont(ofSize: 16, weight: .regular)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        return l
    }()

    private lazy var appleButton: ASAuthorizationAppleIDButton = {
        let style: ASAuthorizationAppleIDButton.Style =
            traitCollection.userInterfaceStyle == .dark ? .white : .black
        let btn = ASAuthorizationAppleIDButton(type: .signIn, style: style)
        btn.cornerRadius = 14
        btn.addTarget(self, action: #selector(handleApple), for: .touchUpInside)
        return btn
    }()

    private lazy var phoneButton  = makeMethodButton(title: "Continue with Phone",
                                                     icon: "phone.fill",
                                                     action: #selector(handlePhone))
    private lazy var emailButton  = makeMethodButton(title: "Continue with Email",
                                                     icon: "envelope.fill",
                                                     action: #selector(handleEmail))

    private let orLabel: UILabel = {
        let l = UILabel()
        l.text = "— or —"
        l.font = .systemFont(ofSize: 13)
        l.textColor = .tertiaryLabel
        l.textAlignment = .center
        return l
    }()

    private let termsLabel: UILabel = {
        let l = UILabel()
        l.text = "By continuing you agree to our Terms of Service and Privacy Policy."
        l.font = .systemFont(ofSize: 12)
        l.textColor = .tertiaryLabel
        l.textAlignment = .center
        l.numberOfLines = 0
        return l
    }()

    // MARK: – Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        navigationController?.setNavigationBarHidden(true, animated: false)
        layout()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        // Recreate Apple button when color scheme changes so it uses the right style
        if traitCollection.hasDifferentColorAppearance(comparedTo: previousTraitCollection) {
            appleButton.removeFromSuperview()
            let style: ASAuthorizationAppleIDButton.Style =
                traitCollection.userInterfaceStyle == .dark ? .white : .black
            let newBtn = ASAuthorizationAppleIDButton(type: .signIn, style: style)
            newBtn.cornerRadius = 14
            newBtn.addTarget(self, action: #selector(handleApple), for: .touchUpInside)
            newBtn.translatesAutoresizingMaskIntoConstraints = false
            newBtn.heightAnchor.constraint(equalToConstant: 52).isActive = true
            // Insert at position 0 in the button stack (it's the first child)
            if let stack = phoneButton.superview as? UIStackView {
                stack.insertArrangedSubview(newBtn, at: 0)
            }
        }
    }

    // MARK: – Layout

    private func layout() {
        let brandStack = UIStackView(arrangedSubviews: [iconLabel, titleLabel, taglineLabel])
        brandStack.axis = .vertical
        brandStack.spacing = 8
        brandStack.alignment = .center
        brandStack.setCustomSpacing(16, after: iconLabel)

        [appleButton, phoneButton, emailButton].forEach {
            $0.heightAnchor.constraint(equalToConstant: 52).isActive = true
        }

        let buttonStack = UIStackView(arrangedSubviews: [appleButton, orLabel, phoneButton, emailButton])
        buttonStack.axis = .vertical
        buttonStack.spacing = 12
        buttonStack.setCustomSpacing(16, after: appleButton)
        buttonStack.setCustomSpacing(16, after: orLabel)

        let root = UIStackView(arrangedSubviews: [brandStack, buttonStack, termsLabel])
        root.axis = .vertical
        root.spacing = 48
        root.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(root)
        NSLayoutConstraint.activate([
            root.centerYAnchor.constraint(equalTo: view.centerYAnchor, constant: 20),
            root.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 32),
            root.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -32),
        ])
    }

    // MARK: – Factory

    private func makeMethodButton(title: String, icon: String, action: Selector) -> UIButton {
        var config = UIButton.Configuration.filled()
        config.title = title
        config.image = UIImage(systemName: icon,
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 14, weight: .medium))
        config.imagePadding = 10
        config.baseBackgroundColor = Theme.accentLight
        config.baseForegroundColor = Theme.accent
        config.cornerStyle = .medium
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attr in
            var a = attr; a.font = UIFont.systemFont(ofSize: 16, weight: .semibold); return a
        }
        let btn = UIButton(configuration: config)
        btn.addTarget(self, action: action, for: .touchUpInside)
        return btn
    }

    // MARK: – Actions

    @objc private func handleApple() {
        let provider = ASAuthorizationAppleIDProvider()
        let request  = provider.createRequest()
        request.requestedScopes = [.fullName, .email]

        let controller = ASAuthorizationController(authorizationRequests: [request])
        controller.delegate = self
        controller.presentationContextProvider = self
        controller.performRequests()
    }

    @objc private func handlePhone() {
        navigationController?.pushViewController(PhoneAuthViewController(), animated: true)
    }

    @objc private func handleEmail() {
        navigationController?.pushViewController(EmailAuthViewController(), animated: true)
    }
}

// MARK: – Apple Sign In Delegates

extension AuthLandingViewController: ASAuthorizationControllerDelegate {

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithAuthorization authorization: ASAuthorization) {
        guard authorization.credential is ASAuthorizationAppleIDCredential else { return }
        // TODO: sign in with FirebaseAuth using identityToken from credential
        SceneDelegate.current?.showMainApp()
    }

    func authorizationController(controller: ASAuthorizationController,
                                 didCompleteWithError error: Error) {
        // ASAuthorizationError.canceled means the user dismissed the sheet — no alert needed
        guard (error as? ASAuthorizationError)?.code != .canceled else { return }
        present(UIAlertController.simpleAlert(title: "Sign In Failed", message: error.localizedDescription),
                animated: true)
    }
}

extension AuthLandingViewController: ASAuthorizationControllerPresentationContextProviding {
    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        view.window!
    }
}
