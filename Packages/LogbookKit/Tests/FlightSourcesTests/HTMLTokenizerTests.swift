import Testing

@testable import FlightSources

@Suite
struct `HTML tokenizer` {
  @Test
  func `lowercases names and reads quoted, bare and valueless attributes`() {
    let tokens = HTMLTokenizer.tokens(in: #"<TD Data-Key="a&amp;b" id=x4 hidden class='c d'>"#)

    #expect(
      tokens == [
        .start(
          name: "td",
          attributes: ["data-key": "a&b", "id": "x4", "hidden": "", "class": "c d"]
        )
      ]
    )
  }

  @Test
  func `skips comments, doctypes and the contents of script and style`() {
    let html =
      "<!DOCTYPE html><!-- <b>hidden</b> --><STYLE>p > a { }</STYLE>"
      + #"<script>if (a < b) { x = "<i>" }</script><p>shown</p>"#

    #expect(
      HTMLTokenizer.tokens(in: html) == [
        .start(name: "style", attributes: [:]),
        .start(name: "script", attributes: [:]),
        .start(name: "p", attributes: [:]), .text("shown"), .end(name: "p")
      ]
    )
  }

  @Test
  func `treats a less-than sign that doesn't open a tag as text`() {
    #expect(HTMLTokenizer.tokens(in: "1 < 2 <3") == [.text("1 "), .text("< 2 "), .text("<3")])
  }

  @Test
  func `tolerates self-closing and unterminated tags`() {
    #expect(
      HTMLTokenizer.tokens(in: "<br/><a href=x") == [
        .start(name: "br", attributes: [:]), .start(name: "a", attributes: ["href": "x"])
      ]
    )
  }

  @Test(arguments: [
    ("a &amp; b &lt;c&gt; &quot;d&quot; &apos;e&apos;", #"a & b <c> "d" 'e'"#),
    ("&#65;&#x42;&#x1F600;", "AB\u{1F600}"),
    ("&bogus; &#xD800; & plain", "&bogus; &#xD800; & plain")
  ])
  func `decodes character references and leaves unknown ones alone`(
    _ encoded: String,
    _ decoded: String
  ) {
    #expect(HTMLTokenizer.decode(encoded) == decoded)
  }
}
