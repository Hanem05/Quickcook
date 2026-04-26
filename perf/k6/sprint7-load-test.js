import http from 'k6/http';
import { check, sleep } from 'k6';

export const options = {
  stages: [
    { duration: '30s', target: 50 },
    { duration: '45s', target: 150 },
    { duration: '60s', target: 300 },
    { duration: '30s', target: 0 },
  ],
  thresholds: {
    http_req_duration: ['p(95)<1500'],
    http_req_failed: ['rate<0.03'],
  },
};

const BASE_URL = __ENV.BASE_URL || 'http://127.0.0.1:8000/api';

export default function () {
  const recipes = http.get(`${BASE_URL}/recipes?per_page=20`);
  check(recipes, {
    'recipes status 200': (r) => r.status === 200,
  });

  const search = http.get(`${BASE_URL}/search?query=chicken`);
  check(search, {
    'search status 200': (r) => r.status === 200,
  });

  const detail = http.get(`${BASE_URL}/recipes/1`);
  check(detail, {
    'detail status 200 or 404': (r) => r.status === 200 || r.status === 404,
  });

  sleep(1);
}
