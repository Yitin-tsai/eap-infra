import test from 'node:test';
import assert from 'node:assert/strict';
import { applyIdempotencyMode, validateIdempotencyMode, sameReceipt } from '../k6/lib/idempotency.js';

const orderId = '71bc6d8d-3c69-468a-9b21-b39374f45fd0';
const body = JSON.stringify({ orderId, bidder: 'user-a', bidPrice: 100, amount: 10 });
const target = {
  method: 'POST', url: 'http://localhost:8080/eap-order/bid/buy',
  header: { 'Content-Type': ['application/json'], ID_TOKEN: ['fixture'] },
  body: Buffer.from(body).toString('base64'),
};
const decode = (encoded) => Buffer.from(encoded, 'base64').toString();

test('baseline preserves the prepared request without decoding it', () => {
  assert.equal(applyIdempotencyMode(target, 'none', () => assert.fail('unexpected decode')), target);
});
test('unique mode deterministically keys the operation and preserves the request and caller headers', () => {
  const first = applyIdempotencyMode(target, 'unique', decode);
  assert.deepEqual(first, applyIdempotencyMode(target, 'unique', decode));
  assert.equal(first.body, target.body);
  assert.equal(first.url, target.url);
  assert.deepEqual(first.header.ID_TOKEN, ['fixture']);
  assert.deepEqual(first.header['Idempotency-Key'], [`http-${orderId}`]);
  assert.equal(target.header['Idempotency-Key'], undefined);
  const other = { ...target, body: Buffer.from(body.replace(orderId,
    '71bc6d8d-3c69-468a-9b21-b39374f45fd1')).toString('base64') };
  assert.notDeepEqual(first.header['Idempotency-Key'],
    applyIdempotencyMode(other, 'unique', decode).header['Idempotency-Key']);
});
test('bad modes, ambiguous keys and missing operation identity fail closed', () => {
  assert.throws(() => validateIdempotencyMode('replay'), /none or unique/);
  assert.throws(() => applyIdempotencyMode({ ...target,
    header: { 'idempotency-key': ['old'] } }, 'unique', decode), /already contains/);
  assert.throws(() => applyIdempotencyMode({ ...target, body: Buffer.from('{}').toString('base64') },
    'unique', decode), /UUID orderId/);
});
test('replay comparison ignores property order but rejects changed, missing and extra receipt fields', () => {
  const expected = { orderId, marketSequence: 7, status: 'PENDING_WALLET_CHECK' };
  assert.equal(sameReceipt({ status: expected.status, marketSequence: 7, orderId }, expected), true);
  assert.equal(sameReceipt({ ...expected, orderId: 'different' }, expected), false);
  assert.equal(sameReceipt({ ...expected, marketSequence: 8 }, expected), false);
  assert.equal(sameReceipt({ orderId }, expected), false);
  assert.equal(sameReceipt({ ...expected, extra: true }, expected), false);
  assert.equal(sameReceipt(null, expected), false);
  assert.equal(sameReceipt(expected, undefined), false);
});
