// Copyright © 2018 Stormbird PTE. LTD.

import Foundation
import UIKit

protocol AlphaWalletTokensCoordinatorDelegate: class {
    func didPress(for type: PaymentFlow, in coordinator: AlphaWalletTokensCoordinator)
    func didPressStormBird(for type: PaymentFlow, token: TokenObject, in coordinator: AlphaWalletTokensCoordinator)
    func didPressOrder(for type: PaymentFlow, token: TokenObject, in coordinator: ClaimOrderCoordinator)
}

//Duplicated from TokensCoordinator.swift for easier upstream merging
class AlphaWalletTokensCoordinator: Coordinator {

    let navigationController: UINavigationController
    let session: WalletSession
    let keystore: Keystore
    var coordinators: [Coordinator] = []
    let storage: AlphaWalletTokensDataStore

    lazy var tokensViewController: AlphaWalletTokensViewController = {
        let controller = AlphaWalletTokensViewController(
            account: session.account,
            dataStore: storage
        )
        controller.delegate = self
        return controller
    }()
    weak var delegate: AlphaWalletTokensCoordinatorDelegate?

    lazy var rootViewController: AlphaWalletTokensViewController = {
        return self.tokensViewController
    }()

    init(
        navigationController: UINavigationController = NavigationController(),
        session: WalletSession,
        keystore: Keystore,
        tokensStorage: AlphaWalletTokensDataStore
    ) {
        self.navigationController = navigationController
        self.navigationController.modalPresentationStyle = .formSheet
        self.session = session
        self.keystore = keystore
        self.storage = tokensStorage
    }

    func start() {
        showTokens()
    }

    func showTokens() {
        navigationController.viewControllers = [rootViewController]
    }

    func newTokenViewController() -> NewTokenViewController {
        let controller = NewTokenViewController()
        controller.delegate = self
        return controller
    }

    @objc func addToken() {
        let controller = newTokenViewController()
        controller.navigationItem.leftBarButtonItem = UIBarButtonItem(barButtonSystemItem: .cancel, target: self, action: #selector(dismiss))
        let nav = UINavigationController(rootViewController: controller)
        nav.modalPresentationStyle = .formSheet
        navigationController.present(nav, animated: true, completion: nil)
    }

    @objc func dismiss() {
        navigationController.dismiss(animated: true, completion: nil)
    }

    @objc func edit() {
        //edit tokens disabled
//        let controller = EditTokensViewController(
//            session: session,
//            storage: storage
//        )
//        navigationController.pushViewController(controller, animated: true)
    }
}

extension AlphaWalletTokensCoordinator: AlphaWalletTokensViewControllerDelegate {
    func didSelect(token: TokenObject, in viewController: UIViewController) {

        let type: TokenType = {
            if token.isStormBird {
                return .stormBird
            }
            return AlphaWalletTokensDataStore.etherToken(for: session.config) == token ? .ether : .token
        }()

        switch type {
        case .ether:
            delegate?.didPress(for: .send(type: .ether(destination: .none)), in: self)
        case .token:
            delegate?.didPress(for: .send(type: .token(token)), in: self)
        case .stormBird:
            delegate?.didPressStormBird(for: .send(type: .stormBird(token)), token: token, in: self)
        case .stormBirdOrder:
            delegate?.didPressStormBird(for: .send(type: .stormBirdOrder(token)), token: token, in: self)
        }
    }

    func didDelete(token: TokenObject, in viewController: UIViewController) {
        storage.delete(tokens: [token])
        tokensViewController.fetch()
    }

    func didPressAddToken(in viewController: UIViewController) {
        addToken()
    }
    private func getContractBalance(for address: String,
                                    in viewController: NewTokenViewController) {
        storage.getStormBirdBalance(for: address) { result in
            switch result {
            case .success(let balance):
                viewController.updateBalanceValue(balance)
            case .failure: break
            }
        }
    }

    private func getDecimals(for address: String,
                             in viewController: NewTokenViewController) {
        storage.getDecimals(for: address) { result in
            switch result {
            case .success(let decimal):
                viewController.updateDecimalsValue(decimal)
            case .failure: break
            }
        }
    }

}

extension AlphaWalletTokensCoordinator: NewTokenViewControllerDelegate {
    func didAddToken(token: ERC20Token, in viewController: NewTokenViewController) {
        storage.addCustom(token: token)
        tokensViewController.fetch()
        dismiss()
    }

    // TODO: Clean this up
    func didAddAddress(address: String, in viewController: NewTokenViewController) {
        storage.getContractName(for: address) { result in
            switch result {
            case .success(let name):
                viewController.updateNameValue(name)
            case .failure: break
            }
        }

        storage.getContractSymbol(for: address) { result in
            switch result {
            case .success(let symbol):
                viewController.updateSymbolValue(symbol)
            case .failure: break
            }
        }

        storage.getIsStormBird(for: address) { result in
            switch result {
            case .success(let isStormBird):
                viewController.updateFormForStormBirdToken(isStormBird)
                if isStormBird {
                    self.getContractBalance(for: address, in: viewController)
                } else {
                    self.getDecimals(for: address, in: viewController)
                }
            case .failure:
                self.getDecimals(for: address, in: viewController)
            }
        }
    }
}
