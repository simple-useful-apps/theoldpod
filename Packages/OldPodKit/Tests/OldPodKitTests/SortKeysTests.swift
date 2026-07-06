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

    @Test func doesNotStripAWordThatMerelyStartsWithThe() {
        // "The " (with a trailing space) is the only match; "Theory" must
        // not be mistaken for an article followed by "ory of a Deadman".
        #expect(SortKeys.articleStripped("Theory of a Deadman") == "Theory of a Deadman")
    }

    @Test func isEmptySafe() {
        #expect(SortKeys.articleStripped("") == "")
    }

    @Test func nameThatIsExactlyTheArticleIsUnchanged() {
        // "The" alone has no trailing space, so it doesn't match the "The "
        // prefix and is returned as-is rather than stripped to "".
        #expect(SortKeys.articleStripped("The") == "The")
    }
}
