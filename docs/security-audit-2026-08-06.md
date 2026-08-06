# Security audit — 2026-08-06

## Scope

A standard whole-repository static review covered all 91 files at commit
`052bf12292715c3072a6544460c0ed7d95f442a4`, including Swift targets, tests,
resources, scripts, documentation and binary assets. The review focused on
untrusted file imports, MIDI/device boundaries, local persistence, build and
release integrity, secrets and public-repository exposure.

The baseline test suite passed 51 tests in 10 suites. The sanitized working tree
subsequently passed 55 tests in 11 suites, all 217 integration-harness checks and
the signed release-build verification gate.

## Result

One low-severity, high-confidence issue was identified: PDF import performed
unbounded file loading, hashing and all-page text extraction from a MainActor
task. A large user-selected document could therefore freeze or exhaust the
local app (CWE-400).

The remediation now:

- rejects files above 32 MiB before PDF parsing when metadata is available and
  validates the loaded byte count as a second boundary;
- rejects documents above 256 pages;
- caps cumulative extracted UTF-8 text at 4 MiB;
- checks task cancellation while extracting pages;
- runs PDFKit parsing in a detached user-initiated task;
- returns localized errors and includes boundary regression tests.

No other reportable runtime vulnerabilities were found in the reviewed scope.
In particular, the review found no issue in `.arrlab` path containment, bounded
MIDI decoding and identity authorization, the read-only KORG media inspector,
audio permission and buffering, the Draft/Verified driver boundary or the fixed
release scripts.

## Publication review

The security review found no high-confidence credential pattern in the current
tree or Git history, and GitHub secret-scanning alerts were empty at review time.
Publication governance was handled separately: personal repertoire, lyrics,
source-derived catalogs and UI screenshots were removed from the sanitized
snapshot and preserved only in a local ignored backup.

Those removed files existed in the pre-sanitization public Git history. That
history was preserved in a local ignored bundle before the public branch and
tag replacement; it is not part of the sanitized root snapshot. The sanitized
snapshot is published under the MIT License.

## Limitations

- No destructive memory-exhaustion proof of concept was run.
- The audit was static plus local test/build verification; it was not an
  independent penetration test or legal review.
- Manufacturer catalog and trademark boundaries are documented in
  [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md), not adjudicated here.
