# Update Feed

`stable.json` is the fixed update endpoint used by both managers. Its detached
Ed25519 signature is stored in `stable.json.sig`. The public key is committed as
`public-key.json`; the matching private JWK stays outside Git and is supplied to
release automation through `CODEX_UPDATE_PRIVATE_KEY_JWK`.

`themes.json` is an independently versioned catalog. Every entry points to a ZIP
containing one schema 2 theme directory and includes its version, minimum manager
version, SHA-256 digest, size, and download URL. Its signature is stored in
`themes.json.sig`.

The manager accepts only HTTPS assets, exact semantic versions, lowercase
SHA-256 digests, bounded file sizes, valid signatures, and the existing strict
theme-package validator. Update metadata never supplies executable arguments.

## Signing key setup

The generated private key is stored locally as `.update-private-key.jwk` and is
ignored by Git. Back it up in a password manager or encrypted secret store, then
configure the repository once:

```bash
gh secret set CODEX_UPDATE_PRIVATE_KEY_JWK < .update-private-key.jwk
```

The Release workflow reads this secret only while generating feed signatures.
Losing the key requires a manager release that embeds a newly generated public
key, so keep the backup separate from the repository checkout.

Generate a release feed after the platform packages have been built:

```bash
node script/update-feed.mjs generate \
  --version 1.7.2 \
  --mac-asset release/Codex-Skin-Manager-1.7.2.dmg \
  --windows-asset release/Codex-Skin-Manager-Setup-1.7.2.exe \
  --private-key .update-private-key.jwk
```

Validate committed feeds and signatures:

```bash
node script/update-feed.mjs validate
```

Package and publish a new online theme entry before uploading its ZIP:

```bash
node script/update-feed.mjs add-theme \
  --theme themes/THEME_ID \
  --theme-version 1 \
  --minimum-app 1.7.2 \
  --url THEME_ZIP_URL \
  --output release/THEME_ID-1.zip \
  --private-key .update-private-key.jwk
```

This increments `catalogVersion`, replaces the matching theme entry, recalculates
the catalog digest in `stable.json`, and signs both files.
