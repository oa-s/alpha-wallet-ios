// Copyright SIX DAY LLC. All rights reserved.

import UIKit
import BigInt
import AlphaWalletFoundation
import Combine

protocol ConfigureTransactionViewControllerDelegate: AnyObject {
    func didSavedToUseDefaultConfigurationType(_ gasSpeed: GasSpeed, in viewController: ConfigureTransactionViewController)
    func didSaved(customConfiguration: TransactionConfiguration, in viewController: ConfigureTransactionViewController)
}

class ConfigureTransactionViewController: UIViewController {

    private lazy var gasLimitTextField: SlidableTextField = {
        let editGasLimitView = SlidableTextField()
        editGasLimitView.delegate = self
        editGasLimitView.textField.inputAccessoryButtonType = .next

        return editGasLimitView
    }()

    private lazy var nonceTextField: TextField = {
        let textField = TextField.buildTextField()
        textField.delegate = self
        textField.keyboardType = .decimalPad

        return textField
    }()

    private lazy var totalFeeTextField: TextField = {
        let textField = TextField.buildTextField()
        textField.delegate = self
        textField.inputAccessoryButtonType = .none
        textField.keyboardType = .decimalPad

        return textField
    }()

    private lazy var dataTextField: TextField = {
        let textField = TextField.buildTextField()
        textField.delegate = self
        textField.inputAccessoryButtonType = .done
        textField.keyboardType = .decimalPad

        return textField
    }()

    private lazy var gasPriceTextField: SlidableTextField = {
        let editGasPriceView = SlidableTextField()
        editGasPriceView.delegate = self
        editGasPriceView.textField.inputAccessoryButtonType = .next

        return editGasPriceView
    }()
    private var cancellable = Set<AnyCancellable>()
    private var viewModel: ConfigureTransactionViewModel
    private var lastSavedConfiguration: TransactionConfiguration
    weak var delegate: ConfigureTransactionViewControllerDelegate?

    private lazy var containerView: ScrollableStackView = {
        return ScrollableStackView()
    }()
    private var footerContainerView: UIView = {
        let view = UIView()
        view.translatesAutoresizingMaskIntoConstraints = false

        return view
    }()
    private var gasSpeedViews: [GasSpeed: GasSpeedView] = [:]

    private let textFieldInsets: UIEdgeInsets = {
        let bottomInset: CGFloat = ScreenChecker.size(big: 20, medium: 20, small: 16)

        return .init(top: bottomInset, left: 16, bottom: bottomInset, right: 16)
    }()

