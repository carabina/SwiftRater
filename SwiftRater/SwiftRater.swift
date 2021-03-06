//
//  SwiftRater.swift
//  SwiftRater
//
//  Created by Fujiki Takeshi on 2017/03/28.
//  Copyright © 2017年 com.takecian. All rights reserved.
//

import UIKit
import StoreKit

public class SwiftRater: NSObject {

    enum ButtonIndex: Int {
        case cancel = 0
        case rate = 1
        case later = 2
    }

    public let SwiftRaterErrorDomain = "Siren Error Domain"

    public static var daysUntilPrompt: Int {
        get {
            return UsageDataManager.shared.daysUntilPrompt
        }
        set {
            UsageDataManager.shared.daysUntilPrompt = newValue
        }
    }
    public static var usesUntilPrompt: Int {
        get {
            return UsageDataManager.shared.usesUntilPrompt
        }
        set {
            UsageDataManager.shared.usesUntilPrompt = newValue
        }
    }
    public static var significantUsesUntilPrompt: Int {
        get {
            return UsageDataManager.shared.significantUsesUntilPrompt
        }
        set {
            UsageDataManager.shared.significantUsesUntilPrompt = newValue
        }
    }

    public static var daysBeforeReminding: Int {
        get {
            return UsageDataManager.shared.daysBeforeReminding
        }
        set {
            UsageDataManager.shared.daysBeforeReminding = newValue
        }
    }
    public static var debugMode: Bool {
        get {
            return UsageDataManager.shared.debugMode
        }
        set {
            UsageDataManager.shared.debugMode = newValue
        }
    }

    public static var showLaterButton: Bool = true

    public static var alertTitle: String?
    public static var alertMessage: String?
    public static var alertCancelTitle: String?
    public static var alertRateTitle: String?
    public static var alertRateLaterTitle: String?

    public static var showLog: Bool = false
    public static var resetWhenAppUpdated: Bool = true

    public static var shared = SwiftRater()

    fileprivate var appID: Int?

    private static var appVersion: String {
        get {
            return Bundle.main.infoDictionary!["CFBundleShortVersionString"] as? String ?? "0.0.0"
        }
    }

    private var titleText: String {
        return SwiftRater.alertTitle ?? String.init(format: localize("Rate %@"), mainAppName)
    }

    private var messageText: String {
        return SwiftRater.alertMessage ?? String.init(format: localize("Rater.title"), mainAppName)
    }

    private var rateText: String {
        return SwiftRater.alertRateTitle ?? String.init(format: localize("Rate %@"), mainAppName)
    }

    private var cancelText: String {
        return SwiftRater.alertCancelTitle ?? String.init(format: localize("No, Thanks"), mainAppName)
    }

    private var laterText: String {
        return SwiftRater.alertRateLaterTitle ?? String.init(format: localize("Remind me later"), mainAppName)
    }

    private func localize(_ key: String) -> String {
        return NSLocalizedString(key, tableName: "SwiftRaterLocalization", bundle: Bundle(for: SwiftRater.self), comment: "")
    }

    private var mainAppName: String {
        if let name = Bundle.main.infoDictionary?["CFBundleDisplayName"] as? String {
            return name
        } else if let name = Bundle.main.infoDictionary?["CFBundleName"] as? String {
            return name
        } else {
            return "App"
        }
    }

    private override init() {
        super.init()
    }

    public static func appLaunched() {
        if SwiftRater.resetWhenAppUpdated && SwiftRater.appVersion != UsageDataManager.shared.trackingVersion {
            UsageDataManager.shared.reset()
            UsageDataManager.shared.trackingVersion = SwiftRater.appVersion
        }

        SwiftRater.shared.perform()
    }

    public static func incrementSignificantUsageCount() {
        UsageDataManager.shared.incrementSignificantUseCount()
    }

    public static func check() {
        if UsageDataManager.shared.ratingConditionsHaveBeenMet {
            SwiftRater.shared.showRatingAlert()
        }
    }

    public static func reset() {
        UsageDataManager.shared.reset()
    }

    private func perform() {
        // get appID and version from itunes
        do {
            let url = try iTunesURLFromString()
            let request = URLRequest(url: url, cachePolicy: .reloadIgnoringCacheData, timeoutInterval: 30)
            URLSession.shared.dataTask(with: request, completionHandler: { (data, response, error) in
                self.processResults(withData: data, response: response, error: error)
            }).resume()
        } catch let error {
            postError(.malformedURL, underlyingError: error)
        }
    }

