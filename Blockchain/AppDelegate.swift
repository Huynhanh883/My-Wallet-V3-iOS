//
//  AppDelegate.swift
//  Blockchain
//
//  Created by Maurice A. on 4/13/18.
//  Copyright © 2018 Blockchain Luxembourg S.A. All rights reserved.
//

import UIKit
import Fabric
import Crashlytics
import Firebase
import PlatformKit
import BitcoinKit
import FirebaseDynamicLinks
import RxSwift

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    // The view used as an intermediary privacy screen when the application state changes to inactive
    fileprivate lazy var visualEffectView: UIVisualEffectView = self.lazyVisualEffectView()

    /// Adds a privacy screen during inactive->activate state transitions
    ///
    /// - Returns: UIVisualEffectView added to keyWindow
    fileprivate func lazyVisualEffectView() -> UIVisualEffectView {
        let view = UIVisualEffectView(effect: UIBlurEffect(style: .light))
        view.translatesAutoresizingMaskIntoConstraints = false
        view.layer.masksToBounds = true
        view.frame = UIScreen.main.bounds
        view.alpha = 0
        return view
    }

    // MARK: - Properties
    // NOTE: Xcode automatically creates the file name for each launch image
    /// The overlay shown when the application resigns active state.
    lazy var privacyScreen: UIImageView? = {
        let launchImages = [
            "320x480": "LaunchImage-700",
            "320x568": "LaunchImage-700-568h",
            "375x667": "LaunchImage-800-667h",
            "375x812": "LaunchImage-1100-Portrait-2436h",
            "414x736": "LaunchImage-800-Portrait-736h"
        ]
        let screenWidth = Int(UIScreen.main.bounds.size.width)
        let screenHeight = Int(UIScreen.main.bounds.size.height)
        let key = String(format: "%dx%d", screenWidth, screenHeight)
        if let launchImage = UIImage(named: launchImages[key]!) {
            let imageView = UIImageView(frame: UIScreen.main.bounds)
            imageView.image = launchImage
            imageView.alpha = 0
            return imageView
        }
        return nil
    }()

    private lazy var deepLinkHandler: DeepLinkHandler = {
        return DeepLinkHandler()
    }()

    /// A service that provides remote notification registration logic,
    /// thus taking responsibility off `AppDelegate` instance.
    private lazy var remoteNotificationRegistrationService: RemoteNotificationRegistering = {
        return RemoteNotificationServiceContainer.default.authorizer
    }()
    
    /// A receipient for device tokens
    private lazy var remoteNotificationTokenReceiver: RemoteNotificationDeviceTokenReceiving = {
        return RemoteNotificationServiceContainer.default.tokenReceiver
    }()
    
    private let disposeBag = DisposeBag()

    // MARK: - Lifecycle Methods

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        FirebaseApp.configure()
        Fabric.with([Crashlytics.self])
        
        // Migrate announcements
        AnnouncementRecorder.migrate()
        
        // Register the application for remote notifications
        remoteNotificationRegistrationService.registerForRemoteNotificationsIfAuthorized()
            .subscribe()
            .disposed(by: disposeBag)
        
        BlockchainSettings.App.shared.appBecameActiveCount += 1
        // MARK: - Global Appearance
        UIApplication.shared.statusBarStyle = .default
        
        //: Navigation Bar
        let navigationBarAppearance = UINavigationBar.appearance()
        navigationBarAppearance.shadowImage = UIImage()
        navigationBarAppearance.isTranslucent = false
        navigationBarAppearance.titleTextAttributes = UINavigationBar.standardTitleTextAttributes
        navigationBarAppearance.barTintColor = .brandPrimary
        navigationBarAppearance.tintColor = .white
    
        #if DEBUG
        let envKey = UserDefaults.Keys.environment.rawValue
        let environment = Environment.production.rawValue
        UserDefaults.standard.set(environment, forKey: envKey)

        BlockchainSettings.App.shared.enableCertificatePinning = true

        let securityReminderKey = UserDefaults.DebugKeys.securityReminderTimer.rawValue
        UserDefaults.standard.removeObject(forKey: securityReminderKey)

        let appReviewPromptKey = UserDefaults.DebugKeys.appReviewPromptCount.rawValue
        UserDefaults.standard.removeObject(forKey: appReviewPromptKey)

        let zeroTickerKey = UserDefaults.DebugKeys.simulateZeroTicker.rawValue
        UserDefaults.standard.set(false, forKey: zeroTickerKey)

        let simulateSurgeKey = UserDefaults.DebugKeys.simulateSurge.rawValue
        UserDefaults.standard.set(false, forKey: simulateSurgeKey)
        
        #endif

        // TODO: prevent any other data tasks from executing until cert is pinned
        CertificatePinner.shared.pinCertificate()
        
        Network.Dependencies.default.communicator.use(eventRecorder: AnalyticsEventRecorder.shared)
        
        checkForNewInstall()

        AppCoordinator.shared.start()
        WalletActionSubscriber.shared.subscribe()

        return true
    }

    func applicationWillResignActive(_ application: UIApplication) {
        Logger.shared.debug("applicationWillResignActive")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            if application.applicationState != .active {
                self.showBlurCurtain()
            }
        }
    }

    func applicationDidEnterBackground(_ application: UIApplication) {
        Logger.shared.debug("applicationDidEnterBackground")

        // Wallet-related background actions

        // TODO: This should be moved into a component that performs actions to the wallet
        // on different lifecycle events (e.g. "WalletAppLifecycleListener")
        let appSettings = BlockchainSettings.App.shared
        let wallet = WalletManager.shared.wallet

        AssetAddressRepository.shared.fetchSwipeToReceiveAddressesIfNeeded()

        NotificationCenter.default.post(name: Constants.NotificationKeys.appEnteredBackground, object: nil)

        wallet.isFetchingTransactions = false
        wallet.isFilteringTransactions = false
        wallet.didReceiveMessageForLastTransaction = false

        WalletManager.shared.closeWebSockets(withCloseCode: .backgroundedApp)

        if wallet.isInitialized() {
            if appSettings.guid != nil && appSettings.sharedKey != nil {
                appSettings.hasEndedFirstSession = true
            }
            WalletManager.shared.close()
        }

        SocketManager.shared.disconnectAll()

        // UI-related background actions
        ModalPresenter.shared.closeAllModals()

        UIApplication.shared.keyWindow?.rootViewController?.dismiss(animated: false)

        AppCoordinator.shared.cleanupOnAppBackgrounded()
        AuthenticationCoordinator.shared.cleanupOnAppBackgrounded()

        showPrivacyScreen()
        
        Network.Dependencies.default.session.reset {
            Logger.shared.debug("URLSession reset completed.")
        }
    }

    func applicationWillEnterForeground(_ application: UIApplication) {
        Logger.shared.debug("applicationWillEnterForeground")
        hidePrivacyScreen()

        BlockchainSettings.App.shared.appBecameActiveCount += 1

        BuySellCoordinator.shared.start()

        if !WalletManager.shared.wallet.isInitialized() {
            if BlockchainSettings.App.shared.guid != nil && BlockchainSettings.App.shared.sharedKey != nil {
                AuthenticationCoordinator.shared.start()
            } else {
                OnboardingCoordinator.shared.start()
            }
        }
    }

    func applicationDidBecomeActive(_ application: UIApplication) {
        hideBlurCurtain()
        Logger.shared.debug("applicationDidBecomeActive")
        hidePrivacyScreen()
        UIApplication.shared.applicationIconBadgeNumber = 0
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {

        let urlString = url.absoluteString

        guard BlockchainSettings.App.shared.isPinSet else {
            if "\(Constants.Schemes.blockchainWallet)loginAuthorized" == urlString {
                AuthenticationCoordinator.shared.startManualPairing()
                return true
            }
            return false
        }

        guard let urlScheme = url.scheme else {
            return true
        }

        if urlScheme == Constants.Schemes.blockchainWallet {
            // Redirect from browser to app - do nothing.
            return true
        }

        if urlScheme == Constants.Schemes.blockchain {
            ModalPresenter.shared.closeModal(withTransition: convertFromCATransitionType(CATransitionType.fade))
            return true
        }

        // Handle "bitcoin://" scheme
        if let bitcoinUrlPayload = BitcoinURLPayload(url: url) {

            ModalPresenter.shared.closeModal(withTransition: convertFromCATransitionType(CATransitionType.fade))

            AuthenticationCoordinator.shared.postAuthenticationRoute = .sendCoins

            AppCoordinator.shared.tabControllerManager.setupBitcoinPaymentFromURLHandler(
                withAmountString: bitcoinUrlPayload.amount,
                address: bitcoinUrlPayload.address
            )

            return true
        }

        return true
    }

    func application(
        _ application: UIApplication,
        continue userActivity: NSUserActivity,
        restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
    ) -> Bool {
        guard let webpageUrl = userActivity.webpageURL else { return false }

        let handled = DynamicLinks.dynamicLinks().handleUniversalLink(webpageUrl) { [weak self] dynamicLink, error in
            guard error == nil else {
                Logger.shared.error("Got error handling universal link: \(error!.localizedDescription)")
                return
            }

            guard let deepLinkUrl = dynamicLink?.url else {
                return
            }

            // Check that the version of the link (if provided) is supported, if not, prompt the user to upgrade
            if let minimumAppVersionStr = dynamicLink?.minimumAppVersion,
                let minimumAppVersion = AppVersion(string: minimumAppVersionStr),
                let appVersionStr = Bundle.applicationVersion,
                let appVersion = AppVersion(string: appVersionStr),
                appVersion < minimumAppVersion {
                self?.showUpdateAppAlert()
                return
            }

            Logger.shared.info("Deeplink: \(deepLinkUrl.absoluteString)")
            self?.deepLinkHandler.handle(deepLink: deepLinkUrl.absoluteString)
        }
        return handled
    }

    // MARK: - State Checks

    func checkForNewInstall() {

        let appSettings = BlockchainSettings.App.shared
        let onboardingSettings = BlockchainSettings.Onboarding.shared

        guard !onboardingSettings.firstRun else {
            Logger.shared.info("This is not the 1st time the user is running the app.")
            return
        }

        onboardingSettings.firstRun = true

        if appSettings.guid != nil && appSettings.sharedKey != nil && !appSettings.isPinSet {
            AlertViewPresenter.shared.alertUserAskingToUseOldKeychain { _ in
                AuthenticationCoordinator.shared.showForgetWalletConfirmAlert()
            }
        }
    }

    // MARK: - Privacy screen

    /// Fades out the privacy overlay and removes it from its superview.
    func hidePrivacyScreen() {
        UIView.animate(withDuration: 0.12, animations: {
            self.privacyScreen?.alpha = 0
        }, completion: { _ in
            self.privacyScreen?.removeFromSuperview()
        })
    }

    func hideBlurCurtain() {
        UIView.animate(withDuration: 0.12, animations: {
            self.visualEffectView.alpha = 0
        }, completion: { _ in
            self.visualEffectView.removeFromSuperview()
        })
    }

    func showBlurCurtain() {
        UIApplication.shared.keyWindow?.addSubview(visualEffectView)
        UIView.animate(withDuration: 0.64) {
            self.visualEffectView.alpha = 1
        }
    }

    func showPrivacyScreen() {
        privacyScreen?.alpha = 1
        UIApplication.shared.keyWindow?.addSubview(privacyScreen!)
    }

    // MARK: - Private

    private func showUpdateAppAlert() {
        let actions = [
            UIAlertAction(title: LocalizationConstants.DeepLink.updateNow, style: .default, handler: { _ in
                UIApplication.shared.openAppStore()
            }),
            UIAlertAction(title: LocalizationConstants.cancel, style: .cancel)
        ]
        AlertViewPresenter.shared.standardNotify(
            message: LocalizationConstants.DeepLink.deepLinkUpdateMessage,
            title: LocalizationConstants.DeepLink.deepLinkUpdateTitle,
            actions: actions
        )
    }
}

// MARK: - Remote Notification Registration

extension AppDelegate {
    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        remoteNotificationTokenReceiver.appDidFailToRegisterForRemoteNotifications(with: error)
    }
    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        remoteNotificationTokenReceiver.appDidRegisterForRemoteNotifications(with: deviceToken)
    }
}

// Helper function inserted by Swift 4.2 migrator.
fileprivate func convertFromCATransitionType(_ input: CATransitionType) -> String {
	return input.rawValue
}
