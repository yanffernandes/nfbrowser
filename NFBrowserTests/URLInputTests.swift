import Foundation
@testable import NFBrowser
import Testing

struct URLInputTests {
    @Test func fileURLConstructionAndValidation() {
        let fileURLString = "file:///Users/yanfernandes/Downloads/teste.html"
        #expect(isValidURL(fileURLString))
        let url = constructURL(from: fileURLString)
        #expect(url != nil)
        #expect(url?.isFileURL == true)
        #expect(url?.path == "/Users/yanfernandes/Downloads/teste.html")

        let tmpURL = constructURL(from: "/tmp")
        #expect(tmpURL != nil)
        #expect(tmpURL?.isFileURL == true)
    }

    @Test func aboutAndDataSchemesRequirePayload() {
        #expect(isValidURL("about:blank"))
        #expect(constructURL(from: "data:text/html,hello world")?.scheme == "data")
        #expect(!isValidURL("data: science jobs"))
        #expect(constructURL(from: "data: science jobs") == nil)
        #expect(constructURL(from: "about: me") == nil)
    }
}
