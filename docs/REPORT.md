# Containerization, Kubernetes Deployment & Observability

IT Security Management (ITSM) & DevOps: Re-examination Assignment, Academic Year 2025-2026

**Name:** [YOUR FULL NAME]
**Student ID:** 10008311
**Repository:** [GITHUB LINK]

> Draft. Replace the bracketed items, add screenshots if you want them, and write section 4.4 yourself. Every number below comes from a real run; raw output is in `docs/evidence/` and `load-tests/results/`.

## 1. Containerization and Setup

### 1.1 Application

The CRUD API is a Rails 8.1 API-only application exposing `/api/v1/tasks` (list, read, create, update, delete) plus `/up`, Rails' built-in health endpoint. Data is stored in MySQL.

### 1.2 Dockerfile

- **Multi-stage build:** `ruby:3.3.10` (full image) installs and compiles gems; `ruby:3.3.10-slim` runs the app, so compilers and headers are not shipped.
- **Server:** Puma, started directly as PID 1 (`docker-entrypoint` uses `exec`).
- **Non-root:** runs as `rails` (uid 1000), confirmed by `docker exec ... id`.
- **Port:** `EXPOSE 3000`.
- **Image size:** 194 MB compressed content (814 MB on disk).

### 1.3 Docker Compose

`docker-compose.yaml` defines the `web` and `crud-mysql` services on the named network `crud_net`, with the named volume `mysql_data`. The app has a healthcheck probing `/up` and starts only after MySQL is healthy.

Validation (`docs/evidence/01-compose.txt`): all 10 functional checks passed, and a row survived `docker compose down` and `up` with the volume kept.

### 1.4 Assumptions

- **Original endpoints:** [CONFIRM AGAINST THE ORIGINAL NODE.JS APP] The original code was not available while containerizing, so the API is assumed to match the course application's task CRUD routes under `/api/v1/tasks`.
- **Versions:** Ruby 3.3.10 and Rails 8.1.4 (a currently supported release), Puma 8.0.2, MySQL 8.0.
- **Ports:** the app listens on 3000 and MySQL on 3306. Compose publishes MySQL only on 127.0.0.1.
- **Database configuration:** one production database, `crud_devops_project_production`, accessed by a dedicated user `crud_app` rather than root. Rails' optional cache, queue and cable databases are not used, so they were removed.
- **Migrations:** `rails db:prepare` runs on container start. This is safe with one replica; with several replicas starting at once, a dedicated migration Job would be preferable.
- **Environment variables:** `DB_HOST`, `DB_USERNAME`, `DB_PASSWORD`, `RAILS_MASTER_KEY`, `RAILS_ENV`, `PORT`, `WEB_CONCURRENCY`, `RAILS_MAX_THREADS`. Secrets are held in a git-ignored `.env`.
- **TLS:** not terminated by the app, because it is only reached inside the cluster for this assignment.

## 2. Kubernetes Deployment

### 2.1 Manifests (`k8s/`)

`deployment.yaml` uses `apps/v1`, namespace `crud-app`, labels matching `selector.matchLabels`, and `replicas: 1`.

| Setting | Web | MySQL |
|---|---|---|
| CPU request / limit | 500m / 2 | 250m / 1 |
| Memory request / limit | 512Mi / 1Gi | 512Mi / 1Gi |

Probes all use HTTP `GET /up`:

| Probe | Period | Failure threshold | Purpose |
|---|---|---|---|
| startupProbe | 5 s | 30 (up to 150 s) | Allows for `db:prepare` and boot |
| readinessProbe | 5 s | 3 | Removes an unready pod from the Service |
| livenessProbe | 10 s | 6 | Restarts a hung process |

The liveness threshold is deliberately tolerant: a pod that is merely slow under load should not be restarted. `/up` confirms the app booted but does not query MySQL, so a database outage does not restart the web pods.

An init container waits for MySQL's port, so first start does not crash-loop. MySQL runs as a StatefulSet with a 2 Gi PersistentVolumeClaim.

### 2.2 Service type

`k8s/service.yaml` uses **ClusterIP**. The assignment asks for exposure inside the cluster, and ClusterIP gives a stable internal address with the smallest attack surface. NodePort would open a port on the node without need, and LoadBalancer requires a cloud provider or `minikube tunnel`. Access from the host for debugging uses `kubectl port-forward`.

### 2.3 Evidence

See `docs/evidence/02-kubernetes.txt` for `kubectl get pods,svc`, the Deployment description and the endpoint list. All 10 functional checks passed through the Service.

### 2.4 Assumptions

- Minikube with the Docker driver, 6 CPUs and 6 GiB memory, Kubernetes v1.37.0, on an Apple Silicon (arm64) Mac.
- The image is loaded with `minikube image load`, so no registry is used.
- The Secret is created from `.env` and is not committed.

## 3. Functional Validation and Load Testing

### 3.1 Scenario

`load-tests/k6-load-test.js` ramps to **500 virtual users in 15 s, holds for 60 s**, then ramps down over 10 s. Each iteration runs list, create, read, update and delete, then sleeps 1 s. Deleting each record keeps the table small so list cost stays constant.

k6 runs **inside the cluster** and targets the Service, so results measure the application rather than a macOS port-forward tunnel. It does share the node's 6 CPUs with the application.

Puma is configured with `WEB_CONCURRENCY=2` and `RAILS_MAX_THREADS=5`, so 10 requests are processed at once per pod.

### 3.2 Results

