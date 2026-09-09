# Starbase2 Kubani namespace and naming guards

Local configuration qualification; no cluster was queried or changed.

The renderer now rejects default/system/legacy dependency namespaces, overlap
with the application namespace, another installation's queue, and application
images outside the Starbase2 repository paths. The build input validator requires
a registry path ending in `/starbase2`. Existing runtime executable, module and
environment interfaces remain compatible with the qualified images.

`before.log` preserves nine reproduced configuration cases that were incorrectly
accepted. After correction, all 49 focused deployment/build tests passed.
`python-suite.log` records all 98 Python tests passing, with one existing
third-party Pydantic deprecation warning. Focused Ruff and type checks passed;
a nullable-body diagnostic in the new test fake was corrected with an explicit
string assertion. Documentation validation passed.

Resource inventory tests cover application resources, the cluster-scoped Namespace,
the two narrowly selected provider-side NetworkPolicies, and newly installed
Secrets. See [deployment ownership](../../docs/deployment.md#starbase2-naming-and-namespace-ownership).
The production defaults already satisfy the stricter configuration. Previously
accepted unscoped image paths must be updated and the bundle regenerated before
preflight. No image rebuild or runtime change is required for this validation.
