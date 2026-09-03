# MXF corpus applicability

The registry contains all 45 cases required by the approved corpus specification. A registered
case is not a promise that arbitrary MXF bytes can be mutated safely: applicability is decided
from inspected structure and caller-supplied profile declarations. An unmet prerequisite returns
`notApplicable` with a capability reason; offsets are never inferred from a profile name.

## Controlled source matrix

The project-owned OP1a and OP-Atom sources contain three verified partition packs and one or two
small essence KLVs. They intentionally contain no primer/local metadata set, index-table segment,
or Random Index Pack. Their BER fields are short form.

| Family | Cases | OP1a | OP-Atom | Structural prerequisite |
|---|---:|---|---|---|
| BER framing | 8 | 5 applicable, 3 not applicable | 5 applicable, 3 not applicable | A compatible BER width; long-form BER for header/overflow cases; an explicit required-element declaration for zero-value |
| Partition | 8 | 7 applicable, footer-missing not applicable | 7 applicable, footer-missing not applicable | Verified partition packs and valid baseline link fields; footer-missing additionally requires a dedicated implementation distinct from missing-structure truncation |
| Count/allocation | 6 | 0 applicable | 0 applicable | Declared local-set/index keys, primer tags, field offsets, widths, and valid baseline relationships |
| Missing structure | 5 | header/footer applicable; RIP/index/metadata not applicable | header/footer applicable; RIP/index/metadata not applicable | Typed profile policy plus a verified structure key; required metadata must be declared as required by that profile |
| Boundary truncation | 12 | 5 applicable, 7 not applicable | 5 applicable, 7 not applicable | The exact boundary must exist; these sources have keys, values, adjacent KLVs, and partition fixed fields, but no long BER, local set, index array, or RIP |
| Field-aware index | 6 | 0 applicable | 0 applicable | Explicit index declaration, complete six-field schema, entry offsets, and verified essence/SID relationships |

For each controlled source, 19 of 45 registered cases are applicable and 26 are explicitly
`notApplicable`. Both profiles have the same structural coverage; their declared missing-footer
policy differs.

The exact result is evaluated by code rather than taken from this summary. In particular, a BER
case may reject a candidate when its existing encoding cannot accept a same-width edit. The
registry's exact ID-set test is the authoritative guard against a family or fixture disappearing.

## Deliberate `notApplicable` cases

- Count and index cases are not attempted on either controlled source. Neither source contains the
  declared local-set/index structures those mutations require.
- RIP removal and RIP truncation cases are not attempted because neither source contains a RIP.
- Missing required metadata is not attempted without a profile-owned required-set declaration.
- Long-form BER truncations and overflow are not attempted against short-form BER fields.
- Required-zero BER is not attempted without a declaration identifying a required, nonempty key.
- The three local-set/index boundary truncations remain registered but unavailable on these
  sources; no byte offset is guessed.
- `partition.footerMissing.v1` remains registered separately from
  `missing.footerPartition.v1`. The former changes the footer reference field; the latter removes
  the verified footer and trailing bytes. The current partition family has no safe implementation
  of the former and reports that explicitly.

## Source policy

OP1a treats a removed footer as `missingFooter`. OP-Atom permits the declared footer fallback and
reports a warning. Both controlled profiles permit a missing RIP with a warning when a verified
RIP-bearing source is supplied. These policies affect expected outcomes only; they never create
structural applicability.
