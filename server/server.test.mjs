import assert from 'node:assert/strict';
import { once } from 'node:events';
import test from 'node:test';
import { makeServer } from './server.mjs';

const token = 'local-test-token-not-a-real-secret';
const vision = Buffer.from([0xff, 0xd8, 0xff, 0xd9]).toString('base64');
const audio = Buffer.from('1234ftypM4A ').toString('base64');

async function fixture(t, handler) {
  const calls = [];
  const server = makeServer({
    apiKey: 'test-server-key',
    token,
    fetchImpl: async (url, options) => {
      calls.push({ url, options });
      if (handler) return handler(url, options);
      if (url.endsWith('/audio/transcriptions')) return Response.json({ text: ' ¿Qué ves? ' });
      return Response.json({
        output: [{ type: 'message', content: [{ type: 'output_text', text: 'Una planta.' }] }],
      });
    },
  });
  server.listen(0, '127.0.0.1');
  await once(server, 'listening');
  t.after(() => {
    server.closeAllConnections();
    return new Promise((resolve) => server.close(resolve));
  });
  const url = `http://127.0.0.1:${server.address().port}/v1/ask`;
  return {
    calls,
    ask: (body, bearer = token) => fetch(url, {
      method: 'POST', headers: { Authorization: `Bearer ${bearer}`, 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    }),
  };
}

test('authenticates before sending anything to OpenAI', async (t) => {
  const { calls, ask } = await fixture(t);
  assert.equal((await ask({ text: 'hola' }, 'incorrect')).status, 401);
  assert.equal(calls.length, 0);
});

test('sends text only and opts out of Responses storage', async (t) => {
  const { calls, ask } = await fixture(t);
  const result = await ask({ text: 'Hola' });
  assert.equal(result.status, 200);
  assert.deepEqual(await result.json(), { answer: 'Una planta.' });
  const [{ url, options }] = calls;
  assert.equal(url, 'https://api.openai.com/v1/responses');
  assert.equal(options.headers.Authorization, 'Bearer test-server-key');
  assert.equal(options.redirect, 'error');
  const payload = JSON.parse(options.body);
  assert.equal(payload.store, false);
  assert.deepEqual(payload.input[0].content, [{ type: 'input_text', text: 'Hola' }]);
});

test('transcribes the recording and sends the JPEG with the question', async (t) => {
  const { calls, ask } = await fixture(t);
  const result = await ask({ text: 'Describe', audio, image: vision });
  assert.equal(result.status, 200);
  assert.deepEqual(await result.json(), { answer: 'Una planta.', transcript: '¿Qué ves?' });
  assert.equal(calls.length, 2);
  assert.equal(calls[0].url, 'https://api.openai.com/v1/audio/transcriptions');
  const form = calls[0].options.body;
  assert.equal(form.get('model'), 'gpt-4o-mini-transcribe');
  assert.equal(form.get('file').name, 'question.m4a');
  assert.deepEqual(Buffer.from(await form.get('file').arrayBuffer()), Buffer.from(audio, 'base64'));
  const { content } = JSON.parse(calls[1].options.body).input[0];
  assert.deepEqual(content, [
    { type: 'input_text', text: 'Describe\n¿Qué ves?' },
    { type: 'input_image', image_url: `data:image/jpeg;base64,${vision}`, detail: 'auto' },
  ]);
});

test('rejects invalid input and caps the streamed request size', async (t) => {
  const { calls, ask } = await fixture(t);
  for (const body of [{}, { text: 14 }, { image: '%%%!' }, { image: audio }, { audio: vision }]) {
    assert.equal((await ask(body)).status, 400);
  }
  assert.equal((await ask({ image: 'A'.repeat(7 * 1024 * 1024) })).status, 413);
  assert.equal((await ask({ text: 'Hola' })).status, 429);
  assert.equal(calls.length, 0);
});

test('does not relay provider error details to the device', async (t) => {
  const { ask } = await fixture(t, () => new Response('sensitive diagnostic', { status: 429 }));
  const result = await ask({ text: 'Hola' });
  assert.equal(result.status, 502);
  assert.deepEqual(await result.json(), { error: 'OpenAI request failed' });
});
