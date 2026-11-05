export function validateIdempotencyMode(mode) {
  if (mode !== 'none' && mode !== 'unique') {
    throw new Error(`idempotency mode must be none or unique, got: ${mode}`);
  }
  return mode;
}

// Prepare keys before the timed schedule. Retransmitting a target reuses its key.
export function applyIdempotencyMode(target, mode, decodeBody) {
  validateIdempotencyMode(mode);
  if (mode === 'none') {
    return target;
  }
  if (Object.keys(target.header || {}).some((name) => name.toLowerCase() === 'idempotency-key')) {
    throw new Error('prepared target already contains an Idempotency-Key');
  }
  const order = JSON.parse(decodeBody(target.body));
  if (typeof order.orderId !== 'string'
      || !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(order.orderId)) {
    throw new Error('unique-key mode requires a prepared UUID orderId');
  }
  return {
    ...target,
    header: { ...target.header, 'Idempotency-Key': [`http-${order.orderId}`] },
  };
}

export function sameReceipt(actual, expected) {
  return actual != null && expected != null
    && typeof actual === 'object' && typeof expected === 'object'
    && Object.keys(actual).length === Object.keys(expected).length
    && Object.keys(expected).every((key) => actual[key] === expected[key]);
}
