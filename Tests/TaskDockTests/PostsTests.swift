import XCTest
@testable import TaskDock

final class PostsTests: XCTestCase {
    private func post(_ id: String = "20", text: String = "", partial: Bool = false, note: String = "") -> Post {
        Post(id: id, url: Post.canonical(handle: "jack", id: id), author: "jack", handle: "jack", text: text,
             postedAt: nil, savedAt: Date(timeIntervalSince1970: 0), note: note, partial: partial)
    }

    func testRefReadsAnyPostLink() {
        XCTAssertEqual(Post.ref("https://x.com/jack/status/20")?.id, "20")
        XCTAssertEqual(Post.ref("https://twitter.com/Jack_1/status/123/photo/1?s=20")?.handle, "Jack_1")
        XCTAssertEqual(Post.ref("https://mobile.x.com/jack/status/20?t=abc")?.id, "20")
        XCTAssertNil(Post.ref("https://x.com/jack"))
        XCTAssertNil(Post.ref("https://evil.example/jack/status/20"))
        XCTAssertEqual(Post.canonical(handle: "jack", id: "20"), "https://x.com/jack/status/20")
    }

    func testMergeKeepsOneEntryAndTheBestText() {
        let full = post(text: "the whole post", note: "my take")
        // Saving again from a timeline that cut the text off keeps the full text and the note.
        let again = Post.merge(full, post(text: "the whole…", partial: true), note: nil)
        XCTAssertEqual(again.text, "the whole post")
        XCTAssertFalse(again.partial)
        XCTAssertEqual(again.note, "my take")
        // A link-only save gets its text filled in later.
        let filled = Post.merge(post(partial: true), post(text: "now known"), note: nil)
        XCTAssertEqual(filled.text, "now known")
        XCTAssertFalse(filled.partial)
        // A note sent after saving replaces the old one; no note leaves it alone.
        XCTAssertEqual(Post.merge(full, post(), note: "changed mind").note, "changed mind")
        XCTAssertEqual(Post.merge(nil, post(text: "new"), note: "first").note, "first")
    }

    func testInboxLinesFromTheShortcut() {
        let text = """
        https://x.com/jack/status/20 worth a paragraph
        https://x.com/jack/status/21

        not a link at all
        https://x.com/jack/status/22\tTab-separated thought
        """
        let lines = Post.inbox(text)
        XCTAssertEqual(lines.map(\.url), ["https://x.com/jack/status/20", "https://x.com/jack/status/21", "https://x.com/jack/status/22"])
        XCTAssertEqual(lines.map(\.note), ["worth a paragraph", "", "Tab-separated thought"])
    }

    func testEmbedReplyGivesTextAuthorAndDate() throws {
        let json = #"""
        {"url":"https://x.com/jack/status/20","author_name":"jack","author_url":"https://x.com/jack",
         "html":"<blockquote class=\"twitter-tweet\"><p lang=\"en\" dir=\"ltr\">just setting up my twttr<br>&amp; more &lt;3 <a href=\"https://t.co/x\">pic.twitter.com/x</a></p>&mdash; jack (@jack) <a href=\"https://x.com/jack/status/20?ref_src=twsrc%5Etfw\">March 21, 2006</a></blockquote>\n"}
        """#
        let p = try XCTUnwrap(Post.fromEmbed(Data(json.utf8), base: post(partial: true)))
        XCTAssertEqual(p.text, "just setting up my twttr\n& more <3 pic.twitter.com/x")
        XCTAssertEqual(p.author, "jack")
        XCTAssertEqual(p.handle, "jack")
        XCTAssertFalse(p.partial)
        let day = Calendar(identifier: .gregorian).dateComponents(in: TimeZone(identifier: "UTC")!, from: try XCTUnwrap(p.postedAt))
        XCTAssertEqual([day.year, day.month, day.day], [2006, 3, 21])
        XCTAssertNil(Post.fromEmbed(Data("{\"error\":\"not found\"}".utf8), base: post()))
    }

    func testMarkdownNoteQuotesEveryPostAndAppends() {
        var p = post(text: "line one\nline two", note: "compare with now")
        p.author = "Jack Dorsey"
        p.postedAt = ISO8601DateFormatter().date(from: "2006-03-21T20:50:14Z")
        let note = Post.markdown([p], title: "Posts – March 2006", existing: nil)
        XCTAssertEqual(note, """
        # Posts – March 2006

        ## Jack Dorsey (@jack) · 21 Mar 2006

        > line one
        > line two

        https://x.com/jack/status/20

        My take: compare with now

        """)
        // Pressing Start writing again that month adds to the same note, never replaces it.
        let more = Post.markdown([post("21", text: "second")], title: "Posts – March 2006", existing: note)
        XCTAssertTrue(more.hasPrefix(note))
        XCTAssertTrue(more.hasSuffix("https://x.com/jack/status/21\n\nMy take: \n"))
        XCTAssertEqual(more.components(separatedBy: "# Posts – March 2006").count, 2) // one title
    }

    func testNoteTitleIsTheMonth() {
        let d = ISO8601DateFormatter().date(from: "2026-11-09T12:00:00Z")!
        XCTAssertEqual(Post.noteTitle(d), "Posts – November 2026")
    }
}
