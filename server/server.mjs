import { createHash, timingSafeEqual } from 'node:crypto';
import { createServer } from 'node:http';
import { pathToFileURL } from 'node:url';

const bodyLimit = 7 * 1024 * 1024;
const mediaLimit = 4 * 1024 * 1024;
const openAI = 'https://api.openai.com/v1';

class HTTPError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

const digest = (value) => createHash('sha256').update(value).digest();

function decodeMedia(value, label) {
  if (value === undefined) return;
  if (typeof value !== 'string' || value.length > Math.ceil(mediaLimit / 3) * 4) {
    throw new HTTPError(400, `Invalid ${label}`);
  }
  const bytes = Buffer.from(value, 'base64');
  if (!bytes.length || bytes.length > mediaLimit || bytes.toString('base64') !== value) {
    throw new HTTPError(400, `Invalid ${label}`);
  }
  return bytes;
}

async function parseRequest(request) {
  if (request.headers['content-type']?.split(';')[0].trim() !== 'application/json') {
    throw new HTTPError(415, 'Expected application/json');
  }
  const chunks = [];
  let count = 0;
  for await (const chunk of request.iterator({ destroyOnReturn: false })) {
    count += chunk.length;
    if (count > bodyLimit) throw new HTTPError(413, 'Request too large');
    chunks.push(chunk);
  }
  let input;
  try {
    input = JSON.parse(Buffer.concat(chunks).toString('utf8'));
  } catch {
    throw new HTTPError(400, 'Invalid JSON');
  }
  if (!input || Array.isArray(input) || typeof input !== 'object' ||
      (input.text !== undefined && typeof input.text !== 'string')) {
    throw new HTTPError(400, 'Invalid payload');
  }
  const text = input.text?.trim() ?? '';
  if (text.length > 4000) throw new HTTPError(400, 'Text too long');
  const image = decodeMedia(input.image, 'image');
  const audio = decodeMedia(input.audio, 'audio');
  if (image && (image[0] !== 0xff || image[1] !== 0xd8 || image[2] !== 0xff)) {
    throw new HTTPError(400, 'Expected JPEG image');
  }
  if (audio && audio.toString('ascii', 4, 8) !== 'ftyp') {
    throw new HTTPError(400, 'Expected M4A audio');
  }
  if (!text && !audio && !image) throw new HTTPError(400, 'Empty question');
  return { text, image, audio };
}

export function makeServer({ apiKey, token, model = 'gpt-4.1-mini', fetchImpl = fetch }) {
  if (!apiKey || !token || token.length < 32) {
    throw new Error('Set OPENAI_API_KEY and a random ASSISTANT_TOKEN of at least 32 characters');
  }
  const expected = digest(`Bearer ${token}`);
  let recent = [];
  let inFlight = false;

  async function callOpenAI(path, body, json, signal) {
    const response = await fetchImpl(`${openAI}/${path}`, {
      method: 'POST',
      headers: {
        Authorization: `Bearer ${apiKey}`,
        ...(json ? { 'Content-Type': 'application/json' } : {}),
      },
      body: json ? JSON.stringify(body) : body,
      redirect: 'error',
      signal,
    });
    if (!response.ok) {
      await response.body?.cancel();
      throw new HTTPError(502, 'OpenAI request failed');
    }
    return response.json();
  }

  return createServer({ requestTimeout: 30_000 }, async (request, response) => {
    let acquired = false;
    const disconnected = new AbortController();
    response.once('close', () => disconnected.abort());
    response.setHeader('Cache-Control', 'no-store');
    response.setHeader('Content-Type', 'application/json; charset=utf-8');
    try {
      if (request.url !== '/v1/ask') throw new HTTPError(404, 'Not found');
      if (request.method !== 'POST') throw new HTTPError(405, 'Use POST');
      if (!timingSafeEqual(digest(request.headers.authorization ?? ''), expected)) {
        throw new HTTPError(401, 'Unauthorized');
      }
      const now = Date.now();
      recent = recent.filter((time) => now - time < 60_000);
      if (inFlight || recent.length >= 6) throw new HTTPError(429, 'Try again later');
      inFlight = acquired = true;
      recent.push(now);
      const { text, image, audio } = await parseRequest(request);
      const signal = AbortSignal.any([disconnected.signal, AbortSignal.timeout(75_000)]);
      let transcript;
      if (audio) {
        const form = new FormData();
        form.append('model', 'gpt-4o-mini-transcribe');
        form.append('file', new Blob([audio], { type: 'audio/mp4' }), 'question.m4a');
        const result = await callOpenAI('audio/transcriptions', form, false, signal);
        transcript = typeof result.text === 'string' ? result.text.trim() : '';
        if (!text && !transcript && !image) throw new HTTPError(422, 'No speech detected');
      }
      const question = [text, transcript].filter(Boolean).join('\n') ||
        'Describe en español lo que se ve en esta imagen.';
      const content = [{ type: 'input_text', text: question }];
      if (image) content.push({
        type: 'input_image', image_url: `data:image/jpeg;base64,${image.toString('base64')}`, detail: 'auto',
      });
      const result = await callOpenAI('responses', {
        model, store: false, max_output_tokens: 500,
        input: [{ role: 'user', content }],
      }, true, signal);
      const answer = (result.output ?? []).filter((item) => item.type === 'message')
        .flatMap((item) => item.content ?? [])
        .filter((item) => item.type === 'output_text' && typeof item.text === 'string')
        .map((item) => item.text).join('\n').trim();
      if (!answer) throw new HTTPError(502, 'No answer returned');
      response.end(JSON.stringify({ answer, ...(transcript ? { transcript } : {}) }));
    } catch (error) {
      if (!response.destroyed) {
        if (!request.complete) response.setHeader('Connection', 'close');
        response.statusCode = error instanceof HTTPError ? error.status : 502;
        response.end(JSON.stringify({
          error: error instanceof HTTPError ? error.message : 'Request failed',
        }));
      }
    } finally {
      if (acquired) inFlight = false;
    }
  });
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const server = makeServer({
    apiKey: process.env.OPENAI_API_KEY,
    token: process.env.ASSISTANT_TOKEN,
    model: process.env.OPENAI_MODEL,
  });
  server.listen(Number(process.env.PORT ?? 8787), '127.0.0.1');
}
