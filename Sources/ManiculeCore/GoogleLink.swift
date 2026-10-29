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

        let fileID = host == "docs.google.com" || host == "drive.google.com"
            ? Self.fileID(segments: segments, id: query("id")).flatMap(Self.validFileID)
            : nil

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

    /// The Drive file id in one of the known shapes: `/<kind>/d/<id>` (a `/u/N/` prefix allowed),
    /// `/drive[/u/N]/folders/<id>`, `open?id=<id>`. `/d/e/<id>` is a published page or a form's
    /// response link, whose id is not a Drive file id.
    private static func fileID(segments: [String], id: String?) -> String? {
        let kinds: Set<String> = ["document", "spreadsheets", "presentation", "forms", "file"]
        if let i = segments.indices.dropLast(2).first(where: { kinds.contains(segments[$0]) && segments[$0 + 1] == "d" }) {
            let candidate = segments[i + 2]
            return candidate == "e" ? nil : candidate
        }
        if let i = segments.firstIndex(of: "folders"), i + 1 < segments.count {
            let prefix = Array(segments[..<i])
            if prefix == ["drive"] || (prefix.count == 3 && prefix[0] == "drive" && prefix[1] == "u") {
                return segments[i + 1]
            }
        }
        if segments == ["open"] { return id }
        return nil
    }

    /// Drive file ids are long runs of letters, digits, `-` and `_`.
    private static func validFileID(_ id: String) -> String? {
        id.count >= 20 && id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") })
            ? id : nil
    }
}
