# Vendor App Conformance

Requirements for any service deployed to the EKS platform. Every item in "Required" must pass before a service is onboarded. We verify these during onboarding review and enforce most of them automatically (admission policy, chart schema, image scanning), so an app that skips one will fail to deploy — better to catch it here.

If your app can't meet a requirement, raise it with the platform team before onboarding. Exceptions are granted per-service, documented, and time-boxed.

## What the platform provides

You don't build or configure any of this — it exists so you know where your responsibility ends:

- Build and push pipeline: GitHub Actions workflow (provided by us) that builds your Dockerfile and pushes to ECR
- Deployment: ArgoCD deploys your image to dev automatically on merge; staging and prod promotions are handled by the platform team
- Ingress, TLS, and DNS
- Secrets delivery: secrets you request are injected as environment variables at runtime
- Log collection: anything on stdout/stderr is shipped and searchable
- Read-only ArgoCD access: deploy status, pod health, log tailing for your own service

## Required

### 1. Image

- Builds from a `Dockerfile` at the repo root using the provided GitHub Actions workflow. No builds outside CI.
- Runs as a non-root user (`USER` directive with a numeric UID, e.g. `USER 10001`). The cluster rejects root containers.
- No secrets, credentials, or environment-specific config baked into the image. One image runs in all three environments.
- Listens on a port above 1024.
- Passes ECR image scanning with no critical CVEs. High CVEs need a remediation date.
- Tags are immutable and set by CI (git SHA). Never reference `latest` anywhere.

### 2. Configuration

- All configuration comes from environment variables. No per-environment config files in the image or the repo.
- Every env var your app reads is documented in your repo's README: name, purpose, example value, required/optional.
- The app fails fast at startup with a clear error if a required variable is missing — don't limp along with defaults that only break later.

### 3. Secrets

- Secrets arrive as environment variables, injected by the platform. Your app just reads them.
- Never commit secrets to the repo, bake them into images, or log them. Request new secrets through the platform team; you'll get the env var name back.

### 4. Health endpoints

- **Liveness** — an endpoint (default `/healthz`) that returns 200 if the process is alive. Keep it dumb: no dependency checks. If this fails, the container gets restarted.
- **Readiness** — an endpoint (default `/readyz`) that returns 200 only when the app can serve traffic, including required downstream dependencies. If this fails, traffic is routed away but the container is left alone.
- Different paths are fine — they're configurable in your values file — but both endpoints must exist. Deploys cannot roll safely without them.

### 5. Lifecycle

- On SIGTERM: stop accepting new work, drain in-flight requests, exit 0. You get 30 seconds by default before SIGKILL. Kubernetes sends SIGTERM on every deploy and node rotation, so this path runs constantly — not just during incidents.
- Crash on unrecoverable startup errors instead of retrying forever. The platform handles restarts and backoff.
- Assume any instance of your app can be killed at any time without data loss.

### 6. State

- No persistent local state. The container filesystem is read-only except `/tmp` and an ephemeral scratch volume.
- Files that must outlive the pod go to S3 (or the datastore you've agreed with the platform team). Sessions go to your database or cache, not process memory, if you run more than one replica.
- If your app genuinely needs a persistent volume, that's an exception — talk to us first.

### 7. Logging

- Log to stdout/stderr only. No log files, no log rotation, no logging agents in your container.
- Structured JSON strongly preferred. At minimum include a timestamp, level, and message.
- Never log secrets, tokens, or full request bodies containing customer data.

### 8. Resources

- Provide a starting estimate for CPU and memory (request and limit) at onboarding. We'll right-size together from real usage after a couple of weeks in dev.
- The app must run correctly with more than one replica unless you've told us it can't (and why).

## Recommended

- Prometheus metrics on `/metrics` — gets you dashboards and alerting for free.
- Startup in under 60 seconds. Slow starters make rollouts and autoscaling sluggish; if yours needs longer, say so and we'll set a startup probe.
- Handle `SIGTERM` and readiness together: flip readiness to failing as soon as SIGTERM arrives so the load balancer drains before you exit.

## Onboarding checklist

Copy into the onboarding issue and check off:

- [ ] Dockerfile builds via the provided GitHub Actions workflow, image lands in ECR
- [ ] Container runs as non-root (verified: `docker run --rm <image> id -u` returns non-zero)
- [ ] ECR scan clean (no criticals)
- [ ] All env vars documented in README
- [ ] No secrets in repo history or image layers
- [ ] Liveness endpoint returns 200 on a healthy instance
- [ ] Readiness endpoint returns 200 only when dependencies are reachable
- [ ] App exits cleanly within 30s of SIGTERM under load
- [ ] No writes outside `/tmp` (verified: runs with a read-only root filesystem)
- [ ] Logs are stdout/stderr, structured
- [ ] Initial CPU/memory estimates provided
- [ ] Values file created from the app-template chart and reviewed by platform team