    init(viewModel: ConfigureTransactionViewModel) {
        self.viewModel = viewModel
        self.lastSavedConfiguration = viewModel.configurationToEdit.configuration

        super.init(nibName: nil, bundle: nil)

        navigationItem.title = viewModel.title
        containerView.configure(viewModel: .init(backgroundColor: Configuration.Color.Semantic.defaultViewBackground))
        navigationItem.leftBarButtonItem = UIBarButtonItem.saveBarButton(self, selector: #selector(saveButtonSelected))

        view.addSubview(containerView)

        NSLayoutConstraint.activate([
            containerView.anchorsIgnoringBottomSafeArea(to: view)
        ])

        handleRecovery()
        generateViews(viewModel: viewModel)
    }

    required init?(coder aDecoder: NSCoder) {
        return nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = Configuration.Color.Semantic.defaultViewBackground
        recalculateTotalFeeForCustomGas()
        bind(viewModel: viewModel)
    }

    private func bind(viewModel: ConfigureTransactionViewModel) {
        viewModel.configurator.gasPrice
            .sink { [weak self] in self?.configure(withEstimatedGasPrice: $0, configurator: viewModel.configurator) }
            .store(in: &cancellable)

        viewModel.configurator.gasLimit
            .sink { [weak self] in self?.configure(withEstimatedGasLimit: $0, configurator: viewModel.configurator) }
            .store(in: &cancellable)

        viewModel.configurator.nonce
            .sink { [weak self] in self?.configure(nonce: $0, configurator: viewModel.configurator) }
            .store(in: &cancellable)
    }

    private func handleRecovery() {
        switch viewModel.recoveryMode {
        case .invalidNonce:
            nonceTextField.status = .error(ConfigureTransactionError.leaveNonceEmpty.localizedDescription)
        case .none:
            break
        }
    }

    func configure(viewModel: ConfigureTransactionViewModel) {
        self.viewModel = viewModel
        recalculateTotalFeeForCustomGas()
        generateViews(viewModel: viewModel)
    }

    func configure(withEstimatedGasLimit value: BigUInt, configurator: TransactionConfigurator) {
        var updatedViewModel = viewModel
        var configuration = makeConfigureSuitableForSaving(from: updatedViewModel.configurationToEdit.configuration)
        guard configuration.gasLimit != value else { return }
        configuration.setEstimated(gasLimit: value)
        updatedViewModel.configurationToEdit = EditedTransactionConfiguration(configuration: configuration, server: configurator.session.server)
        viewModel = updatedViewModel
        recalculateTotalFeeForCustomGas()
        generateViews(viewModel: viewModel)
    }

    func configure(withEstimatedGasPrice value: BigUInt, configurator: TransactionConfigurator) {
        var updatedViewModel = viewModel
        var configuration = makeConfigureSuitableForSaving(from: updatedViewModel.configurationToEdit.configuration)
        guard configuration.gasPrice != value else { return }
        configuration.setEstimated(gasPrice: value)
        updatedViewModel.configurationToEdit = EditedTransactionConfiguration(configuration: configuration, server: configurator.session.server)
        updatedViewModel.configurations = configurator.configurations
        viewModel = updatedViewModel
        recalculateTotalFeeForCustomGas()
        showGasPriceWarning()

        generateViews(viewModel: viewModel)
    }

    func configure(nonce: Int, configurator: TransactionConfigurator) {
        var updatedViewModel = viewModel
        var configuration = makeConfigureSuitableForSaving(from: updatedViewModel.configurationToEdit.configuration)
        guard configuration.nonce != nonce else { return }
        configuration.set(nonce: nonce)
        updatedViewModel.configurationToEdit = EditedTransactionConfiguration(configuration: configuration, server: configurator.session.server)
        updatedViewModel.configurations = configurator.configurations
        viewModel = updatedViewModel
        recalculateTotalFeeForCustomGas()

        generateViews(viewModel: viewModel)
    }

    private func showFooterWarning() {
        let view: UIView
        if let gasPriceWarning = viewModel.gasPriceWarning {
            view = createTableFooterForGasPriceWarning(gasPriceWarning)
        } else {
            view = createTableFooterForGasInformation()
        }

        for each in footerContainerView.subviews {
            each.removeFromSuperview()
        }

        footerContainerView.addSubview(view)
        NSLayoutConstraint.activate(view.anchorsConstraint(to: footerContainerView, margin: 30))
    }

    private func createTableFooterForGasInformation() -> UIView {
        let footer = UIView(frame: .init(x: 0, y: 0, width: 0, height: 100))
        let label = UILabel()
        label.translatesAutoresizingMaskIntoConstraints = false
        label.textAlignment = .center
        label.numberOfLines = 0
        label.font = Fonts.regular(size: 15)
        label.textColor = Configuration.Color.Semantic.defaultSubtitleText
        label.text = R.string.localizable.transactionConfirmationFeeFooterText()

        footer.translatesAutoresizingMaskIntoConstraints = false
        footer.addSubview(label)

        NSLayoutConstraint.activate([
            label.anchorsConstraint(to: footer),
        ])

        return footer
    }

    private func createTableFooterForGasPriceWarning(_ gasPriceWarning: TransactionConfigurator.GasPriceWarning) -> UIView {
        let background = UIView()
        background.translatesAutoresizingMaskIntoConstraints = false
        background.backgroundColor = Configuration.Color.Semantic.configureTransactionBackground
        background.borderColor = Configuration.Color.Semantic.configureTransactionBorder
        background.cornerRadius = 8
        background.borderWidth = 1

        let warningIcon = UIImageView(image: R.image.gasWarning())
        warningIcon.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = UILabel()
        titleLabel.textAlignment = .center
        titleLabel.font = Fonts.semibold(size: 20)
        titleLabel.textColor = Configuration.Color.Semantic.defaultErrorText
        titleLabel.text = gasPriceWarning.longTitle

        let descriptionLabel = UITextView()
        descriptionLabel.backgroundColor = .clear
        descriptionLabel.textColor = Configuration.Color.Semantic.defaultSubtitleText
        descriptionLabel.textAlignment = .center
        descriptionLabel.isEditable = false
        descriptionLabel.isSelectable = true
        descriptionLabel.isUserInteractionEnabled = true
        descriptionLabel.isScrollEnabled = false
        descriptionLabel.dataDetectorTypes = .link
        descriptionLabel.font = Fonts.regular(size: 15)
        descriptionLabel.text = gasPriceWarning.description

        let row0 = [warningIcon, titleLabel].asStackView(axis: .horizontal, spacing: 6)
        let row1 = descriptionLabel

        let stackView = [
            row0,
            row1,
        ].asStackView(axis: .vertical, spacing: 6, alignment: .center)
        stackView.translatesAutoresizingMaskIntoConstraints = false

        background.addSubview(stackView)

        NSLayoutConstraint.activate([
            stackView.anchorsConstraint(to: background, edgeInsets: UIEdgeInsets(top: 16, left: 0, bottom: 16, right: 16)),

            warningIcon.widthAnchor.constraint(equalToConstant: 24),
            warningIcon.widthAnchor.constraint(equalTo: warningIcon.heightAnchor),

            descriptionLabel.widthAnchor.constraint(equalTo: stackView.widthAnchor, constant: -50)
        ])

        return background
    }

    private func recalculateTotalFeeForCustomGas() {
        totalFeeTextField.value = viewModel.gasViewModel.feeText

        if let view = gasSpeedViews[.custom] {
            view.configure(viewModel: viewModel.gasSpeedViewModel(gasSpeed: .custom))
        }

        showGasPriceWarning()
        showGasLimitWarning()
        showGasFeeWarning()
        showFooterWarning()
    }

    private func showGasPriceWarning() {
        if viewModel.gasPriceWarning == nil {
            gasPriceTextField.textField.status = .none
        } else {
            gasPriceTextField.textField.status = .error("")
        }
    }

    private func showGasLimitWarning() {
        if let warning = viewModel.gasLimitWarning {
            gasLimitTextField.textField.status = .error(warning.description)
        } else {
            gasLimitTextField.textField.status = .none
        }
    }

    private func showGasFeeWarning() {
        if let warning = viewModel.gasFeeWarning {
            totalFeeTextField.status = .error(warning.description)
        } else {
            totalFeeTextField.status = .none
        }
    }

    @objc private func saveButtonSelected(_ sender: UIBarButtonItem) {
        guard let delegate = delegate else { return }

        switch viewModel.selectedGasSpeed {
        case .custom:
            var canSave: Bool = true

            if viewModel.configurationToEdit.isGasPriceValid {
                gasPriceTextField.textField.status = .none
            } else {
                canSave = false
                gasPriceTextField.textField.status = .error(ConfigureTransactionError.gasPriceTooLow.localizedDescription)
            }

            if viewModel.configurationToEdit.isGasLimitValid {
                gasLimitTextField.textField.status = .none
            } else {
                canSave = false
                gasLimitTextField.textField.status = .error(ConfigureTransactionError.gasLimitTooHigh.localizedDescription)
            }

            if viewModel.configurationToEdit.isTotalFeeValid {
                totalFeeTextField.status = .none
            } else {
                canSave = false
                totalFeeTextField.status = .error(ConfigureTransactionError.gasFeeTooHigh.localizedDescription)
            }

            if viewModel.configurationToEdit.isNonceValid {
                nonceTextField.status = .none
            } else {
                canSave = false
                nonceTextField.status = .error(ConfigureTransactionError.nonceNotPositiveNumber.localizedDescription)
            }

            if viewModel.gasPriceWarning == nil {
                gasPriceTextField.textField.status = .none
            } else {
                gasPriceTextField.textField.status = .error("")
            }

            guard canSave else {
                generateViews(viewModel: viewModel)
                return
            }

            let configuration = makeConfigureSuitableForSaving(from: viewModel.configurationToEdit.configuration)
            delegate.didSaved(customConfiguration: configuration, in: self)
        case .standard, .slow, .fast, .rapid:
            delegate.didSavedToUseDefaultConfigurationType(viewModel.selectedGasSpeed, in: self)
        }
    }

    private func makeConfigureSuitableForSaving(from configuration: TransactionConfiguration) -> TransactionConfiguration {
        let hasUserAdjustedGasPrice = lastSavedConfiguration.hasUserAdjustedGasPrice || (lastSavedConfiguration.gasPrice != configuration.gasPrice)
        let hasUserAdjustedGasLimit = lastSavedConfiguration.hasUserAdjustedGasLimit || (lastSavedConfiguration.gasLimit != configuration.gasLimit)
        let newConfiguration = TransactionConfiguration(
                gasPrice: configuration.gasPrice,
                gasLimit: configuration.gasLimit,
                data: configuration.data,
                nonce: configuration.nonce,
                hasUserAdjustedGasPrice: hasUserAdjustedGasPrice,
                hasUserAdjustedGasLimit: hasUserAdjustedGasLimit
        )
        lastSavedConfiguration = newConfiguration
        return newConfiguration
    }

    private func moveFocusToNextTextField(afterTextField textField: UIView) {
        if textField == gasPriceTextField {
            gasLimitTextField.becomeFirstResponder()
        } else if textField == gasLimitTextField {
            nonceTextField.becomeFirstResponder()
        } else if textField == nonceTextField {
            dataTextField.becomeFirstResponder()
        }
    }
}

extension ConfigureTransactionViewController: SlidableTextFieldDelegate {
    func shouldReturn(in textField: SlidableTextField) -> Bool {
        return true
    }

