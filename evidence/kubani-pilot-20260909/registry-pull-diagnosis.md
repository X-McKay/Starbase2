# Registry pull diagnosis, 2026-09-09

Read-only inspection after the Starbase2 migration ImagePullBackOff:

- Live registry Service remains `10.43.150.95:5000`, selector `app.kubernetes.io/name: registry`.
- Ready endpoint is `10.42.3.124:5000`, pod `registry-588c5cddbf-4965h` on strix.
- rig0 `/etc/rancher/k3s/registries.yaml` mirrors use the correct Service IP. No `configs` hosts were present; no credentials were read.
- rig0 GET `/v2/` against both ClusterIP and pod IP immediately fails connection refused. External HTTPS registry `/v2/` returns401, showing the ingress path is available.
- Registry policies created2026-09-09T03:30:04Z allow same namespace and Traefik ingress, plus default deny. They omit host image-pull traffic.
- rig0 route selects flannel.1 source10.42.1.0.
- Header-only tcpdump on strix flannel.1, filtered to the exact source/destination/port, observed the generated read-only probe:
  `08:12:00.900499 IP 10.42.1.0.12128 > 10.42.3.124.5000: tcp 0`
  Capture stopped at its12-second bound after one packet; no payloads captured.
- Registry pod chain `KUBE-POD-FW-RB4UTKMRKIY46XTU` allows its local node, then traverses defaultdeny, DNS, Traefik and same-namespace policies; unmatched packets are REJECTed with icmp-port-unreachable.

All node host interface addresses verified with `ip -j -4 address show flannel.1`:

| Node | Host flannel source |
|---|---|
| sparky |10.42.0.0/32|
| rig0 |10.42.1.0/32|
| asio |10.42.2.0/32|
| strix |10.42.3.0/32|

Minimal fix: additive GitOps NetworkPolicy in namespace registry, selecting only registry pods, permitting ingress TCP5000 from these four exact host /32 ipBlocks. Update the address inventory if node podCIDRs change. No node configuration change, service address change, credential rotation or restart is indicated. This investigation made no cluster changes.
