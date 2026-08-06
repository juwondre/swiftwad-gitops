# Networking — two planes, deliberately separated

The platform carries two kinds of traffic with opposite exposure requirements, and they must never share an entry point:

| | **Platform plane** (tooling) | **Service plane** (vendor workloads) |
|---|---|---|
| What | ArgoCD, Kargo, Grafana, Atlantis | The applications vendors ship |
| Who reaches it | Staff and vendors **on the corporate network only** | The internet, or whoever the product serves |
| Load balancer | **internal** ALB, private subnets only | **internet-facing** ALB, public subnets |
| DNS | Private hosted zone (`*.platform.<domain>`) | Public zone (`*.<domain>` or per-product) |
| WAF | Not required (no public surface) | **Required** — this is where it earns its keep |
| Ingress class | `alb-internal` | `alb-public` |

Rule: **nothing in the platform plane is ever internet-facing.** A tool that manages deployments is a control plane; exposing it publicly means the only thing between an attacker and your delivery pipeline is an OAuth flow.

---

## Platform plane

**Ingress**: every platform UI sets `alb.ingress.kubernetes.io/scheme: internal` and joins the shared `platform-internal` ingress group — one internal ALB serving `argocd`, `kargo`, and `grafana` by host header (one ALB instead of three, ~$36/month saved).

**Subnets**: the ALB lives in the private subnets. There is no route from the internet to it; a misconfigured security group cannot accidentally expose it, because no public path exists at all.

**DNS**: a **Route53 private hosted zone** for `platform.<domain>`, associated with the VPC. Records resolve only from inside the VPC or from networks that forward DNS to it. external-dns runs with `--aws-zone-type=private` and a domain filter for that zone.

**Reaching it from a laptop** — one of:
1. **VPN into the VPC** (site-to-site, or AWS Client VPN). DNS resolution over the VPN needs a **Route53 Resolver inbound endpoint** so corporate resolvers can forward `platform.<domain>` queries into the VPC.
2. **kubectl port-forward** — always works, needs only cluster access, ideal for break-glass and small teams.

**Certificates**: an ACM cert still terminates TLS at the internal ALB. Private endpoints deserve TLS too — it's the same cost and stops in-network sniffing.

## The Atlantis exception, and how to remove it

Atlantis is the one component that needs **inbound from GitHub** (webhooks), which conflicts with "nothing public." Three ways out, in order of preference:

1. **Replace Atlantis with GitHub Actions for Terraform** *(recommended)* — plan on PR, apply on approval, running on GitHub's infrastructure and assuming an AWS role via OIDC. **Zero inbound to your VPC.** The trade-off is losing Atlantis's per-project locking and comment UX; for a single infra repo with few operators, Actions plus an environment protection rule is simpler and strictly more private. A ready-to-use workflow ships at `.github/workflows/terraform.yml` in the infra repo.
2. **Webhook relay** — keep Atlantis internal and put a minimal public receiver in front: API Gateway (HTTP API) → VPC Link → internal NLB → Atlantis, with the webhook secret validated and WAF restricting to GitHub's published hook CIDRs (`gh api meta --jq .hooks`). No compute is exposed, only a managed endpoint.
3. **Accept a public Atlantis**, protected by the webhook secret and IP allowlist. Simplest, and what most teams run — but it *is* an exception to the rule above, so make it a decision rather than an accident.

## Service plane — how vendor apps reach the world

**Ingress**: vendor services opt in per environment with `ingress.public: true` in their values file, which sets `scheme: internet-facing`, joins the shared `vendor-public` ingress group, and attaches the WAF. A service with `ingress.public: false` (the default) gets an internal ALB — right for internal APIs and for staging copies of public services.

**Subnets**: public ALBs live in public subnets; **nodes always stay private**. Traffic path: internet → ALB (public subnet) → pod IP (private subnet). No node is ever directly reachable.

**TLS**: ACM wildcard for the public domain, terminated at the ALB. HTTP redirects to HTTPS by default.

**WAF**: attached to the vendor-public ALB only — AWS managed rule sets plus per-IP rate limiting. This is the plane that faces the internet, so this is where the money belongs.

**Optional edge layer**: for products needing caching, DDoS absorption, or global latency, put CloudFront in front of the public ALB (origin = ALB, custom header shared secret so the ALB rejects direct access). Add it per-product rather than platform-wide.

**Isolation between vendors**: each service has its own namespace with a default-deny NetworkPolicy — ingress allowed only from the ALB, egress allowed to DNS, the internet via NAT, and explicitly named dependencies. One vendor cannot reach another's pods or Services even by IP.

**Egress**: all outbound traffic leaves through the NAT gateway with a **stable Elastic IP** — useful when a vendor's third-party dependency requires IP allowlisting. VPC endpoints for S3/ECR/STS keep AWS-bound traffic off the NAT (cheaper, and it removes NAT from the critical path).

## Diagram

```
                    ┌──────────────── internet ────────────────┐
                    │                                          │
              [WAF] │                                          │ (no path)
                    ▼                                          ✗
        ┌───────────────────────┐                  ┌───────────────────────┐
        │ ALB  vendor-public    │                  │ ALB  platform-internal│
        │ public subnets        │                  │ private subnets       │
        │ *.<domain>            │                  │ *.platform.<domain>   │
        └───────────┬───────────┘                  └───────────┬───────────┘
                    │                                          │
                    │                              corporate VPN / port-forward
                    ▼                                          ▼
        ┌─────────────────────────────────────────────────────────────────┐
        │  EKS nodes — PRIVATE subnets only                               │
        │  vendor namespaces (default-deny NetworkPolicy)  │  platform ns │
        └─────────────────────────────────────────────────────────────────┘
                    │ egress via NAT (stable EIP) + VPC endpoints
                    ▼
              third parties / AWS APIs
```

## Cost note

Two shared ALBs (one per plane) rather than one per service: ~$36/month total instead of ~$18 per service. Ingress `group.name` is what makes that possible — services join a group rather than provisioning their own.