| Run | Replicas | Requests | Avg req/s | Error % | p50 (ms) | p95 (ms) | p99 (ms) | Max (ms) |
|---|---|---|---|---|---|---|---|---|
| 1 baseline | 1 | 80,120 | 933.5 | 0.00 | 257 | 594 | 782 | 1,370 |
| 2 repeat with counters | 1 | 77,850 | 905.2 | 0.00 | 270 | 632 | 920 | 1,360 |
| 3 HPA, 180 s hold | 1 to 3 | 170,205 | 826.4 | 0.00 | 333 | 873 | 1,190 | 1,950 |
| 4 fixed replicas | 3 | 103,500 | 1,207.3 | 0.00 | 102 | 481 | 777 | 1,230 |

Averages include the ramp-up and ramp-down periods.

Run 1 over time, in 10-second windows:

| Window (s) | Req/s | Error % | p50 (ms) | p95 (ms) | p99 (ms) |
|---|---|---|---|---|---|
| 0-10 | 867.0 | 0.00 | 2 | 31 | 85 |
| 10-20 | 932.3 | 0.00 | 311 | 540 | 606 |
| 20-30 | 921.2 | 0.00 | 316 | 642 | 754 |
| 30-40 | 941.9 | 0.00 | 297 | 749 | 1224 |
| 40-50 | 1086.1 | 0.00 | 255 | 449 | 677 |
| 50-60 | 934.3 | 0.00 | 282 | 691 | 1327 |
| 60-70 | 1010.4 | 0.00 | 281 | 594 | 727 |
| 70-80 | 1026.8 | 0.00 | 265 | 451 | 757 |
| 80-90 | 292.0 | 0.00 | 5 | 119 | 155 |

The same table for each run is in `load-tests/results/<run>/analysis.md`.

### 3.3 Resource use per pod (run 2, one replica)

| Pod | CPU | Memory peak | Memory limit |
|---|---|---|---|
| crud-web | 1.33 cores average over the whole 89 s (cgroup counters); 1.56 cores peak (`kubectl top`) | 384 MiB (cgroup) | 1 GiB |
| mysql-0 | 297m peak (`kubectl top`) | 382 Mi | 1 GiB |

`kubectl top` refreshes slowly, so its values are coarse. The web pod's CPU average comes from `usage_usec` in its cgroup and is more reliable. The CPU limit was never hit: `nr_throttled` stayed at 0.

### 3.4 Analysis

**The load was handled satisfactorily.** All runs had 0% errors, and with one replica p95 stayed around 600 ms, inside the 2-second target.

**Relation to Puma.** At about 930 req/s and 258 ms average latency, Little's Law gives about 240 requests in the system, against 10 Puma threads. Most of a request's time was therefore spent queued, which matches the jump from about 2 ms p50 at low load to about 300 ms under full load. Connections to the pool were sized to match: one MySQL connection per thread.

**CPU-bound or memory-bound.** The application tier is **CPU-bound at the Puma worker level, not memory-bound**. Memory peaked at about 38% of its limit. With the Global VM Lock, each Ruby worker can use roughly one core, so 2 workers cap near 2 cores; the pod reached up to 1.56. Tripling the workers by running 3 replicas lifted throughput from about 950 to 1,600-1,650 req/s for the first part of run 4 and cut overall p95 by roughly 20%, which supports this. MySQL did not appear saturated (576m peak of 1 core in run 4).

**Limits of this conclusion.** Run 4 did not sustain its peak: throughput began falling about 40 seconds in and was down to 880-970 req/s by the final minute's end. The cause was not isolated. All pods and k6 shared one 6-CPU node, so this could be CPU contention on the node or a growing MySQL cost. Further runs varying `WEB_CONCURRENCY` alone would be needed to confirm it.

## 4. Observability and Fault Tolerance

### 4.1 Crash simulation

The Puma master process was killed with SIGKILL from the Minikube node (`docs/evidence/03-fault-tolerance.txt`):

- `kubectl get pods` showed `RESTARTS` going from **0 to 1**.
- The previous container reported exit code **137** (SIGKILL).
- The pod went `0/1` (removed from the Service by the readiness probe) and was `1/1` again about **9 seconds** later.
- The events show the startup probe failing with "connection refused" during the restart.

Deleting the pod also worked: the ReplicaSet created a replacement that was Ready within seconds, and all 10 functional checks passed afterwards.

### 4.2 Horizontal Pod Autoscaler

`k8s/hpa.yaml` targets 70% of the CPU request (350m per pod), with 1 to 3 replicas. The 1-replica baseline runs without it.

In run 3 (`docs/evidence/04-hpa.txt`), the HPA read 302% CPU and scaled to 3 replicas, but **throughput did not improve**. The two new pods stayed near 50m CPU. The likely reason is that k6 keeps connections open, and a ClusterIP Service balances per connection, so existing connections stayed on the first pod. Run 4 supports this: with 3 replicas before the test began, connections spread out and the extra pods did real work (peaks of about 1,150-1,210m).

Autoscaling a workload built on long-lived connections therefore needs connection limits or Layer 7 load balancing to rebalance. The metric also took about 80 seconds to become available after the HPA was applied, which is too slow for short bursts.

### 4.3 Monitoring

`kubectl top`, pod events and restart counts gave enough visibility for this exercise. `kubectl top` proved too coarse for peaks, so cgroup counters were added. A production setup would add Prometheus and Grafana.

### 4.4 Reflective summary

[WRITE THIS YOURSELF: what worked, what did not, and what you would change. The assignment asks for an honest account. Points you could draw on: the missing `/up` route; a local dev server shadowing port 3000; the HPA not improving throughput; run 4 not sustaining its peak.]

## 5. Repository

The layout is described in `README.md`. Required files: `Dockerfile`, `docker-compose.yaml`, `k8s/deployment.yaml`, `k8s/service.yaml`, `load-tests/k6-load-test.js`.
