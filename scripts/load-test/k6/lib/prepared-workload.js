import { SharedArray } from 'k6/data';
import encoding from 'k6/encoding';

export function loadPreparedTargets(path, expectedRequests) {
  const targets = new SharedArray('prepared matched-order targets', () =>
    open(path)
      .split('\n')
      .filter((line) => line.trim().length > 0)
      .map((line, index) => {
        const target = JSON.parse(line);
        if (!target.method || !target.url || !target.body) {
          throw new Error(`prepared target ${index} is missing method, url, or body`);
        }
        return target;
      }),
  );

  if (targets.length !== expectedRequests) {
    throw new Error(
      `prepared target count ${targets.length} does not match `
        + `rate-duration contract ${expectedRequests}`,
    );
  }
  return targets;
}

export function materializeRequest(target, httpTimeout) {
  const headers = {};
  for (const [name, values] of Object.entries(target.header || {})) {
    headers[name] = Array.isArray(values) ? values[0] : values;
  }
  const side = target.url.endsWith('/bid/buy') ? 'buy' : 'sell';
  return {
    body: encoding.b64decode(target.body, 'std', 's'),
    method: target.method,
    params: {
      headers,
      responseType: 'none',
      timeout: httpTimeout,
      tags: {
        endpoint: `order-${side}`,
        name: `POST /bid/${side}`,
        order_side: side,
      },
    },
    url: target.url,
  };
}
