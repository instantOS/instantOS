# Repository key bootstrap

`instantos-signing-key.asc` is the public key exported from the vendored
`packages/instantos-keyring/instantos.gpg` in instantOS/packages. The master
fingerprint is `E5C4740F883910B29694D6BE10DA645A82CF5206`; the signing subkey is
`86D0589DC0EC55E4E5DFCE4436276C1C0A17CCD1`.

`repo.sh` embeds the same key so it still works as a standalone download. Its
`--bootstrap-key [PACMAN_CONFIG]` mode imports and locally trusts that master
in the GPGDir selected by the given configuration. It neither adds a repository
nor fetches a key. ISO builds and the standalone offline bundle downloader run
this before their first repository sync. Normal `repo.sh` invocation performs
this bootstrap before adding the repository.

Keep the embedded snapshot, instantCLI's bundled snapshots, and the ISO
verifier's subkey pin in sync when the public key changes. Key imports merge
with installed keys and preserve newer subkeys and revocations. Refresh the
signed test package fixture before its signing key expires.

Verification:

```sh
PYTHONDONTWRITEBYTECODE=1 /usr/bin/python3 -m unittest discover -s iso/tests -p test_signing.py -v
```

These tests use disposable keyrings and a small squashfs fixture, need no root
access or network, and reject missing or invalid instant package signatures
and images without their keyring initialization service. Tests require GnuPG,
pacman-conf, bsdtar, and squashfs-tools; unavailable tool sets are skipped.