    func doneButtonTapped(for textField: SlidableTextField) {
        view.endEditing(true)
    }

    func nextButtonTapped(for textField: SlidableTextField) {
        moveFocusToNextTextField(afterTextField: textField)
    }

    func textField(_ textField: SlidableTextField, textDidChange value: Int) {
        if textField == gasLimitTextField {
            viewModel.configurationToEdit.gasLimitRawValue = value
            viewModel.configurationToEdit.updateMaxGasLimitIfNeeded(value)

            gasLimitTextField.configureSliderRange(viewModel: viewModel.gasLimitSliderViewModel)
        } else if textField == gasPriceTextField {
            viewModel.configurationToEdit.updateMaxGasPriceIfNeeded(value)
            viewModel.configurationToEdit.gasPriceRawValue = value

            gasPriceTextField.configureSliderRange(viewModel: viewModel.gasPriceSliderViewModel)
        }

        recalculateTotalFeeForCustomGas()
    }

    func textField(_ textField: SlidableTextField, valueDidChange value: Int) {
        if textField == gasLimitTextField {
            viewModel.configurationToEdit.gasLimitRawValue = value
        } else if textField == gasPriceTextField {
            viewModel.configurationToEdit.gasPriceRawValue = value
        }

        recalculateTotalFeeForCustomGas()
    }
}

extension ConfigureTransactionViewController {

