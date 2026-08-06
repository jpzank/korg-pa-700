# Contributing to Arranger Lab

Thank you for helping make arranger-keyboard tooling safer and more useful.

## Before you start

- Search existing issues before opening a new one.
- Use an issue for significant behavior or protocol changes so the evidence and
  safety implications can be discussed first.
- Keep pull requests focused. Do not combine unrelated cleanup with a feature or
  protocol mapping.
- Never commit copyrighted songs or lyrics, commercial set lists, source PDFs,
  credentials, personal captures, device serials or private contact details.

## Development setup

You need macOS 14+, Swift 5.10+ and Xcode Command Line Tools or Xcode.

```sh
bash scripts/test.sh
swift run --disable-sandbox ArrangerLabTestHarness
swift run ArrangerLabApp
```

Hardware is not required for the test suite. If you work with a keyboard, back
it up first, use a dedicated MIDI preset and keep new mappings in Draft until
their exact bytes and physical outcome are documented.

## Pull requests

1. Create a topic branch from `main`.
2. Add or update tests for behavior changes.
3. Update documentation when a workflow, safety boundary or public API changes.
4. Run `./scripts/verify.sh`.
5. Complete the pull-request template, including hardware and evidence status.

Do not describe a mapping as Verified based only on a manual, endpoint name,
MIDI output or plausible behavior. The relevant capture, device configuration
and physical confirmation must support the claim. Volume and timbre mappings
also require the audio evidence defined in [CONTEXT.md](CONTEXT.md).

## Code style

- Prefer small, explicit Swift types over hidden global state.
- Keep manufacturer-specific protocol rules inside profiles or drivers.
- Preserve raw capture data; filtering is presentation-only.
- Bound file sizes, collections and protocol frames at trust boundaries.
- Keep UI labels clear about Draft, Applied, Observed and Verified state.

## Reporting results

Include the macOS version, Swift version, instrument model and firmware when
they matter. Share the smallest sanitized fixture that reproduces the issue.
Do not upload an entire Application Support directory.

By participating, you agree to follow [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
