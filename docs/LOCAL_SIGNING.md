# Local certificate signing

SnapMark can use a code-signing certificate on your Mac instead of its default
ad-hoc signature. This gives local rebuilds a stable cryptographic identity.
Keep the certificate's private key: creating a replacement certificate changes
the app's identity and may require granting Screen Recording permission again.

## Create the identity

1. Open **Keychain Access** and choose **Keychain Access → Certificate
   Assistant → Create a Certificate**.
2. Name it **SnapMark Local Signing**, choose **Self Signed Root** as the
   identity type and **Code Signing** as the certificate type.
3. Save it in your login keychain. Do not export or commit its private key.

List available signing identities:

```sh
security find-identity -v -p codesigning
```

Copy the 40-character hexadecimal identity hash for **SnapMark Local
Signing**. Using the hash avoids choosing another certificate with the same
name.

## Build and install on your Mac

Run these commands in the SnapMark checkout, replacing the example hash with
your own:

```sh
SNAPMARK_SIGNING_IDENTITY=YOUR_40_CHARACTER_IDENTITY_HASH ./install.sh --source
codesign --verify --deep --strict --verbose=2 "$HOME/Applications/SnapMark.app"
codesign -dvv "$HOME/Applications/SnapMark.app" 2>&1
```

The build script signs the completed app bundle. Without
`SNAPMARK_SIGNING_IDENTITY`, it retains the ad-hoc signing behavior. The
certificate-backed signature uses macOS's certificate-derived designated
requirement; the ad-hoc build retains SnapMark's explicit identifier
requirement. Switching between them can trigger one new Screen Recording
permission prompt.

`./install.sh --source` builds and installs directly from your checkout, so
your own build does not arrive as a browser-quarantined download. The
certificate is useful for verifying that future builds were signed with the
same private key. It is not an Apple Developer ID certificate.

## Downloaded apps and Gatekeeper

Adding this self-signed certificate to Keychain, even with **Always Trust**,
does not make Gatekeeper automatically accept downloaded apps signed with it.
Current macOS requires an Apple-issued Developer ID signature and
notarization for that default download experience. There is no supported
system setting to allow every downloaded app from one self-signed signer.

For an app you built yourself but downloaded later, first verify its signature
and origin, then use **System Settings → Privacy & Security → Open Anyway** if
macOS blocks it. That creates an exception for the app you approved. Do not
disable Gatekeeper globally.

GitHub release builds remain ad-hoc signed because the release workflow does
not have your private key. If you later join the Apple Developer Program, use
a **Developer ID Application** certificate, hardened runtime, secure
timestamp, and notarization for public releases. Do not upload your local
certificate's private key to the repository.
