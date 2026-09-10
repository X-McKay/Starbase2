# Scoped GitHub observation · 2026-09-10

Status: GitHub credential deployed and bounded manual repository observation
completed. GitHub inference and recurring work remain disabled.

The user created `starbase2-readonly` through GitHub's fine-grained credential
flow. The saved settings page verified one selected private repository,
`X-McKay/Starbase2`, read-only Contents/Metadata/Pull requests, no account
permissions, and expiry on2026-12-09. GitHub inherently permits public repository
reads as well. [Credential metadata](credential-metadata.json) contains no secret.
The token was encrypted directly from browser memory into Kubani SOPS YAML;
no plaintext credential file or token output was created.

Only runtime receives the credential mount. Core/init do not. The configured
target `starbase2-github` uses `github_repository`; its inference flag is false.
No automatic repository watch or recurring duty is added. Existing Watchkeeper,
LLM, image digests and other disabled capabilities are preserved.

The adapter performs bounded GET requests against GitHub's API, verifies PR
head/base and Git blob identities, and retains masked changed Python source and
structured findings in Core. Masking is best effort; this is trusted private
repository data access, not proof that retained material cannot contain secrets.
The LLM receives none of this repository data in this configuration. No comment,
approval, merge, checkout or candidate-code execution is performed.

Credential renewal owner: Al/operator. Before2026-12-09, replace the credential
with the same scope through SOPS/GitOps, verify one bounded observation, and then
retire the old credential. Expiry must remain an explicit failed/unavailable
observation, not invented success. Do not reuse an administrator token.


Network routing is scoped to the worker-verified GitHub API address, pinned only
in the Starbase2 pod while retaining HTTPS hostname verification. This avoids
broad internet egress but couples availability to that address: re-resolve,
validate, and update the GitOps pin if GitHub changes it. There is no automatic
fallback to wider egress. DNS changes do not silently expand the allowlist.


## Deployed result

[Kubani PR148](https://github.com/X-McKay/kubani/pull/148), merge
`1d1b6a4d69218059e2cd9fc9268bb47c3e902124`, passed local validation, repository
hooks and all three CI checks. Flux applied the revision. The
[live pod](live-pod.json) is healthy with the same qualified source028f42a image
pair and both existing capabilities preserved. [Actual worker checks](worker-api-status.json)
verified TLS and authenticated repository/open-PR GET access using the mounted
credential; no token or private response body was emitted.

The [Core/Temporal observation](observation-proof.json) completed against
X-McKay/Starbase2 and retained a non-synthetic snapshot with zero open PRs. The
list was complete. No PR files were fetched in this observation, no model call
was made, and no finding was produced. This proves authenticated repository
observation and empty-result handling, not review quality or live changed-file
coverage. A future open PR can exercise head/blob provenance and Python analysis;
unsupported languages and bounded coverage remain explicit limitations.

No recurring duty or repository watch was created. Manual GitHub observation,
scoped Watchkeeper observation and synthetic LLM inference are enabled. Memory
recall, repairs and legacy execution remain disabled. The current data remains
disposable pilot evidence; this does not qualify durable production recovery.
