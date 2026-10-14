import Foundation
@testable import NFBrowser
import Testing
@preconcurrency import WebKit

/// Camera, microphone and screen requests as a tab asks the user about them.
struct MediaCapturePermissionTests {
    private struct Question {
        let site: String
        let devices: BrowserMediaDevices
        let answer: (Bool) -> Void
    }

    /// Keeps each question until the test answers it.
    private final class User {
        var questions: [Question] = []

        func answer(_ granted: Bool) throws {
            let question = try #require(questions.first)
            questions.removeFirst()
            question.answer(granted)
        }
    }

    private func permissions(asking user: User) -> MediaCapturePermissions {
        MediaCapturePermissions { site, devices, answer in
            user.questions.append(Question(site: site, devices: devices, answer: answer))
        }
    }

    @Test func asksOncePerSiteUntilTheNextPage() throws {
        let user = User()
        let permissions = permissions(asking: user)
        var decisions: [Bool] = []
        permissions.request([.camera, .microphone], from: "meet.example") { decisions.append($0) }
        #expect(user.questions.map(\.devices) == [[.camera, .microphone]])
        try user.answer(true)
        permissions.request(.camera, from: "meet.example") { decisions.append($0) }
        #expect(decisions == [true, true])
        #expect(user.questions.isEmpty)

        permissions.request(.camera, from: "other.example") { decisions.append($0) }
        permissions.reset()
        permissions.request(.camera, from: "meet.example") { decisions.append($0) }
        #expect(user.questions.map(\.site) == ["other.example", "meet.example"])
    }

    @Test func refusedDevicesStayRefusedUntilTheNextPage() throws {
        let user = User()
        let permissions = permissions(asking: user)
        var decisions: [Bool] = []
        permissions.request(.camera, from: "site.example") { decisions.append($0) }
        try user.answer(false)
        permissions.request([.camera, .microphone], from: "site.example") { decisions.append($0) }
        #expect(decisions == [false, false])
        #expect(user.questions.isEmpty)
        // The microphone alone was never refused.
        permissions.request(.microphone, from: "site.example") { decisions.append($0) }
        #expect(user.questions.map(\.devices) == [.microphone])
    }

    @Test func requestsWhileAskingWaitForTheAnswer() throws {
        let user = User()
        let permissions = permissions(asking: user)
        var decisions: [String] = []
        permissions.request([.camera, .microphone], from: "site.example") { decisions.append("both \($0)") }
        permissions.request(.camera, from: "site.example") { decisions.append("camera \($0)") }
        permissions.request(.screen, from: "site.example") { decisions.append("screen \($0)") }
        #expect(user.questions.count == 1)
        try user.answer(true)
        #expect(decisions == ["both true", "camera true"])
        // The screen wasn't part of that question, so it gets its own.
        #expect(user.questions.map(\.devices) == [.screen])
    }

    @Test func screenSharingIsAskedEachTime() throws {
        let user = User()
        let permissions = permissions(asking: user)
        var decisions: [Bool] = []
        permissions.request(.screen, from: "site.example") { decisions.append($0) }
        try user.answer(true)
        permissions.request(.screen, from: "site.example") { decisions.append($0) }
        #expect(decisions == [true])
        #expect(user.questions.map(\.devices) == [.screen])
    }

    @Test func answersAboutAnEarlierPageAreNotKept() throws {
        let user = User()
        let permissions = permissions(asking: user)
        var decisions: [Bool] = []
        permissions.request(.camera, from: "site.example") { decisions.append($0) }
        permissions.reset()
        try user.answer(true)
        #expect(decisions == [false])
        permissions.request(.camera, from: "site.example") { decisions.append($0) }
        #expect(user.questions.count == 1)
    }

    @Test func questionsNameTheSiteAndWhatItWants() {
        #expect(
            MediaCapturePermissions.question(for: [.camera, .microphone], from: "meet.example")
                == "Allow “meet.example” to use your camera and microphone?"
        )
        #expect(
            MediaCapturePermissions.question(for: .screen, from: "meet.example")
                == "Allow “meet.example” to share your screen?"
        )
        #expect(MediaCapturePermissions.siteName(for: URL(string: "https://meet.example/")) == "meet.example")
        #expect(MediaCapturePermissions.siteName(for: URL(string: "http://localhost:8080")) == "localhost:8080")
    }

    /// The engines look these methods up by name, so a near miss compiles but is never called.
    @Test func enginesImplementTheirPermissionMethods() {
        #expect(WebKitBrowserPage.instancesRespond(to: #selector(
            WKUIDelegate.webView(_:requestMediaCapturePermissionFor:initiatedByFrame:type:decisionHandler:)
        )))
        #expect(ChromiumBrowserPage.instancesRespond(to: #selector(
            NFChromiumBrowserViewDelegate.chromiumBrowserView(_:requestMediaAccessForOrigin:devices:decision:)
        )))
    }
}
