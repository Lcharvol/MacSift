import Testing
@testable import MacSift

@Suite("FileSize Formatting")
struct FileSizeFormattingTests {
    @Test func formatsBytes() {
        #expect(Int64(0).formattedFileSize == "0 B")
        #expect(Int64(512).formattedFileSize == "512 B")
        #expect(Int64(1023).formattedFileSize == "1,023 B")
    }

    @Test func formatsKilobytes() {
        #expect(Int64(1024).formattedFileSize == "1.0 KB")
        #expect(Int64(1536).formattedFileSize == "1.5 KB")
        #expect(Int64(10240).formattedFileSize == "10.0 KB")
    }

    @Test func formatsMegabytes() {
        #expect(Int64(1_048_576).formattedFileSize == "1.0 MB")
        #expect(Int64(5_242_880).formattedFileSize == "5.0 MB")
    }

    @Test func formatsGigabytes() {
        #expect(Int64(1_073_741_824).formattedFileSize == "1.0 GB")
        #expect(Int64(2_684_354_560).formattedFileSize == "2.5 GB")
    }

    @Test func formatsTerabytes() {
        #expect(Int64(1_099_511_627_776).formattedFileSize == "1.0 TB")
    }
}
