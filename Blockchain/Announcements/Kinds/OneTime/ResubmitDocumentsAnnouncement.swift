//
//  ResubmitDocumentsAnnouncement.swift
//  Blockchain
//
//  Created by Daniel Huri on 19/07/2019.
//  Copyright © 2019 Blockchain Luxembourg S.A. All rights reserved.
//

import PlatformKit
import PlatformUIKit
import RxSwift
import RxCocoa

/// Let the user know that something went wrong during KYC, and that he needs to send his docs once more
final class ResubmitDocumentsAnnouncement: OneTimeAnnouncement & ActionableAnnouncement {

    // MARK: - Properties

    var viewModel: AnnouncementCardViewModel {
        let button = ButtonViewModel.primary(
            with: LocalizationConstants.AnnouncementCards.ResubmitDocuments.ctaButton
        )
        button.tapRelay
            .bind {  [weak self] in
                guard let self = self else { return }
                self.analyticsRecorder.record(event: self.actionAnalyticsEvent)
                self.markRemoved()
                self.action()
                self.dismiss()
            }
            .disposed(by: disposeBag)

        return AnnouncementCardViewModel(
            image: AnnouncementCardViewModel.Image(name: "card-icon-v"),
            title: LocalizationConstants.AnnouncementCards.ResubmitDocuments.title,
            description: LocalizationConstants.AnnouncementCards.ResubmitDocuments.description,
            buttons: [button],
            dismissState: .dismissible { [weak self] in
                guard let self = self else { return }
                self.analyticsRecorder.record(event: self.dismissAnalyticsEvent)
                self.markRemoved()
                self.dismiss()
            },
            didAppear: { [weak self] in
                guard let self = self else { return }
                self.analyticsRecorder.record(event: self.didAppearAnalyticsEvent)
            }
        )
    }

    var shouldShow: Bool {
        guard user.needsDocumentResubmission != nil else {
            return false
        }
        return !isDismissed
    }
    
    let type = AnnouncementType.resubmitDocuments
    let analyticsRecorder: AnalyticsEventRecording

    var dismiss: CardAnnouncementAction
    var recorder: AnnouncementRecorder
    
    let action: CardAnnouncementAction

    private let user: NabuUser

    private let disposeBag = DisposeBag()
    
    // MARK: - Setup

    init(user: NabuUser,
         cacheSuite: CacheSuite = UserDefaults.standard,
         analyticsRecorder: AnalyticsEventRecording = AnalyticsEventRecorder.shared,
         dismiss: @escaping CardAnnouncementAction,
         action: @escaping CardAnnouncementAction) {
        self.user = user
        self.recorder = AnnouncementRecorder(cache: cacheSuite)
        self.analyticsRecorder = analyticsRecorder
        self.dismiss = dismiss
        self.action = action
    }
}
