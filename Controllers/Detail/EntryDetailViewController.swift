// MARK: – MVVM | View
// Renders a single entry's details. Reads only from EntryDetailViewModel.

import UIKit
import MapKit

final class EntryDetailViewController: UIViewController, UIScrollViewDelegate {

    // MARK: – MVVM

    private let viewModel: EntryDetailViewModel

    init(viewModel: EntryDetailViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: – Stored coordinate (set in populate, applied in viewDidAppear)

    private var pendingCoordinate: CLLocationCoordinate2D?

    // MARK: – UI

    private let scrollView = UIScrollView()
    private let stack: UIStackView = {
        let sv = UIStackView()
        sv.axis = .vertical
        sv.spacing = 16
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let photoScrollView: UIScrollView = {
        let sv = UIScrollView()
        sv.isPagingEnabled = true
        sv.showsHorizontalScrollIndicator = false
        sv.layer.cornerRadius = 16
        sv.clipsToBounds = true
        sv.translatesAutoresizingMaskIntoConstraints = false
        return sv
    }()

    private let pageControl: UIPageControl = {
        let pc = UIPageControl()
        pc.currentPageIndicatorTintColor = Theme.accent
        pc.pageIndicatorTintColor = Theme.accent.withAlphaComponent(0.3)
        pc.hidesForSinglePage = true
        pc.translatesAutoresizingMaskIntoConstraints = false
        return pc
    }()

    private var photoScrollViewWidth: NSLayoutConstraint?

    private let categoryLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 14, weight: .semibold)
        l.textColor = .white
        l.textAlignment = .center
        l.layer.cornerRadius = 11
        l.clipsToBounds = true
        return l
    }()

