# Sprint 7 Load Testing (k6)

## Prerequisites
- Install [k6](https://k6.io/docs/get-started/installation/).
- Start Laravel API locally (`php artisan serve`) or point to your hosted API.

## Run

```bash
k6 run perf/k6/sprint7-load-test.js
```

Custom API URL:

```bash
k6 run -e BASE_URL=http://127.0.0.1:8000/api perf/k6/sprint7-load-test.js
```

## What it measures
- recipe list endpoint latency
- search endpoint latency
- recipe detail endpoint latency
- request failure rate

## Targets
- p95 response time < 1500 ms
- error rate < 3%
