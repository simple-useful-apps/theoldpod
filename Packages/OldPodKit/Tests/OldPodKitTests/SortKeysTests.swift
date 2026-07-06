import Domain
import Testing

struct SortKeysTests {
    @Test func stripsLeadingArticleCaseInsensitively() {
        #expect(SortKeys.articleStripped("The Beatles") == "Beatles")
        #expect(SortKeys.articleStripped("the who") == "who")
        #expect(SortKeys.articleStripped("THE Clash") == "Clash")
    }

    @Test func leavesNamesWithoutArticleAlone() {
        #expect(SortKeys.articleStripped("Pink Floyd") == "Pink Floyd")
        #expect(SortKeys.articleStripped("Them") == "Them")
    }

    @Test func isEmptySafe() {
        #expect(SortKeys.articleStripped("") == "")
    }
}