    func didSelectCell(gasSpeed: GasSpeed) {
        self.viewModel.selectedGasSpeed = gasSpeed

        generateViews(viewModel: self.viewModel)
    }

    private func buildGasSpeedView(gasSpeed: GasSpeed) -> GasSpeedView {
        if let view = gasSpeedViews[gasSpeed] {
            return view
        } else {
            let subview = GasSpeedView()
            subview.isUserInteractionEnabled = true

            UITapGestureRecognizer.init(addToView: subview) { [weak self] in
                self?.didSelectCell(gasSpeed: gasSpeed)
            }
            gasSpeedViews[gasSpeed] = subview

            return subview
        }
    }

    private func generateViews(viewModel: ConfigureTransactionViewModel) {
        var views: [UIView] = []

        for section in viewModel.sections {
            switch section {
            case .configurations:
                for gasSpeed in viewModel.gasSpeedsList {
                    let subview: GasSpeedView = buildGasSpeedView(gasSpeed: gasSpeed)
                    subview.configure(viewModel: viewModel.gasSpeedViewModel(gasSpeed: gasSpeed))

                    views += [subview, UIView.separator()]
                }
            case .custom:
                for each in viewModel.editableConfigurationViews {
                    switch each {
                    case .header(let string):
                        let view: GasSpeedTableViewHeaderView = .init()
                        view.configure(viewModel: .init(title: string))

                        views += [view]
                    case .field(let fieldType):
                        switch fieldType {
                        case .gasPrice:
                            gasPriceTextField.configure(viewModel: viewModel.gasPriceSliderViewModel)

                            views += [gasPriceTextField, UIView.separator()]
                        case .gasLimit:
                            gasLimitTextField.configure(viewModel: viewModel.gasLimitSliderViewModel)

                            views += [gasLimitTextField, UIView.separator()]
                        case .nonce:
                            nonceTextField.configure(viewModel: viewModel.nonceViewModel)
                            nonceTextField.inputAccessoryButtonType = viewModel.isDataInputHidden ? .done : .next

                            views += [nonceTextField.defaultLayout(edgeInsets: textFieldInsets), UIView.separator()]
                        case .totalFee:
                            totalFeeTextField.configure(viewModel: viewModel.totalFeeViewModel)

                            views += [totalFeeTextField.defaultLayout(edgeInsets: textFieldInsets), UIView.separator()]
                        case .transactionData:
                            dataTextField.configure(viewModel: viewModel.dataViewModel)

                            views += [dataTextField.defaultLayout(edgeInsets: textFieldInsets), UIView.separator()]
                        }
                    }
                }
            }
        }

        views += [footerContainerView]
        showFooterWarning()

        containerView.stackView.removeAllArrangedSubviews()
        containerView.stackView.addArrangedSubviews(views)
    }
}

extension ConfigureTransactionViewController: TextFieldDelegate {

    func shouldReturn(in textField: TextField) -> Bool {
        return true
    }

    func doneButtonTapped(for textField: TextField) {
        view.endEditing(true)
    }

    func nextButtonTapped(for textField: TextField) {
        moveFocusToNextTextField(afterTextField: textField)
    }

    func shouldChangeCharacters(inRange range: NSRange, replacementString string: String, for textField: TextField) -> Bool {
        let value = (textField.value as NSString).replacingCharacters(in: range, with: string)

        if textField == dataTextField {
            viewModel.configurationToEdit.dataRawValue = value
        } else if textField == nonceTextField {
            viewModel.configurationToEdit.nonceRawValue = Int(value)
        }

        return true
    }
}
