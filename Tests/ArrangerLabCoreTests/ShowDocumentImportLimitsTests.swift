import ArrangerLabCore
import Testing

struct ShowDocumentImportLimitsTests {
    private let limits = ShowDocumentImportLimits(
        maximumFileBytes: 100,
        maximumPageCount: 3,
        maximumExtractedTextBytes: 50
    )

    @Test func acceptsValuesAtEveryBoundary() throws {
        try limits.validate(fileBytes: 100)
        try limits.validate(pageCount: 3)
        try limits.validate(extractedTextBytes: 50)
    }

    @Test func rejectsOversizedFiles() {
        #expect(throws: ShowDocumentImportLimitError.fileTooLarge(maximumBytes: 100)) {
            try limits.validate(fileBytes: 101)
        }
    }

    @Test func rejectsTooManyPages() {
        #expect(throws: ShowDocumentImportLimitError.tooManyPages(maximum: 3)) {
            try limits.validate(pageCount: 4)
        }
    }

    @Test func rejectsExcessiveExtractedText() {
        #expect(throws: ShowDocumentImportLimitError.extractedTextTooLarge(maximumBytes: 50)) {
            try limits.validate(extractedTextBytes: 51)
        }
    }
}
