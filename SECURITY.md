# Security Policy

## Supported versions

Security fixes are made on the current `main` branch. Tagged local-use builds
may not receive backports.

## Report a vulnerability privately

Do not open a public issue for a suspected vulnerability. Use the repository's
GitHub **Security** tab and select **Report a vulnerability** to start a private
security advisory. Include:

- the affected commit or version;
- impact and prerequisites;
- minimal reproduction steps or a proof of concept;
- suggested remediation, if known.

Remove credentials, copyrighted repertoire, personal captures and device
identifiers. Please allow maintainers time to reproduce and address the issue
before public disclosure.

## Security boundaries

Arranger Lab interacts with MIDI hardware, local files, PDFs and audio input.
The project treats those as trust boundaries:

- Operational MIDI APIs accept Verified mappings only.
- Arbitrary SysEx requires expiring Expert mode and a second confirmation.
- Panic runs on stop, disconnect, replay completion, failure and app close.
- PDF imports are bounded by file size, page count and extracted-text size and
  are processed away from the main UI executor.
- The KORG media inspector is read-only, rejects firmware and backup inputs,
  does not follow symbolic links and exports relative metadata only.
- Runtime captures and imported charts are local Application Support data and
  are never intended for source control.

Build the app from reviewed source or use a trusted release. Current local
builds are ad-hoc signed and are not notarized.
