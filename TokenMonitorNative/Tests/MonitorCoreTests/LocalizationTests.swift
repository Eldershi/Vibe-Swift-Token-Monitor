import XCTest
@testable import MonitorCore
@testable import TokenMonitorNative

final class LocalizationTests: XCTestCase {
    func testBothNativeLanguageResourcesAndDynamicValues() throws {
        for (language, title) in [("en", "Data"), ("zh-Hans", "数据")] {
            let url = try XCTUnwrap(L10n.resourceBundle.resourceURL?.appendingPathComponent(language.lowercased() + ".lproj"))
            let bundle = try XCTUnwrap(Bundle(url: url))
            XCTAssertEqual(bundle.localizedString(forKey: "数据", value: nil, table: nil), title)
            let format = bundle.localizedString(forKey: "连接成功：已读取 %@ 台设备。点击“保存连接”开始同步。", value: nil, table: nil)
            for count in [0, 1, 2] {
                let text = String(format: format, String(count))
                XCTAssertTrue(text.contains(String(count)))
                XCTAssertFalse(text.contains("%@"))
                if language == "en" { XCTAssertTrue(text.contains("Devices read:")) }
            }
        }
    }
    func testPersistedPageIdentityIsIndependentOfLanguage() {
        XCTAssertEqual(Page.overview.rawValue, "总览")
        XCTAssertEqual(Page(rawValue: "模型"), .models)
        XCTAssertEqual(Page.models.title, L10n.text("模型"))
        XCTAssertEqual(HomeSection.trends.rawValue, "trends")
    }
    func testDynamicArgumentsAreNotTreatedAsFormatOrLocalizationKeys() {
        XCTAssertTrue(["Remaining 50%", "剩余 50%"].contains(L10n.text("剩余 %@", "50%")))
        XCTAssertTrue(L10n.text("Hub 数据格式不兼容（%@），已保留上次有效数据。", "external %@ 100%").contains("external %@ 100%"))
    }
}
