import Foundation
@testable import NFBrowser
import Testing

struct ChromiumEngineTests {
    @Test func netErrorsMapToURLErrorCodes() {
        #expect(ChromiumNetError.urlErrorCode(forNetError: -105) == NSURLErrorCannotFindHost)
        #expect(ChromiumNetError.urlErrorCode(forNetError: -106) == NSURLErrorNotConnectedToInternet)
        #expect(ChromiumNetError.urlErrorCode(forNetError: -202) == NSURLErrorServerCertificateUntrusted)
        #expect(ChromiumNetError.urlErrorCode(forNetError: -118) == NSURLErrorTimedOut)
        #expect(ChromiumNetError.urlErrorCode(forNetError: -2) == nil)

        let url = URL(string: "https://expired.badssl.com/")
        let error = ChromiumNetError.makeError(code: -201, text: "net::ERR_CERT_DATE_INVALID", url: url)
        #expect(error.domain == NSURLErrorDomain)
        #expect(error.code == NSURLErrorServerCertificateUntrusted)
        #expect(error.userInfo[NSURLErrorFailingURLErrorKey] as? URL == url)
        #expect(ChromiumNetError.makeError(code: -2, text: "", url: nil).domain == ChromiumNetError.domain)
    }

    @Test func documentEndScriptsWaitForTheDOMInTheMainFrame() {
        let script = BrowserUserScript(
            name: "probe",
            source: "window.__probe = 1;",
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        )
        let source = ChromiumUserScripts.chromiumSource(for: script)
        #expect(source.hasPrefix("if (window.top === window) {"))
        #expect(source.contains("DOMContentLoaded"))
        #expect(source.contains("window.__probe = 1;"))

        let startScript = BrowserUserScript(
            name: nil,
            source: "start();",
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        #expect(ChromiumUserScripts.chromiumSource(for: startScript) == "start();")
    }

    @Test func bindingPayloadDecodesIntoScriptMessage() {
        let message = ChromiumUserScripts.message(fromBindingPayload: #"{"name":"linkHover","body":"https://a.b/"}"#)
        #expect(message?.name == "linkHover")
        #expect(message?.body as? String == "https://a.b/")
        #expect(ChromiumUserScripts.message(fromBindingPayload: #"{"name":"empty","body":null}"#)?.body == nil)
        #expect(ChromiumUserScripts.message(fromBindingPayload: "not json") == nil)
    }

    @Test func bridgeScriptRemovesTheBindingAndNeverDefinesWebKit() {
        let script = ChromiumUserScripts.bridgeScript(bindingName: "__nfabc")
        #expect(script.contains("'__nfabc'"))
        #expect(script.contains("delete window[bindingName]"))
        #expect(script.contains("'__oraBridge'"))
        #expect(!script.contains("window.webkit"))
    }
}
