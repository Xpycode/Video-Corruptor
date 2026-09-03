# Controlled synthetic MXF source kit

`op1a-project-owned-v1.mxf.hex` and `op-atom-project-owned-v1.mxf.hex` are tiny,
deterministic KLV streams used where an end-to-end file structure is required. Tests decode the
ASCII hex to the actual MXF bytes. Arithmetic, malformed framing, and large payload buffers remain
generated in tests and are not checked in as binaries.

## Provenance and rights

Both sources were generated specifically for VideoCorruptor by `SyntheticMXFBuilder.swift`. They
contain invented byte patterns only, no third-party essence, metadata, trademarks, or identifying
production information. The project dedicates these fixture bytes to the public domain under
CC0-1.0.

| Fixture | Profile | Provenance | Rights disposition | `repositoryAllowed` |
| --- | --- | --- | --- | --- |
| `op1a-project-owned-v1.mxf.hex` | OP1a | In-repository deterministic builder | `project-owned-cc0` | `true` |
| `op-atom-project-owned-v1.mxf.hex` | OP-Atom | In-repository deterministic builder | `project-owned-cc0` | `true` |

The test inventory maps `repositoryAllowed` to the manifest model's `repositoryEligible` property
and combines it with redistribution permission. Derived mutations must reuse the complete source
rights record; corruption never upgrades an external or restricted source to publishable.

SHA-256 values are computed over decoded MXF bytes (not over the textual hex files) and pinned in
`SyntheticMXFSourceKit` tests.
