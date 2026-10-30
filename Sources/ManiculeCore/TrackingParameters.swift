import Foundation

/// Known click-tracking query parameters, removed when a link is copied.
public enum TrackingParameters {
    public static let prefixes: [String] = ["utm_", "mc_", "pk_", "hsa_"]

    public static let names: Set<String> = [
        "fbclid", "gclid", "gclsrc", "dclid", "gbraid", "wbraid", "msclkid",
        "yclid", "twclid", "igshid", "_hsenc", "_hsmi", "mkt_tok",
        "oly_anon_id", "oly_enc_id", "vero_id", "rb_clickid", "s_cid", "ref_src",
    ]

    /// The URL without tracking parameters; order of the rest and the fragment are kept,
    /// and the `?` is dropped when nothing remains. Kept parameters stay percent-encoded as they
    /// came: decoding and re-encoding them would turn `%2B` into `+`, a space to the server.
    public static func stripped(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let items = components.percentEncodedQueryItems else { return url }
        let kept = items.filter { !isTracking($0.name.removingPercentEncoding ?? $0.name) }
        guard kept.count != items.count else { return url }
        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        return components.url ?? url
    }

    private static func isTracking(_ name: String) -> Bool {
        let lower = name.lowercased()
        return names.contains(lower) || prefixes.contains { lower.hasPrefix($0) }
    }
}
