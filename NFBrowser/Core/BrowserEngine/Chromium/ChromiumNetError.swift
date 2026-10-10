import Foundation

/// Maps Chromium net error codes (net/base/net_error_list.h) to the NSURLError codes the
/// status page understands, so both engines show the same error screens.
enum ChromiumNetError {
    static let domain = "ChromiumNetErrorDomain"
    static let codeKey = "ChromiumNetErrorCode"

    static func makeError(code: Int, text: String, url: URL?) -> NSError {
        var userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: text.isEmpty ? "net::\(code)" : text,
            codeKey: code
        ]
        if let url {
            userInfo[NSURLErrorFailingURLErrorKey] = url
            userInfo[NSURLErrorFailingURLStringErrorKey] = url.absoluteString
        }
        guard let urlErrorCode = urlErrorCode(forNetError: code) else {
            return NSError(domain: domain, code: code, userInfo: userInfo)
        }
        return NSError(domain: NSURLErrorDomain, code: urlErrorCode, userInfo: userInfo)
    }

    static func urlErrorCode(forNetError code: Int) -> Int? {
        switch code {
        case -106: // INTERNET_DISCONNECTED
            NSURLErrorNotConnectedToInternet
        case -21, -100, -101: // NETWORK_CHANGED, CONNECTION_CLOSED, CONNECTION_RESET
            NSURLErrorNetworkConnectionLost
        case -102, -104, -109: // CONNECTION_REFUSED, CONNECTION_FAILED, ADDRESS_UNREACHABLE
            NSURLErrorCannotConnectToHost
        case -105, -137: // NAME_NOT_RESOLVED, NAME_RESOLUTION_FAILED
            NSURLErrorCannotFindHost
        case -7, -118: // TIMED_OUT, CONNECTION_TIMED_OUT
            NSURLErrorTimedOut
        case -300, -301, -302: // INVALID_URL, DISALLOWED_URL_SCHEME, UNKNOWN_URL_SCHEME
            NSURLErrorBadURL
        case -110: // SSL_CLIENT_AUTH_CERT_NEEDED
            NSURLErrorClientCertificateRequired
        case -299 ... -200: // CERT_*
            NSURLErrorServerCertificateUntrusted
        case -107, -113: // SSL_PROTOCOL_ERROR, SSL_VERSION_OR_CIPHER_MISMATCH
            NSURLErrorSecureConnectionFailed
        default:
            nil
        }
    }
}
