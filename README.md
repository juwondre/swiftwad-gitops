# swiftwad-gitops

Deployment config for the vendor platform POC. ArgoCD (hub on `swiftwad-staging`) watches this repo and reconciles both clusters. Vendors have no write access here — CI bumps dev image tags, humans merge promotion PRs for staging.

## Layout

- `charts/app-template/` — the one chart every vendor service deploys through. Conformance is enforced by its `values.schema.json` and hardcoded security context.
- `envs/{dev,staging}/<app>.yaml` — per-environment values. Dev tags are written by app-repo CI; staging tags change via promotion PR only.
- `argocd/` — AppProjects and Applications, managed by the root app-of-apps.
- `bootstrap/` — ArgoCD install values, applied once by hand.
- `docs/vendor-conformance.md` — requirements a service must meet before onboarding.

## Promotion

Dev is continuous: merge to an app repo → CI pushes image → CI bumps `envs/dev/<app>.yaml` → ArgoCD syncs.

Staging is a PR: copy the proven tag from `envs/dev/<app>.yaml` into `envs/staging/<app>.yaml`, open a PR, get it reviewed, merge. ArgoCD does the rest. (Kargo can automate this later; the layout already fits it.)

## Bootstrap (once)

```sh
aws eks update-kubeconfig --name swiftwad-staging --profile swiftwad
helm repo add argo https://argoproj.github.io/argo-helm
helm install argocd argo/argo-cd -n argocd --create-namespace -f bootstrap/argocd-values.yaml
# register dev cluster as a spoke, then:
kubectl apply -f argocd/root-app.yaml
```
