# Branching and promotion model

**Environments are directories and gates, not branches.** There is no `dev` branch, no `staging` branch, no promotion-by-merge. If someone proposes adding one, this page is the answer why not.

The classic `dev → staging → main` branch-per-environment model is a known GitOps anti-pattern: branches drift, promotions become merge conflicts, hotfixes become cherry-pick archaeology, and "what is actually running in staging" stops being answerable. This platform replaces it with:

- **One `main` in every repo.**
- **Environments are directories**: `envs/dev/`, `envs/staging/` (and `envs/prod/` when it exists).
- **Promotion moves content, not branches**: Kargo copies a verified image tag from one environment's values file to the next, as a commit.
- **Kargo is the branching strategy for deployments.** The gate is an RBAC verb, not a merge.

## Per-repo model

| Repo | Branches | `main` means | Writers |
|---|---|---|---|
| **Service repos** | trunk-based: short-lived feature branches → PR → `main` | "buildable truth — this will be in dev within minutes" | Vendors, by reviewed PR. Merging **is** the decision to deploy to dev |
| **GitOps repo** | `main` only — **paths** are the boundary, not branches | the deployed state of every environment | Three writers, separated by path: **Kargo** owns `image.tag` in `envs/*` (its own deploy key); **humans by PR** own charts, RBAC, platform config; nothing else writes |
| **Infra repo** | trunk + PR branches; **Atlantis applies before merge** | applied reality | Humans by PR; `atlantis apply` is the gate, merge follows a successful apply |

## What goes where, when

- **dev** — automatic, on merge to a service repo. No approval, no schedule. Dev is where "when" costs nothing.
- **staging** — when a human holding the `promote` verb decides. Timing policy, if you want any, is expressed as data on the Stage rather than as calendar convention:
  - `requiredSoakTime` — freight must bake in dev for N hours before it's eligible
  - `spec.verification` — run a smoke test between stages and gate on its result
- **prod** (when it exists) — same shape, one more stage sourced from staging, with its own approver team and a `promote` Role scoped `resourceNames: ["prod"]`.

## Enforcement

Convention is not enforcement. What should actually be configured:

**Service and infra repos** — Settings → Rules → New branch ruleset, enforcement **Active**, target the default branch:
- Require a pull request before merging
- Require status checks (the build) — service repos
- Block force pushes

**GitOps repo** — same, with one critical addition: **Kargo pushes tag commits directly to `main`**, so a naive PR requirement breaks every promotion. Add Kargo's deploy key to the ruleset's **bypass list**. If your plan doesn't offer deploy-key bypass, do not enable the PR rule here; rely on CODEOWNERS (below) and accept the gap knowingly.

**CODEOWNERS** (this repo) makes human changes attract review even where pushes stay open:

```
/envs/staging/   @<org>/<release-team>
/envs/prod/      @<org>/<prod-approvers>
/charts/         @<org>/<release-team>
/argocd/         @<org>/<release-team>
/kargo/          @<org>/<release-team>
```

**Atlantis** — set `apply_requirements: [approved, mergeable]` in `atlantis.yaml` as soon as more than one person operates the platform.

## Rules of thumb

1. **One writer per field.** Kargo owns image tags; humans own everything else. Two writers to the same field is how git stops being the truth.
2. **Never branch an environment.** If you want an environment, add a directory and a stage.
3. **Rollback is `git revert`** on the promotion commit — not a redeploy, not a console click.
4. **Hotfix is the normal path, faster** — merge to the service repo, let it flow to dev, promote. There is no separate hotfix branch, because there is no branch to hotfix.
