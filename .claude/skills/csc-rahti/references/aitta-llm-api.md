# CSC Aitta — LLM Inference API

## Contents
- [Authentication](#authentication)
- [Environment variables](#environment-variables)
- [Endpoints](#endpoints)
- [Model catalog](#model-catalog-snapshot--verify-with-get-model)
- [curl examples](#curl-examples)
- [OpenAI Python SDK](#openai-python-sdk)
- [Vercel AI SDK](#vercel-ai-sdk-openai-compatible-provider)
- [Gotchas](#gotchas)

Aitta is CSC's curated LLM inference service. It is **separate from Rahti**
(container hosting) but lives in the same CSC account ecosystem and shares
the CSC login. Aitta exposes an OpenAI-compatible HTTP API so existing
OpenAI clients (Python `openai`, Vercel AI SDK, LangChain, etc.) work
unchanged by pointing `baseURL` at Aitta.

- Web UI / model catalog: <https://aitta.csc.fi/>
- API docs: <https://aitta-api.csc.fi/docs>
- User docs: <https://aitta.csc.fi/page/docs>
- Auth (get / rotate token): <https://aitta-auth.csc.fi>

## Authentication

Tokens are issued **per user, per CSC project** (the JWT carries a
`lumiProjects` claim). To obtain or rotate: log in at <https://aitta.csc.fi/>
with CSC credentials and follow the **Generate token** link in the navigation
(the token service itself lives at <https://aitta-auth.csc.fi>). Regenerating
leaves the old token valid until its natural expiry.

Tokens are long-lived (~90 days) but **do expire**. The current expiry is
stored in `AITTA_TOKEN_EXPIRES`. Aitta returns 401 once expired; check
that env var before debugging deeper.

Send the token in the `Authorization` header:

```
Authorization: Bearer <AITTA_API_TOKEN>
```

Do NOT commit tokens to git. Keep the token in a private env store outside the
repository and let project `.env` files reference it.

## Environment variables

| Variable | Value / purpose |
|---|---|
| `AITTA_API_TOKEN` | Bearer token (JWT). User-bound. |
| `AITTA_API_BASE` | `https://aitta-api.csc.fi/openai` — point OpenAI SDK `baseURL` here. |
| `AITTA_API_ROOT` | `https://aitta-api.csc.fi` — root for Aitta-native endpoints (`/model`, `/status`). |
| `AITTA_PROJECT_ID` | CSC LUMI project id (e.g. `46XXXXXXX`). |
| `AITTA_TOKEN_EXPIRES` | ISO timestamp; check before assuming token is valid. |

## Endpoints

Aitta-native (HAL responses — prefer following `_links` over hardcoding):

| Method | Path | Purpose |
|---|---|---|
| GET | `/model` | List available models |
| GET | `/model/{model_id}` | Model details |
| GET | `/model/{model_id}/queue` | Queue length & processing time |
| POST | `/model/{model_id}/preload` | Wake an **Offline** model |
| GET | `/status` | Service health |
| GET | `/downtimes` | Scheduled downtimes |
| GET | `/worker`, `/worker/{model_id}` | Running workers |

OpenAI-compatible (under `/openai/v1/`):

| Method | Path | Purpose |
|---|---|---|
| GET | `/openai/v1/models` | List models (OpenAI format) |
| POST | `/openai/v1/chat/completions` | Chat completions |
| POST | `/openai/v1/embeddings` | Embeddings |

## Model catalog (snapshot — verify with `GET /model`)

Online (ready immediately):

- `meta-llama/Llama-3.3-70B-Instruct`
- `openai/gpt-oss-120b`

Offline (must be preloaded — first call after preload may queue):

- `LumiOpen/Llama-Poro-2-70B-Instruct` (Finnish/English/code, 70B)
- `LumiOpen/Poro-34B-chat`
- `google/gemma-3-27b-it`
- `Qwen/Qwen3-VL-30B-A3B-Thinking` (vision)
- `Qwen/Qwen3-Coder-Next`
- `mistralai/Ministral-3-14B-Reasoning-2512`
- `allenai/OLMo-7B-0724-Instruct`
- `TinyLlama/TinyLlama-1.1B-Chat-v1.0`

### Embedding models (verified live 2026-08-13)

Aitta **does** serve embeddings — two models, both with `capabilities: ["openai-embeddings"]`:

| Model | Base | Dims | Max tokens |
|---|---|---:|---:|
| `intfloat/multilingual-e5-large` | XLM-RoBERTa large, 100 languages | 1024 | **512** (`max_position_embeddings` 514) |
| `lightonai/modernbert-embed-large` | ModernBERT-large (English-pretrained) | 1024 | 8192 |

No Snowflake Arctic-Embed, no BGE, no Nomic, no OpenAI-compatible `text-embedding-*`.

⚠️ **Cold start is brutal.** A single 18-token embedding request against e5-large took
**80.3 s** end to end because the worker had to spin up. Aitta embeddings are usable for
batch jobs, **not** for a request-path call such as embedding a user's search query.
Preload first (`POST /model/{id}/preload`) and still do not depend on it interactively.

⚠️ e5-large's 512-token window truncates silently. Check your chunk token distribution
against it before choosing this model — no error is raised for over-long input.

## curl examples

```bash
# 1. List models
curl -H "Authorization: Bearer $AITTA_API_TOKEN" \
  "$AITTA_API_ROOT/model" | jq

# 2. Preload an Offline model (wait for worker spin-up)
curl -X POST -H "Authorization: Bearer $AITTA_API_TOKEN" \
  "$AITTA_API_ROOT/model/LumiOpen%2FLlama-Poro-2-70B-Instruct/preload"

# 3. Check queue
curl -H "Authorization: Bearer $AITTA_API_TOKEN" \
  "$AITTA_API_ROOT/model/LumiOpen%2FLlama-Poro-2-70B-Instruct/queue"

# 4. Chat completion (OpenAI-compatible)
curl -X POST "$AITTA_API_BASE/v1/chat/completions" \
  -H "Authorization: Bearer $AITTA_API_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "model": "meta-llama/Llama-3.3-70B-Instruct",
    "messages": [{"role": "user", "content": "Moi! Kuka olet?"}]
  }'
```

Model IDs contain `/` — URL-encode as `%2F` when used in path segments.

## OpenAI Python SDK

```python
import os
from openai import OpenAI

client = OpenAI(
    base_url=os.environ["AITTA_API_BASE"] + "/v1",
    api_key=os.environ["AITTA_API_TOKEN"],
)

resp = client.chat.completions.create(
    model="meta-llama/Llama-3.3-70B-Instruct",
    messages=[{"role": "user", "content": "Hei!"}],
)
print(resp.choices[0].message.content)
```

## Vercel AI SDK (OpenAI-compatible provider)

```ts
import { createOpenAICompatible } from "@ai-sdk/openai-compatible";
import { generateText } from "ai";

const aitta = createOpenAICompatible({
  name: "aitta",
  baseURL: `${process.env.AITTA_API_BASE}/v1`,
  apiKey: process.env.AITTA_API_TOKEN!,
});

const { text } = await generateText({
  model: aitta("meta-llama/Llama-3.3-70B-Instruct"),
  prompt: "Hei!",
});
```

## Gotchas

- **Offline models cold-start.** Call `POST /model/{id}/preload` first or
  the first chat-completion may time out / 503. `GET /model/{id}/queue`
  tells you how long to wait.
- **Token is user-bound**, not a service account. There is no way to
  issue a project-wide token — rotate per developer.
- **Token expiry is silent.** Check `AITTA_TOKEN_EXPIRES` when calls
  suddenly start returning 401.
- **HAL responses include `_links`.** Prefer following links from
  `/model` over hardcoding `/openai/v1/...` paths — Aitta may add new
  routes.
- **Not the same as Rahti.** Aitta has its own quota and account flow;
  having a Rahti project does not grant Aitta access (and vice versa).
- **Some models advertise their own `openai_api_url`** in `GET /model/{id}`.
  If a model 404s against `$AITTA_API_BASE/v1`, read that field and use the
  per-model URL rather than assuming one shared base.
