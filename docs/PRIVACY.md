# Publication privacy review

The public inventory contains authored Lua code, portable build scripts, regression fixtures, dependency pins, documentation and reviewed PNG artwork. Runtime logs, process captures, screenshots, profiles, memory dumps, extracted native code/game resources, compiler checkouts and build caches are excluded.

The technical documentation describes the implementation without personal paths, process IDs, exact session chronology or links into private research. Geometry fixtures retain native numeric expectations for rounding checks, but their ownership addresses and ignored-unit identifiers are synthetic. They contain no account, player, machine or network identity.

`scripts/privacy_audit.py` checks the explicit source allowlist and installable ZIP for home/network-share paths, local user/machine identifiers, contact/account patterns, network addresses, private keys, common credentials and process-session labels. It scans UTF-8 and both UTF-16 byte orders. Optional Git checks cover tracked/untracked inventory, staged bytes and reachable source history, including commit identities. Public GitHub noreply addresses are permitted commit metadata; private contact details are not.

Only image-critical PNG chunks are retained. Artwork keeps its visible AI-development disclosure. ZIP entries have fixed timestamps and file permissions, no comments or extra fields; Lua bytecode is stripped. Reports contain relative filenames, categories and hashes, never matched sensitive values.

Public project/dependency names, loader resource identifiers, module hashes, relative virtual addresses, synthetic addresses, build identifiers and the manager GUID are intentional compatibility or technical data. They are not account or machine identifiers.

The initial automated scan and manual review found no personal-data patterns in the existing source history; no history rewrite is needed. The surrounding private workspace is outside this repository and outside the publication inventory. Pattern checks cannot prove the absence of every conceivable identifying value; the report records their exact scope.
