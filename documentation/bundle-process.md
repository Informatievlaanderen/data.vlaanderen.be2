

When a CI run starts, bundling is executed as a dedicated job in the main CircleCI workflow.
The process is designed to collect publication assets into a stable resources directory per publication point.

High-level flow:

1. CI checks out and prepares publication point workspaces.
2. Artefact generators run (context, RDF, SHACL, Swagger, and others).
3. The bundle step runs and aggregates generated + external + manual bundle assets.
4. Bundled assets are written into the generated publication tree.
5. The generated repository receives the final result in the create-artifact step.

## Bundle entrypoint behavior

The script `scripts/render-details4.sh` has a dedicated `bundle` mode.

When mode is `bundle`, it immediately calls:

- `scripts/copy_resources_to_urlref.sh <config-dir> /tmp/workspace/target /tmp/workspace`

## Input model used by bundling

Per publication point, these fields are relevant:

- `bundle`: boolean flag to enable or disable bundling.
- `bundleDirectory`: optional path in the thema repo checkout to copy additional files from.

## What is copied for bundle=true

For each publication point with `bundle=true`, the script creates:

- `<generated>/<urlref>/resources`

Then it copies, when available:

1. Generated artefact directories from `<generated>/<urlref>`:
- `context`
- `shacl`
- `rdf`
- `swagger`

2. Optional manual bundle directory from the thema checkout:
- Source: `<OSLOthemarepo>/<bundleDirectory>`
- Destination: `<generated>/<urlref>/resources`

3. External resources discovered from intermediate JSON-LD reports:
- Source reports: `/tmp/workspace/report4/<urlref>/all-*.jsonld`
- Extracted field: `assignedURI`
- Destination: `<generated>/<urlref>/resources/ontologies`

## External ontology fetching logic

External resource retrieval is implemented in `scripts/copy_resources_to_urlref.sh` with helper `scripts/fetch_external_rdf.js`.

Technical behavior:

1. URLs are normalized to namespace roots (with special handling for `schema.org`, fragment URIs, and `/ns` paths).
2. Duplicate URLs are de-duplicated per publication point.
3. Primary fetch path uses `rdf-dereference` in Node.js and writes RDF serialization.
4. Fallback fetch path uses `curl` to store raw document content when RDF dereferencing fails.
5. Failed URLs are tracked in:
- `<generated>/<urlref>/resources/ontologies/.failed_external_sources`

## Behavior for bundle=false

If `bundle` is not true, bundling is disabled for that publication point.

## Reporting

For every bundled publication point, a report is written to:

- `/tmp/workspace/report4/<urlref>/bundle.report.md`

Report content includes:

- Informational line when resources were copied.
- Error lines for each failed external source fetch.

## Failure conditions

The bundling step fails the job when one or more of these conditions occur:

1. External resource fetch failures are recorded in `.failed_external_sources`.
2. `bundle=true` but no resources were copied at all.

If any failure is detected, `copy_resources_to_urlref.sh` exits non-zero.
Because `render-details4.sh` runs bundling in direct mode, this non-zero exit propagates to CI and fails the `bundle-release` job.

## Runtime dependencies

Bundling relies on:

- `jq`
- `curl`
- `node`
- npm-installable package `rdf-dereference` (installed at runtime in `/tmp/rdf-dereference-modules`)

## Output in generated repository

After bundling and subsequent workflow steps:

- Files under `/tmp/workspace/target/<urlref>/resources` are copied to the generated repository root path `<urlref>/resources` during `create-artifact`.
- Bundle reports are included under `report4/.../bundle.report.md` in the generated repository reporting tree.

## Operational notes

- Bundling is publication-point specific and controlled entirely by publication metadata (`bundle`, `bundleDirectory`).
- External dependencies are frozen into the publication output when fetch succeeds, improving long-term reproducibility.
- Fetch failures are blocking by design, so unresolved external sources prevent publication of incomplete bundles.
