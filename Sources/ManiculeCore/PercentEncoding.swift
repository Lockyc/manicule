import Foundation

/// Percent-encoding for id parts and URL query values, shared by every target kind that
/// builds either.
enum PercentEncoding {
    /// The only characters left bare.
    private static let unreserved = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    static func encode(_ s: String) -> String {
        s.addingPercentEncoding(withAllowedCharacters: unreserved) ?? s
    }
}
