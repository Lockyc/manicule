import Foundation

public enum WebApp: String, Sendable {
    case docs, sheets, slides

    /// The Chrome app ID of the installed Docs/Sheets/Slides web app.
    public var chromeAppID: String {
        switch self {
        case .docs: "mpnpojknpmmopombnjdcgaaiekajbnjb"
        case .sheets: "fhihpiojkbmbpdjeoajapmgkhlnakfjf"
        case .slides: "kefjledonklijopmnomlcbpllchaibag"
        }
    }
}

public struct GoogleLink: Equatable, Sendable {
    public var fileID: String?
    public var email: String?
    public var webApp: WebApp?

    public init(fileID: String?, email: String?, webApp: WebApp?) {
        self.fileID = fileID
        self.email = email
        self.webApp = webApp
    }
}

extension GoogleLink {
    /// Nil unless the host is `google.com` or one of its subdomains.
    public init?(url: URL) {
        guard let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let host = parts.host?.lowercased(),
              host == "google.com" || host.hasSuffix(".google.com")
        else { return nil }

        let segments = parts.path.split(separator: "/").map(String.init)
        func after(_ key: String) -> String? {
            guard let i = segments.firstIndex(of: key), i + 1 < segments.count else { return nil }
            return segments[i + 1]
        }
        func query(_ name: String) -> String? {
            parts.queryItems?.first { $0.name == name }?.value
        }

        let fileID = after("d") ?? after("folders") ?? query("id")

        // Only an address is an account; a numeric index (`/u/1/`, `authuser=1`) is not.
        let email = [after("u"), query("authuser")]
            .compactMap { $0 }
            .first { $0.contains("@") }?
            .lowercased()

        let webApp: WebApp? = host == "docs.google.com"
            ? ["document": WebApp.docs, "spreadsheets": .sheets, "presentation": .slides]
                .first { segments.contains($0.key) }?.value
            : nil

        self.init(fileID: fileID, email: email, webApp: webApp)
    }
}