    private func processResults(withData data: Data?, response: URLResponse?, error: Error?) {
        if let error = error {
            self.postError(.appStoreDataRetrievalFailure, underlyingError: error)
        } else {
            guard let data = data else {
                self.postError(.appStoreDataRetrievalFailure, underlyingError: nil)
                return
            }

            do {
                let jsonData = try JSONSerialization.jsonObject(with: data, options: JSONSerialization.ReadingOptions.allowFragments)
                guard let appData = jsonData as? [String: Any] else {
                    self.postError(.appStoreJSONParsingFailure, underlyingError: nil)
                    return
                }

                DispatchQueue.main.async {
                    // Print iTunesLookup results from appData
//                    self.printMessage(message: "JSON results: \(appData)")

                    // Process Results (e.g., extract current version that is available on the AppStore)
                    self.processVersionCheck(withResults: appData)
                }

            } catch let error {
                self.postError(.appStoreDataRetrievalFailure, underlyingError: error)
            }
        }
    }

    private func processVersionCheck(withResults results: [String: Any]) {
        guard let allResults = results["results"] as? [[String: Any]] else {
            self.postError(.appStoreDataRetrievalFailure, underlyingError: nil)
            return
        }

        /// App not in App Store
        guard !allResults.isEmpty else {
            postError(.appStoreDataRetrievalFailure, underlyingError: nil)
            return
        }

        guard let appID = allResults.first?["trackId"] as? Int else {
            postError(.appStoreAppIDFailure, underlyingError: nil)
            return
        }

        self.appID = appID
        
        incrementUsageCount()
    }

    private func iTunesURLFromString() throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "itunes.apple.com"
        components.path = "/lookup"

        let items: [URLQueryItem] = [URLQueryItem(name: "bundleId", value: Bundle.bundleID())]

        components.queryItems = items

        guard let url = components.url, !url.absoluteString.isEmpty else {
            throw SwiftRaterError.malformedURL
        }

        return url
    }

    private func postError(_ code: SwiftRaterErrorCode, underlyingError: Error?) {
        let description: String

        switch code {
        case .malformedURL:
            description = "The iTunes URL is malformed. Please leave an issue on http://github.com/ArtSabintsev/Siren with as many details as possible."
        case .appStoreDataRetrievalFailure:
            description = "Error retrieving App Store data as an error was returned."
        case .appStoreJSONParsingFailure:
            description = "Error parsing App Store JSON data."
        case .appStoreAppIDFailure:
            description = "Error retrieving trackId as results.first does not contain a 'trackId' key."
        }

        var userInfo: [String: Any] = [NSLocalizedDescriptionKey: description]

        if let underlyingError = underlyingError {
            userInfo[NSUnderlyingErrorKey] = underlyingError
        }

        let error = NSError(domain: SwiftRaterErrorDomain, code: code.rawValue, userInfo: userInfo)
        printMessage(message: error.localizedDescription)
    }

    private func printMessage(message: String) {
        if SwiftRater.showLog {
            print("[SwiftRater] \(message)")
        }
    }

    private func incrementUsageCount() {
        UsageDataManager.shared.incrementUseCount()
    }

    private func incrementSignificantUseCount() {
        UsageDataManager.shared.incrementSignificantUseCount()
    }

    private func showRatingAlert() {
        if #available(iOS 10.3, *) {
            SKStoreReviewController.requestReview()
            UsageDataManager.shared.isRateDone = true
        } else {
            let alertView = { () -> UIAlertView in
                if SwiftRater.showLaterButton {
                    return UIAlertView(title: titleText, message: messageText, delegate: self, cancelButtonTitle: cancelText, otherButtonTitles: rateText, laterText)
                } else {
                    return UIAlertView(title: titleText, message: messageText, delegate: self, cancelButtonTitle: cancelText, otherButtonTitles: rateText)
                }
            }()
            alertView.show()
        }
    }
}

extension SwiftRater: UIAlertViewDelegate {
    public func alertView(_ alertView: UIAlertView, clickedButtonAt buttonIndex: Int) {
        if SwiftRater.showLaterButton {
            switch buttonIndex {
            case ButtonIndex.rate.rawValue:
                rateApp()
                UsageDataManager.shared.isRateDone = true
            case ButtonIndex.later.rawValue:
                UsageDataManager.shared.saveReminderRequestDate()
            default:
                UsageDataManager.shared.isRateDone = true
            }
        } else {
            switch buttonIndex {
            case ButtonIndex.rate.rawValue:
                rateApp()
                UsageDataManager.shared.isRateDone = true
            default:
                UsageDataManager.shared.isRateDone = true
            }
        }
    }

    private func rateApp() {
        #if arch(i386) || arch(x86_64)
            print("APPIRATER NOTE: iTunes App Store is not supported on the iOS simulator. Unable to open App Store page.");
        #else
            guard let appId = self.appID else { return }
            let reviewURL = "itms-apps://itunes.apple.com/WebObjects/MZStore.woa/wa/viewContentsUserReviews?id=\(appId)&onlyLatestVersion=true&pageNumber=0&sortOrdering=1&type=Purple+Software";
            guard let url = URL(string: reviewURL) else { return }
            UIApplication.shared.openURL(url)
        #endif
    }
}
