# The LogTen Assistant Help book

`LogTen Assistant.help` is the Apple Help book the app ships. It is one book, in one language
folder, staged into the app at build time.

```text
LogTen Assistant.help/Contents/
  Info.plist                        book metadata; identifier stamped at build
  Resources/
    help-icon.png                   HPDBookIconPath, reached as ../help-icon.png
    en.lproj/
      index.html                    the landing page and full table of contents
      *.html                        one article per topic
      logten-assistant-help.css
```

## How it gets into the app

The book sits outside every synchronized group on purpose. Xcode has no file type for the `.help`
extension, so a synchronized group descends into the bundle and treats each page as a loose
resource, colliding the book's own `Info.plist` with the target's. Staging it with a script phase
is what keeps the wrapper intact.

That phase is **Build Help Book**, on the app target, and it runs `Scripts/build-help-book.sh`:

```sh
Scripts/build-help-book.sh \
  "Help/LogTen Assistant.help" \
  "$TARGET_BUILD_DIR/$UNLOCALIZED_RESOURCES_FOLDER_PATH" \
  codes.tim.LogTenAssistant.help \
  "$DERIVED_FILE_DIR" \
  "LogTen Assistant/Support/HelpAnchor.swift"
```

The book is copied into the app's `Contents/Resources`, the copy's `CFBundleIdentifier` is stamped,
and `hiutil` builds the CoreSpotlight search index each localization ships. The app's own
`Info.plist` points at the book through `LogTen Assistant-Info.plist`, which holds
`CFBundleHelpBookFolder` and `CFBundleHelpBookName`; Xcode's generated plist cannot carry them.
The identifier in `CFBundleHelpBookName`, the one passed to the script, and the one in the book's
`Info.plist` are all `codes.tim.LogTenAssistant.help`.

## Writing a page

A new page needs `<meta name="robots" content="index, anchor">` in its `<head>`, plus an
`<a name="…">` on anything `HelpLink(anchor:)` should be able to open. The anchors the interface
asks for are named once in `LogTen Assistant/Support/HelpAnchor.swift`, and the build **fails**
when that enum names one the book doesn't define. A misspelled anchor doesn't error at runtime; it
quietly opens the book's first page instead of the topic, so the build is the only place to catch
it.

`hiutil` records one target per page, so an anchor resolves exactly only when it is the page's own
anchor. A second anchor part-way down a page is reachable by an in-page `href="#…"`, but a
`HelpLink` pointing at it lands at the top of the page instead. If the interface needs to land on
a topic, give that topic its own page. Each page's file name, its anchor and its `HelpAnchor` raw
value are the same string.

Menu paths and control labels are written exactly as the app shows them, with `&#9656;` between
menu levels and `<strong>` around every label. When a menu title or button changes in the app,
search the book for the old label.

For styling and copy alone, skip the build: the pages are ordinary HTML and
`open "Help/LogTen Assistant.help/Contents/Resources/en.lproj/index.html"` renders them in a
browser. Only anchors, search, and the icon need a real book.

## Reading it the way a user does

The viewer is **Tips.app**. The book can be opened without going through the app at all:

```sh
open "help:openbook=codes.tim.LogTenAssistant.help"
open "help:anchor=applying-fixes%20bookID=codes.tim.LogTenAssistant.help"
```

## When an edit doesn't show up

`helpd` does not read the book out of the app. It copies it into its own group container the first
time it sees it, and serves the copy ever after, under a name keyed on the app's
`CFBundleShortVersionString`. While the marketing version stays put, every rebuild is ignored. An
edit that never shows up, a page stuck without its images, or a Help menu landing on the generic
macOS Tips page all have this cause.

`hiutil -P` does not clear that copy. `Scripts/purge-help-cache.sh` drops both it and helpd's own
registrations:

```sh
Scripts/purge-help-cache.sh
```

Then open the book at its root before clicking any help button. An anchor resolves only once
`helpd` has registered the book, and until it has, every `HelpLink` reports "The selected content
is currently unavailable". Opening the book at its root registers it for a build run from
DerivedData; a copy in `/Applications` registers itself within a minute of the first request.

## Screenshots

The book has no screenshots yet. When they are added, put them in `en.lproj/images` as WebP, a
light and a `-dark` variant of each, and reference the pair from the page.