    // Place is the primary heading — no item name label
    private let placeLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 26, weight: .bold)
        l.numberOfLines = 0
        return l
    }()

    private let starView: StarRatingView = {
        let sv = StarRatingView()
        sv.isInteractive = false
        return sv
    }()

    private let ratingLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 16, weight: .semibold)
        l.textColor = Theme.accent
        return l
    }()

    private let dateLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13)
        l.textColor = .tertiaryLabel
        return l
    }()

    private let visibilityBadge: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 13, weight: .medium)
        l.layer.cornerRadius = 10
        l.clipsToBounds = true
        l.isUserInteractionEnabled = true
        return l
    }()

    private let commentCard: UIView = {
        let v = UIView()
        v.backgroundColor = UIColor(red: 0.18, green: 0.44, blue: 0.96, alpha: 0.07)
        v.layer.cornerRadius = 14
        v.layer.borderWidth  = 1
        v.layer.borderColor  = UIColor(red: 0.18, green: 0.44, blue: 0.96, alpha: 0.18).cgColor
        return v
    }()

    private let commentLabel: UILabel = {
        let l = UILabel()
        l.font = .systemFont(ofSize: 15)
        l.numberOfLines = 0
        l.textColor = .label
        l.translatesAutoresizingMaskIntoConstraints = false
        return l
    }()

    private lazy var miniMap: MKMapView = {
        let mv = MKMapView()
        mv.layer.cornerRadius = 12
        mv.clipsToBounds = true
        mv.isUserInteractionEnabled = false
        mv.translatesAutoresizingMaskIntoConstraints = false
        return mv
    }()

    private lazy var navigateButton: UIButton = {
        var cfg = UIButton.Configuration.filled()
        cfg.title = "Navigate here"
        cfg.image = UIImage(systemName: "arrow.triangle.turn.up.right.circle.fill")
        cfg.imagePadding = 8
        cfg.baseBackgroundColor = Theme.accent
        cfg.cornerStyle = .large
        let b = UIButton(configuration: cfg)
        b.addTarget(self, action: #selector(navigateTapped), for: .touchUpInside)
        return b
    }()

    // MARK: – Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        title = viewModel.categoryBadge

        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .edit, target: self, action: #selector(editTapped)
        )

        setupScrollView()
        populate()

        viewModel.onEntryUpdated = { [weak self] in
            self?.updateVisibilityBadge()
        }

        // Tap the badge to cycle visibility
        visibilityBadge.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(visibilityBadgeTapped))
        )
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        if let coord = pendingCoordinate {
            // 300 feet ≈ 91 metres
            miniMap.setRegion(
                MKCoordinateRegion(center: coord, latitudinalMeters: 91, longitudinalMeters: 91),
                animated: false
            )
        }
    }

    // MARK: – Actions

    @objc private func editTapped() {
        let addVC = AddEntryViewController(viewModel: viewModel.editViewModel)
        navigationController?.pushViewController(addVC, animated: true)
    }

    @objc private func navigateTapped() {
        guard let coord = viewModel.coordinate else { return }
        MapsNavigator.openDirections(
            to: CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude),
            name: viewModel.placeName
        )
    }

    @objc private func visibilityBadgeTapped() {
        let sheet = UIAlertController(title: "Visibility", message: nil, preferredStyle: .actionSheet)
        for option in Visibility.allCases {
            let action = UIAlertAction(title: option.label, style: .default) { [weak self] _ in
                self?.viewModel.setVisibility(option)
            }
            if option == viewModel.visibility { action.setValue(true, forKey: "checked") }
            sheet.addAction(action)
        }
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        sheet.popoverPresentationController?.sourceView = visibilityBadge
        present(sheet, animated: true)
    }

    // MARK: – Layout

    private func setupScrollView() {
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scrollView)
        scrollView.addSubview(stack)
        NSLayoutConstraint.activate([
            scrollView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor, constant: 16),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor, constant: -16),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor, constant: -32),
            stack.widthAnchor.constraint(equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32)
        ])
    }

    private func populate() {
        // Photo gallery — paging scroll view
        if viewModel.hasImage {
            stack.addArrangedSubview(photoScrollView)
            photoScrollView.heightAnchor.constraint(equalToConstant: 220).isActive = true
            photoScrollView.delegate = self

            let localPhotos  = viewModel.localPhotos
            let remoteURLs   = viewModel.remoteImageURLs
            let count        = max(localPhotos.count, remoteURLs.count)
            pageControl.numberOfPages = count

            // Build image views inside the scroll view after layout
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                let w = self.photoScrollView.bounds.width
                self.photoScrollView.contentSize = CGSize(width: w * CGFloat(count), height: 220)

                for i in 0..<count {
                    let iv = UIImageView(frame: CGRect(x: w * CGFloat(i), y: 0, width: w, height: 220))
                    iv.contentMode = .scaleAspectFill
                    iv.clipsToBounds = true
                    iv.backgroundColor = .secondarySystemBackground
                    self.photoScrollView.addSubview(iv)

                    if i < localPhotos.count {
                        iv.image = localPhotos[i]
                    } else if i < remoteURLs.count {
                        let spinner = UIActivityIndicatorView(style: .medium)
                        spinner.center = CGPoint(x: w / 2, y: 110)
                        iv.addSubview(spinner)
                        spinner.startAnimating()
                        ImageLoader.shared.load(urlString: remoteURLs[i]) { image in
                            spinner.removeFromSuperview()
                            iv.image = image
                        }
                    }
                }
            }

            if count > 1 {
                stack.addArrangedSubview(pageControl)
            }
        }

        // Category badge
        categoryLabel.text = "  \(viewModel.categoryBadge)  "
        categoryLabel.backgroundColor = Theme.categoryColor(viewModel.category)
        let headerRow = UIStackView(arrangedSubviews: [categoryLabel, UIView()])
        headerRow.axis = .horizontal
        stack.addArrangedSubview(headerRow)

        // Place name — primary heading
        placeLabel.text = viewModel.placeName
        stack.addArrangedSubview(placeLabel)

        // Star rating
        starView.rating  = viewModel.rating
        ratingLabel.text = viewModel.formattedRating
        let ratingRow = UIStackView(arrangedSubviews: [starView, ratingLabel, UIView()])
        ratingRow.axis = .horizontal
        ratingRow.spacing = 8
        ratingRow.alignment = .center
        NSLayoutConstraint.activate([
            starView.heightAnchor.constraint(equalToConstant: 26),
            starView.widthAnchor.constraint(equalToConstant: 154)
        ])
        stack.addArrangedSubview(ratingRow)

        // Visibility badge (tappable) + check-in date
        updateVisibilityBadge()
        dateLabel.text = viewModel.formattedDate
        let metaRow = UIStackView(arrangedSubviews: [visibilityBadge, UIView(), dateLabel])
        metaRow.axis = .horizontal
        metaRow.alignment = .center
        stack.addArrangedSubview(metaRow)

        // Comment
        if viewModel.hasComment {
            commentCard.addSubview(commentLabel)
            NSLayoutConstraint.activate([
                commentLabel.topAnchor.constraint(equalTo: commentCard.topAnchor, constant: 12),
                commentLabel.leadingAnchor.constraint(equalTo: commentCard.leadingAnchor, constant: 12),
                commentLabel.trailingAnchor.constraint(equalTo: commentCard.trailingAnchor, constant: -12),
                commentLabel.bottomAnchor.constraint(equalTo: commentCard.bottomAnchor, constant: -12)
            ])
            commentLabel.text = "\"\(viewModel.comment)\""
            stack.addArrangedSubview(commentCard)
        }

        // Mini map
        if let coord = viewModel.coordinate {
            let center = CLLocationCoordinate2D(latitude: coord.latitude, longitude: coord.longitude)
            pendingCoordinate = center
            let pin = MKPointAnnotation()
            pin.coordinate = center
            pin.title = viewModel.placeName
            miniMap.addAnnotation(pin)
            stack.addArrangedSubview(miniMap)
            miniMap.heightAnchor.constraint(equalToConstant: 160).isActive = true

            stack.addArrangedSubview(navigateButton)
            navigateButton.heightAnchor.constraint(equalToConstant: 48).isActive = true
        }
    }

    // MARK: – UIScrollViewDelegate (photo paging)

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        guard scrollView === photoScrollView, photoScrollView.bounds.width > 0 else { return }
        let page = Int((scrollView.contentOffset.x / photoScrollView.bounds.width).rounded())
        pageControl.currentPage = page
    }

    private func updateVisibilityBadge() {
        visibilityBadge.text = "  \(viewModel.visibilityText)  "
        switch viewModel.visibility {
        case .public:
            visibilityBadge.backgroundColor = Theme.accentLight
            visibilityBadge.textColor       = Theme.accent
        case .shared:
            visibilityBadge.backgroundColor = UIColor.systemGreen.withAlphaComponent(0.12)
            visibilityBadge.textColor       = .systemGreen
        case .private:
            visibilityBadge.backgroundColor = UIColor.systemRed.withAlphaComponent(0.12)
            visibilityBadge.textColor       = .systemRed
        }
    }
}
