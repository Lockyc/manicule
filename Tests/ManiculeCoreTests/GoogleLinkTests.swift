import XCTest
@testable import ManiculeCore

final class GoogleLinkTests: XCTestCase {
    private func link(_ s: String) -> GoogleLink? { GoogleLink(url: URL(string: s)!) }

    func testDocFileIDAndWebApp() {
        let l = link("https://docs.google.com/document/d/ABC123/edit")
        XCTAssertEqual(l, GoogleLink(fileID: "ABC123", email: nil, webApp: .docs))
    }

    func testSheetsAndSlides() {
        XCTAssertEqual(link("https://docs.google.com/spreadsheets/d/S1/edit")?.webApp, .sheets)
        XCTAssertEqual(link("https://docs.google.com/presentation/d/P1/edit")?.webApp, .slides)
        XCTAssertEqual(WebApp.docs.chromeAppID, "mpnpojknpmmopombnjdcgaaiekajbnjb")
        XCTAssertEqual(WebApp.sheets.chromeAppID, "fhihpiojkbmbpdjeoajapmgkhlnakfjf")
        XCTAssertEqual(WebApp.slides.chromeAppID, "kefjledonklijopmnomlcbpllchaibag")
    }

    func testDriveFileFolderAndOpen() {
        let f = link("https://drive.google.com/file/d/F1/view")
        XCTAssertEqual(f?.fileID, "F1")
        XCTAssertNil(f?.webApp)
        XCTAssertEqual(link("https://drive.google.com/drive/folders/D1")?.fileID, "D1")
        XCTAssertEqual(link("https://docs.google.com/open?id=O1")?.fileID, "O1")
    }

    func testAuthuserEmailDecodedAndLowercased() {
        let l = link("https://docs.google.com/open?id=O1&authuser=Lachlan%40Example.COM&usp=drive_fs")
        XCTAssertEqual(l?.fileID, "O1")
        XCTAssertEqual(l?.email, "lachlan@example.com")
    }

    func testPathEmail() {
        XCTAssertEqual(link("https://mail.google.com/mail/u/a@example.com/")?.email, "a@example.com")
        XCTAssertEqual(link("https://mail.google.com/mail/u/B%40Example.com/")?.email, "b@example.com")
    }

    func testNumericAccountIndexIsNoEmail() {
        let p = link("https://docs.google.com/u/1/document/d/X/edit")
        XCTAssertNil(p?.email)
        XCTAssertEqual(p?.fileID, "X")
        let q = link("https://docs.google.com/document/d/X/edit?authuser=1")
        XCTAssertNil(q?.email)
        XCTAssertEqual(q?.fileID, "X")
    }

    func testNonGoogleHostIsNil() {
        XCTAssertNil(link("https://github.com/x"))
        XCTAssertNil(link("https://notgoogle.com/x"))
    }
}
