# Offline infrastructure-only stopped candidate

Not applied, activated, committed or pushed. This is a concrete review candidate,
not an image-qualified release. Context is `default`; current audit found no
`starbase2-prod` namespace or Flux owner. Kubani main removed the earlier inactive
draft, so any installation needs a fresh reviewed GitOps change.

Five resources only:
- Namespace `starbase2-prod` with restricted pod-security admission.
- ServiceAccount `starbase2` with automatic API-token mounting disabled.
- Application NetworkPolicy denying ingress and permitting DNS, PostgreSQL5432
  in `database`, and Temporal7233 in `temporal`.
- PostgreSQL ingress allowance in `database`, limited to selected PostgreSQL pods
  and exact Starbase2 namespace/application labels.
- Temporal ingress allowance in `temporal`, limited to frontend pods and exact
  Starbase2 namespace/application labels.

The objects are selected unchanged from the current deployment renderer. Its
existing historical configuration supplied names/dependencies; all workload and
image-bearing objects were discarded before writing this candidate. There is no
Deployment, Job, Secret, image reference or placeholder digest in this bundle.
No application process can start from these five resources alone. The manifest
records the renderer and file hashes; `rendered.yaml` is local kustomize output.

Validation: `kubectl kustomize .local/starbase2-stopped-preparation` exited0.
This validates local composition only. No server dry-run or connectivity probe
was performed; dependency readiness does not prove credential access or working
network policy. Current schema/image qualification, dependency identities,
operator-managed secrets, migration, and fresh GitOps ownership remain separate
steps. A real GitHub pilot also needs reviewed field capability and provider
egress/credential configuration; this dependency-only policy does not permit it.

Review the exact selector/port boundaries, namespace ownership and single Flux
owner before any authorized installation. Do not add old draft manifests or
activate admission while preparing infrastructure.
