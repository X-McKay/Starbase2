# ADR 0007: version editable Blender sources with Git LFS

Status: accepted

Owner: Al; implementation assistant under the authorized baseline push and asset
reorganization. Date: 2026-09-07.

## Decision

Store `.blend` sources through Git LFS in this repository, starting with the
current baseline. Git LFS 3.8.0 was used for this migration. Keep runtime exports
in ordinary Git so game-only checkouts do not require downloading Blender files.
Do not rewrite prior history or upload ignored provider ledgers and credentials.

## Reason and alternatives

The selected Vanguard Blender source is 263.8 MiB, exceeding GitHub's ordinary
100 MiB file limit. Excluding it would leave the requested baseline incomplete.
An external source archive would add another storage location and restoration
procedure. LFS preserves the source path and version association within Git.
See [GitHub's limits](https://docs.github.com/en/repositories/working-with-files/managing-large-files/about-large-files-on-github).

LFS adds a client dependency and account storage/bandwidth usage. No additional
paid plan is purchased. Original provider downloads remain local dependencies;
this does not certify that every paid-source rebuild works from a fresh clone.

## Rollout and recovery

Install Git LFS, run `git lfs install --local`, then `git lfs pull` to hydrate
editable sources after cloning. CI jobs that need Blender sources must enable
LFS checkout; current game checks use committed runtime exports. Validate pointer
integrity and remote upload on the baseline push. Old Git revisions remain
unchanged. Revisit storage when quotas or collaboration needs make LFS unsuitable;
export hydrated files and their hashes before changing storage providers.
