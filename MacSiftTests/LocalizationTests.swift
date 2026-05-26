import Foundation
import Testing
@testable import MacSift

@Suite("Localization")
struct LocalizationTests {
    private let chinese = Locale(identifier: "zh-Hans")

    @Test func supportedLanguagesAreRegistered() {
        #expect(AppLanguage.allCases.map(\.rawValue) == ["system", "english", "simplifiedChinese", "french"])
        #expect(AppLanguage.simplifiedChinese.localeIdentifier == "zh-Hans")
    }

    @Test func chineseResourcesAreBundled() throws {
        let path = try #require(L10n.resourcePath(forLocalization: "zh-Hans"))
        #expect(path.hasSuffix("zh-Hans.lproj/Localizable.strings"))
    }

    @Test func languageOverrideDrivesLookup() {
        L10n.setLanguage(.simplifiedChinese)
        defer { L10n.setLanguage(.system) }

        #expect(L10n.text("Start Scan", defaultValue: "Start Scan") == "开始扫描")
    }

    @Test func categoryLabelsResolveInChinese() {
        #expect(FileCategory.cache.localizedLabel(locale: chinese) == "缓存")
        #expect(FileCategory.oldDownloads.localizedLabel(locale: chinese) == "旧下载")
        #expect(FileCategory.mailDownloads.localizedLabel(locale: chinese) == "邮件附件")
    }

    @Test func riskLabelsResolveInChinese() {
        #expect(RiskLevel.safe.localizedLabel(locale: chinese) == "可安全删除")
        #expect(RiskLevel.moderate.localizedLabel(locale: chinese) == "建议检查")
        #expect(RiskLevel.risky.localizedLabel(locale: chinese) == "谨慎处理")
    }

    @Test func fileDescriptionsResolveInChinese() {
        let temp = URL(filePath: "/tmp/random_file.dat")
        let log = URL(filePath: "/private/var/log/system.log")

        #expect(FileDescriptions.describe(url: temp, category: .tempFiles, locale: chinese) == "临时文件：random_file.dat")
        #expect(FileDescriptions.describe(url: log, category: .logs, locale: chinese) == "系统日志：system.log")
    }
}
