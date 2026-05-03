// MARK: – MVVM | View
// Step 1 of phone auth: country-code picker + phone number field.
// On continue, pushes to PhoneOTPViewController.
// No Firebase calls yet — stub marked TODO.

import UIKit

final class PhoneAuthViewController: UIViewController {

    // MARK: – Country data (common subset)

    private struct Country {
        let flag: String
        let name: String
        let dialCode: String
    }

    private let countries: [Country] = [
        Country(flag: "🇺🇸", name: "United States", dialCode: "+1"),
        Country(flag: "🇲🇽", name: "Mexico",        dialCode: "+52"),
        Country(flag: "🇬🇧", name: "United Kingdom", dialCode: "+44"),
        Country(flag: "🇨🇦", name: "Canada",         dialCode: "+1"),
        Country(flag: "🇪🇸", name: "Spain",          dialCode: "+34"),
        Country(flag: "🇦🇷", name: "Argentina",      dialCode: "+54"),
        Country(flag: "🇨🇴", name: "Colombia",       dialCode: "+57"),
        Country(flag: "🇨🇱", name: "Chile",          dialCode: "+56"),
        Country(flag: "🇧🇷", name: "Brazil",         dialCode: "+55"),
        Country(flag: "🇩🇪", name: "Germany",        dialCode: "+49"),
        Country(flag: "🇫🇷", name: "France",         dialCode: "+33"),
        Country(flag: "🇮🇹", name: "Italy",          dialCode: "+39"),
        Country(flag: "🇯🇵", name: "Japan",          dialCode: "+81"),
        Country(flag: "🇰🇷", name: "South Korea",    dialCode: "+82"),
        Country(flag: "🇨🇳", name: "China",          dialCode: "+86"),
        Country(flag: "🇮🇳", name: "India",          dialCode: "+91"),
        Country(flag: "🇦🇺", name: "Australia",      dialCode: "+61"),
    ]

    private var selectedCountry: Country { countries[selectedIndex] }
    private var selectedIndex = 0

    // MARK: – UI

    private lazy var countryButton: UIButton = {
        var config = UIButton.Configuration.tinted()
        config.baseBackgroundColor = Theme.accentLight
        config.baseForegroundColor = Theme.accent
        config.cornerStyle = .medium
        config.imagePlacement = .trailing
        config.imagePadding = 6
        config.image = UIImage(systemName: "chevron.down",
                               withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .medium))
        let btn = UIButton(configuration: config)
        btn.setContentHuggingPriority(.required, for: .horizontal)
        btn.addTarget(self, action: #selector(pickCountry), for: .touchUpInside)
        return btn
    }()

    private let phoneField: UITextField = {
        let f = UITextField()
        f.placeholder = "Phone number"
        f.font = .systemFont(ofSize: 17)
        f.keyboardType = .phonePad
        f.textContentType = .telephoneNumber
        f.clearButtonMode = .whileEditing
        f.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return f
    }()

    private lazy var continueButton: UIButton = {
        var config = UIButton.Configuration.filled()
        config.title = "Send Code"
        config.baseBackgroundColor = Theme.accent
        config.baseForegroundColor = .white
        config.cornerStyle = .medium
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { attr in
            var a = attr; a.font = UIFont.systemFont(ofSize: 17, weight: .semibold); return a
        }
        let btn = UIButton(configuration: config)
        btn.isEnabled = false
        btn.alpha = 0.5
        btn.addTarget(self, action: #selector(continueTapped), for: .touchUpInside)
        return btn
    }()

    private let hintLabel: UILabel = {
        let l = UILabel()
        l.text = "We'll send a one-time code to verify your number."
        l.font = .systemFont(ofSize: 13)
        l.textColor = .secondaryLabel
        l.textAlignment = .center
        l.numberOfLines = 0
        return l
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
        title = "Phone"
        view.backgroundColor = .systemBackground
        layout()
        updateCountryButton()
        phoneField.addTarget(self, action: #selector(phoneChanged), for: .editingChanged)
        addKeyboardDismissGesture()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        phoneField.becomeFirstResponder()
    }

    // MARK: – Actions

    @objc private func pickCountry() {
        let alert = UIAlertController(title: "Select Country", message: nil, preferredStyle: .actionSheet)
        for (index, country) in countries.enumerated() {
            alert.addAction(UIAlertAction(title: "\(country.flag)  \(country.name) (\(country.dialCode))",
                                          style: .default) { [weak self] _ in
                self?.selectedIndex = index
                self?.updateCountryButton()
            })
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.popoverPresentationController?.sourceView = countryButton
        present(alert, animated: true)
    }

    @objc private func phoneChanged() {
        let digits = phoneField.text?.filter { $0.isNumber } ?? ""
        continueButton.isEnabled = digits.count >= 7
        continueButton.alpha = continueButton.isEnabled ? 1 : 0.5
    }

    @objc private func continueTapped() {
        guard let number = phoneField.text?.trimmingCharacters(in: .whitespaces), !number.isEmpty else { return }
        let fullNumber = selectedCountry.dialCode + number
        setLoading(true)

        // TODO: call PhoneAuthProvider.provider().verifyPhoneNumber(fullNumber, uiDelegate: nil) { ... }
        print("Sending OTP to \(fullNumber)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.setLoading(false)
            // TODO: pass the real verificationID received from Firebase
            let otp = PhoneOTPViewController(phoneNumber: fullNumber, verificationID: "STUB_ID")
            self?.navigationController?.pushViewController(otp, animated: true)
        }
    }

    // MARK: – Helpers

    private func updateCountryButton() {
        var config = countryButton.configuration
        config?.title = "\(selectedCountry.flag) \(selectedCountry.dialCode)"
        countryButton.configuration = config
    }

    private func setLoading(_ loading: Bool) {
        loading ? spinner.startAnimating() : spinner.stopAnimating()
        continueButton.isUserInteractionEnabled = !loading
        var config = continueButton.configuration
        config?.title = loading ? "" : "Send Code"
        continueButton.configuration = config
    }

    // MARK: – Layout

    private func layout() {
        // Phone input row: [country picker] [phone field]
        let inputRow = UIStackView(arrangedSubviews: [countryButton, phoneField])
        inputRow.axis = .horizontal
        inputRow.spacing = 10
        inputRow.alignment = .center

        let card = UIView()
        Theme.applyCardStyle(to: card)
        inputRow.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(inputRow)
        NSLayoutConstraint.activate([
            inputRow.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            inputRow.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            inputRow.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            inputRow.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])

        spinner.translatesAutoresizingMaskIntoConstraints = false
        continueButton.addSubview(spinner)
        NSLayoutConstraint.activate([
            spinner.centerXAnchor.constraint(equalTo: continueButton.centerXAnchor),
            spinner.centerYAnchor.constraint(equalTo: continueButton.centerYAnchor),
        ])
        continueButton.heightAnchor.constraint(equalToConstant: 52).isActive = true

        let root = UIStackView(arrangedSubviews: [card, hintLabel, continueButton])
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

    private func addKeyboardDismissGesture() {
        let tap = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
        tap.cancelsTouchesInView = false
        view.addGestureRecognizer(tap)
    }

    @objc private func dismissKeyboard() { view.endEditing(true) }
}
