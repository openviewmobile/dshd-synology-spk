# DeepSeek Harness SPK source

This directory is published by GitHub Pages at:

- https://openviewmobile.github.io/dshd-synology-spk/spk-repo/
- https://openviewmobile.github.io/dshd-synology-spk/spk-repo/x86_64.json
- https://openviewmobile.github.io/dshd-synology-spk/spk-repo/armv8.json

The two JSON files are **architecture-specific static package indexes**. The
direct SPK install remains the supported path. Static package sources are
experimental because Synology Package Center normally queries a dynamic
repository API; the static files only work if DSM accepts the JSON response
without server-side architecture filtering.

## Regenerate

The files were generated from the v0.4.0 release metadata. Rebuild them when a
new release changes the asset names, sizes, or checksums. Do not advertise a
source URL until the JSON file and the linked SPK have both been tested on DSM.

The static index does not provide MD5 values; Package Center may require them
for verification. Use direct SPK installation if Package Center rejects the
source.
