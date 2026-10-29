import XCTest
@testable import ManiculeCore

final class GoogleLinkTests: XCTestCase {
    private func link(_ s: String) -> GoogleLink? { GoogleLink(url: URL(string: s)!) }

    /// Drive file ids are long; these are made-up ids of a realistic length.
    private let doc = "1DocAbCdEfGhIjKlMnOpQrStUvWxYz0123456789"
    private let sheet = "1SheetAbCdEfGhIjKlMnOpQrStUvWxYz01234567"
    private let slides = "1SlidesAbCdEfGhIjKlMnOpQrStUvWxYz0123456"
    private let file = "1FileAbCdEfGhIjKlMnOpQrSt"
    private let folder = "1FolderAbCdEfGhIjKlMnOpQ"
    private let opened = "1OpenAbCdEfGhIjKlMnOpQrSt"

    func testDocFileIDAndWebApp() {
        let l = link("https://docs.google.com/document/d/\(doc)/edit")
        XCTAssertEqual(l, GoogleLink(fileID: doc, email: nil, webApp: .docs))
    }

    func testSheetsAndSlides() {
        XCTAssertEqual(link("https://docs.google.com/spreadsheets/d/\(sheet)/edit"),
                       GoogleLink(fileID: sheet, email: nil, webApp: .sheets))
        XCTAssertEqual(link("https://docs.google.com/presentation/d/\(slides)/edit"),
                       GoogleLink(fileID: slides, email: nil, webApp: .slides))
        XCTAssertEqual(WebApp.docs.chromeAppID, "mpnpojknpmmopombnjdcgaaiekajbnjb")
        XCTAssertEqual(WebApp.sheets.chromeAppID, "fhihpiojkbmbpdjeoajapmgkhlnakfjf")
        XCTAssertEqual(WebApp.slides.chromeAppID, "kefjledonklijopmnomlcbpllchaibag")
    }

    func testFormFileID() {
        XCTAssertEqual(link("https://docs.google.com/forms/d/\(doc)/edit")?.fileID, doc)
    }

    func testDriveFileFolderAndOpen() {
        let f = link("https://drive.google.com/file/d/\(file)/view")
        XCTAssertEqual(f?.fileID, file)
        XCTAssertNil(f?.webApp)
        XCTAssertEqual(link("https://drive.google.com/drive/folders/\(folder)")?.fileID, folder)
        XCTAssertEqual(link("https://drive.google.com/drive/u/1/folders/\(folder)")?.fileID, folder)
        XCTAssertEqual(link("https://docs.google.com/open?id=\(opened)")?.fileID, opened)
        XCTAssertEqual(link("https://drive.google.com/open?id=\(opened)")?.fileID, opened)
    }

    /// `/d/e/<id>` is a published page or a form's response link: that id is not a Drive file id.
    func testPublishedAndFormResponseLinksHaveNoFileID() {
        XCTAssertNil(link("https://docs.google.com/forms/d/e/1FAIpQLSeAbCdEfGhIjKlMnOpQrStUvWxYz/viewform")?.fileID)
        let published = link("https://docs.google.com/document/d/e/2PACX-1vAbCdEfGhIjKlMnOpQrStUvWxYz/pub")
        XCTAssertNotNil(published)
        XCTAssertNil(published?.fileID)
    }

    func testOtherGoogleHostsHaveNoFileID() {
        XCTAssertNil(link("https://www.google.com/maps/d/edit?mid=1MapAbCdEfGhIjKlMnOpQrStUv")?.fileID)
        XCTAssertNil(link("https://play.google.com/store/apps/details?id=com.example.someapp.long")?.fileID)
        XCTAssertNil(link("https://www.google.com/open?id=\(opened)")?.fileID)
    }

    func testShortIDsAreNotFileIDs() {
        XCTAssertNil(link("https://docs.google.com/document/d/ABC123/edit")?.fileID)
        XCTAssertNil(link("https://drive.google.com/drive/folders/my-drive")?.fileID)
        XCTAssertNil(link("https://docs.google.com/open?id=O1")?.fileID)
    }

    func testAuthuserEmailDecodedAndLowercased() {
        let l = link("https://docs.google.com/open?id=\(opened)&authuser=Someone%40Example.COM&usp=drive_fs")
        XCTAssertEqual(l?.fileID, opened)
        XCTAssertEqual(l?.email, "someone@example.com")
    }

    func testPathEmail() {
        XCTAssertEqual(link("https://mail.google.com/mail/u/a@example.com/")?.email, "a@example.com")
        XCTAssertEqual(link("https://mail.google.com/mail/u/B%40Example.com/")?.email, "b@example.com")
    }

    func testNumericAccountIndexIsNoEmail() {
        let p = link("https://docs.google.com/u/1/document/d/\(doc)/edit")
        XCTAssertNil(p?.email)
        XCTAssertEqual(p?.fileID, doc)
        let q = link("https://docs.google.com/document/d/\(doc)/edit?authuser=1")
        XCTAssertNil(q?.email)
        XCTAssertEqual(q?.fileID, doc)
    }

    func testNonGoogleHostIsNil() {
        XCTAssertNil(link("https://github.com/x"))
        XCTAssertNil(link("https://notgoogle.com/x"))
    }
}
