// k6 load test: 500 concurrent virtual users held for 60 seconds.
// Each iteration exercises the full CRUD cycle, so the tasks table stays small
// and the list endpoint's cost does not grow during the run.
import http from "k6/http";
import { check, sleep } from "k6";

const BASE_URL = __ENV.BASE_URL || "http://crud-web.crud-app.svc.cluster.local";
const API = `${BASE_URL}/api/v1/tasks`;
const JSON_HEADERS = { headers: { "Content-Type": "application/json" }, timeout: "60s" };
const PLAIN = { timeout: "60s" };

export const options = {
  stages: [
    { duration: "15s", target: 500 }, // ramp up
    { duration: __ENV.HOLD || "60s", target: 500 }, // sustained load
    { duration: "10s", target: 0 },   // ramp down
  ],
  thresholds: {
    // Targets, not hard limits: the run still completes if they are missed.
    http_req_failed: ["rate<0.01"],
    http_req_duration: ["p(95)<2000"],
  },
  summaryTrendStats: ["avg", "min", "med", "p(90)", "p(95)", "p(99)", "max"],
};

export default function () {
  check(http.get(API, PLAIN), { "list 200": (r) => r.status === 200 });

  const created = http.post(
    API,
    JSON.stringify({ task: { title: `load-${__VU}-${__ITER}`, description: "k6" } }),
    JSON_HEADERS
  );
  const ok = check(created, { "create 201": (r) => r.status === 201 });

  if (ok) {
    const id = created.json("id");
    check(http.get(`${API}/${id}`, PLAIN), { "show 200": (r) => r.status === 200 });
    check(
      http.patch(`${API}/${id}`, JSON.stringify({ task: { completed: true } }), JSON_HEADERS),
      { "update 200": (r) => r.status === 200 }
    );
    check(http.del(`${API}/${id}`, null, PLAIN), { "delete 200": (r) => r.status === 200 });
  }

  sleep(1);
}
