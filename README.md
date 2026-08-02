# swiftwad-gitops

Deployment config for the vendor platform POC. ArgoCD (hub on `swiftwad-staging`) watches this repo and reconciles both clusters. Vendors have no write access here — CI bumps dev image tags, humans merge promotion PRs for staging.

## Layout

- `charts/app-template/` — the one chart every vendor service deploys through. Conformance is enforced by its `values.schema.json` and hardcoded security context.
- `envs/{dev,staging}/<app>.yaml` — per-environment values. Dev tags are written by app-repo CI; staging tags change via promotion PR only.
- `argocd/` — AppProjects and Applications, managed by the root app-of-apps.
- `bootstrap/` — ArgoCD install values, applied once by hand.
- `docs/vendor-conformance.md` — requirements a service must meet before onboarding.

## Promotion (Kargo)

CI only builds and pushes images. Kargo (on the staging cluster, `kargo/` dir here) watches ECR:

- **dev** — auto-promotes every new image: Kargo commits the tag to `envs/dev/<app>.yaml` and triggers the ArgoCD sync.
- **staging** — only freight that has passed dev is eligible; promotion is a manual approval (Kargo UI or a `Promotion` resource), after which Kargo does the same commit + sync against `envs/staging/<app>.yaml`.

Kargo pushes via its own write deploy key; the promotion history is the git log.

## Bootstrap (once)

```sh
aws eks update-kubeconfig --name swiftwad-staging --profile swiftwad
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd --create-namespace -f bootstrap/argocd-values.yaml
# register dev cluster as a spoke, then:
kubectl apply -f argocd/root-app.yaml
```
