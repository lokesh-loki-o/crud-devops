# CRUD DevOps Project

A Ruby on Rails CRUD API for tasks, backed by MySQL, packaged with Docker and deployed on Kubernetes (Minikube), with load tests and fault-tolerance evidence.

Ruby 3.3.10 · Rails 8.1.4 · Puma 8.0.2 · MySQL 8.0

## API

| Method | Path | Purpose |
|---|---|---|
| GET | `/up` | Health check |
| GET | `/api/v1/tasks` | List tasks |
| GET | `/api/v1/tasks/:id` | Read one task |
| POST | `/api/v1/tasks` | Create a task |
| PATCH / PUT | `/api/v1/tasks/:id` | Update a task |
| DELETE | `/api/v1/tasks/:id` | Delete a task |

Request body for create and update: `{"task": {"title": "...", "description": "...", "completed": false}}`

## Repository layout

| Path | Contents |
|---|---|
| `app/`, `config/`, `db/` | Rails application |
| `frontend/` | React client (not part of the API image) |
| `Dockerfile`, `docker-compose.yaml` | Multi-stage image and local stack |
| `k8s/` | Kubernetes manifests |
| `load-tests/` | Functional test, k6 script, runner and results |
| `docs/` | Report draft and captured command output |

## Run with Docker Compose

```bash
cp env.example .env   # then fill in the values
docker compose up -d --build --wait
docker exec -i -e BASE_URL=http://localhost:3000 crud-devops-project bash -s < load-tests/functional-test.sh
```

The Rails API is available at `http://localhost:3002` on the host. To run the React frontend, use `npm --prefix frontend run dev` and open `http://localhost:5173`.

## Docker monitoring

Start the app and monitoring services with Docker Compose:

```bash
docker compose up -d
```

Open Grafana at `http://localhost:3000` and select the **CRUD Project - Docker Containers** dashboard in the **CRUD Docker** folder. Prometheus scrapes a Docker API exporter for each running container's CPU and memory metrics; Prometheus is available at `http://localhost:9090`. On Linux, set `DOCKER_SOCK=/var/run/docker.sock` before running Compose; Docker Desktop on macOS uses its default socket path. The exporter needs access to the Docker socket, so keep this stack local and do not expose the exporter outside the trusted Docker network.

## Deploy on Minikube

```bash
minikube start --driver=docker --cpus=6 --memory=6144 --addons=metrics-server
docker compose build web
minikube image load crud-devops-project:1.0.0
kubectl apply -f k8s/namespace.yaml -f k8s/configmap.yaml
kubectl -n crud-app create secret generic crud-secrets --from-env-file=.env
kubectl apply -f k8s/mysql.yaml -f k8s/deployment.yaml -f k8s/service.yaml
kubectl -n crud-app rollout status deployment/crud-web
kubectl -n crud-app get pods,svc
```

To reach the API from your machine:

```bash
kubectl -n crud-app port-forward svc/crud-web 8080:80
```

## Load test

Runs k6 inside the cluster with 500 virtual users held for 60 seconds. Results are saved in `load-tests/results/<label>/`.

```bash
./load-tests/run-in-cluster.sh baseline
```

## Secrets

`.env` and `config/master.key` are git-ignored. The Kubernetes Secret is created from `.env` and never committed; `k8s/secret.example.yaml` shows its shape.
