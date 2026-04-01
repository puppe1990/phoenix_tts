# API HTTP

Documentação da API HTTP do `phoenix_tts` para uso por outros sistemas.

Especificação OpenAPI:

```text
docs/openapi.yaml
```

Base local:

```text
http://localhost:4000/api
```

## Autenticação

Se `API_AUTH_TOKEN` estiver configurado, todas as rotas da API exigem header `Authorization` no formato:

```text
Authorization: Bearer seu-token
```

Se `API_AUTH_TOKEN` não estiver definido, a API permanece aberta.

## CORS

As origens permitidas são controladas por `API_ALLOWED_ORIGINS`.

Exemplo:

```bash
API_ALLOWED_ORIGINS="https://app.exemplo.com,http://localhost:3000"
```

A API responde preflight `OPTIONS` automaticamente.

## Variáveis de ambiente

```bash
API_AUTH_TOKEN=seu-token-forte
API_ALLOWED_ORIGINS=https://app.exemplo.com,http://localhost:3000
ELEVENLABS_API_KEY=...
ELEVENLABS_BASE_URL=https://api.elevenlabs.io
ELEVENLABS_DEFAULT_OUTPUT_FORMAT=mp3_44100_128
```

## Rotas

### `GET /voices`

Lista vozes disponíveis. O app tenta sincronizar com a ElevenLabs e usa o cache local como fallback.

Exemplo:

```bash
curl http://localhost:4000/api/voices \
  -H "Authorization: Bearer seu-token"
```

Resposta:

```json
{
  "data": [
    {
      "id": "voice_br",
      "name": "Narradora BR",
      "category": "premade",
      "labels": {
        "accent": "pt-BR"
      }
    }
  ]
}
```

### `GET /models`

Lista modelos de TTS compatíveis.

```bash
curl http://localhost:4000/api/models \
  -H "Authorization: Bearer seu-token"
```

### `GET /subscription`

Retorna visão resumida da assinatura e consumo.

```bash
curl http://localhost:4000/api/subscription \
  -H "Authorization: Bearer seu-token"
```

Resposta:

```json
{
  "data": {
    "tier": "creator",
    "status": "active",
    "used_credits": 1250,
    "total_credits": 10000,
    "remaining_credits": 8750,
    "next_reset_unix": 1743086400
  }
}
```

### `GET /history`

Lista histórico remoto da ElevenLabs.

Query params suportados:

- `page_size`
- `start_after_history_item_id`

```bash
curl "http://localhost:4000/api/history?page_size=10" \
  -H "Authorization: Bearer seu-token"
```

### `GET /history/:history_item_id/audio`

Faz stream do áudio remoto do item de histórico.

Query params:

- `download=1` força `content-disposition: attachment`

```bash
curl http://localhost:4000/api/history/hist_123/audio \
  -H "Authorization: Bearer seu-token" \
  --output history.mp3
```

### `GET /generations`

Lista gerações salvas localmente.

```bash
curl http://localhost:4000/api/generations \
  -H "Authorization: Bearer seu-token"
```

Resposta:

```json
{
  "data": [
    {
      "id": 1,
      "text": "Texto salvo localmente",
      "voice_id": "voice_br",
      "model_id": "eleven_multilingual_v2",
      "output_format": "mp3_44100_128",
      "language_code": "pt",
      "quality_preset": "high",
      "stability": 0.35,
      "similarity_boost": 0.9,
      "style": 0.15,
      "speaker_boost": true,
      "character_count": 64,
      "content_type": "audio/mpeg",
      "request_id": "req_local_123",
      "remote_history_item_id": "hist_local_123",
      "audio_url": "/api/generations/1/audio",
      "inserted_at": "2026-04-01T22:00:00Z",
      "updated_at": "2026-04-01T22:00:00Z"
    }
  ]
}
```

### `GET /generations/:id`

Retorna uma geração local específica.

```bash
curl http://localhost:4000/api/generations/1 \
  -H "Authorization: Bearer seu-token"
```

### `GET /generations/:id/audio`

Faz stream do áudio salvo localmente.

Query params:

- `download=1` força download

```bash
curl http://localhost:4000/api/generations/1/audio \
  -H "Authorization: Bearer seu-token" \
  --output generation.mp3
```

### `POST /generations`

Cria uma nova geração de áudio e persiste o resultado localmente.

Body JSON:

- `text` obrigatório
- `voice_id` obrigatório
- `model_id` obrigatório
- `output_format` obrigatório
- `language_code` opcional
- `quality_preset` opcional: `high`, `balanced`, `consistent`
- `stability` opcional: `0.0` a `1.0`
- `similarity_boost` opcional: `0.0` a `1.0`
- `style` opcional: `0.0` a `1.0`
- `speaker_boost` opcional: `true` ou `false`

Exemplo:

```bash
curl -X POST http://localhost:4000/api/generations \
  -H "Authorization: Bearer seu-token" \
  -H "Content-Type: application/json" \
  -d '{
    "text": "Teste de áudio para integração externa.",
    "voice_id": "voice_br",
    "model_id": "eleven_multilingual_v2",
    "output_format": "mp3_44100_128",
    "language_code": "pt",
    "quality_preset": "high"
  }'
```

Resposta:

```json
{
  "data": {
    "id": 12,
    "text": "Teste de áudio para integração externa.",
    "voice_id": "voice_br",
    "model_id": "eleven_multilingual_v2",
    "output_format": "mp3_44100_128",
    "language_code": "pt",
    "quality_preset": "high",
    "stability": 0.35,
    "similarity_boost": 0.9,
    "style": 0.15,
    "speaker_boost": true,
    "character_count": 48,
    "content_type": "audio/mpeg",
    "request_id": "req_api_123",
    "remote_history_item_id": "hist_api_123",
    "audio_url": "/api/generations/12/audio",
    "inserted_at": "2026-04-01T22:00:00Z",
    "updated_at": "2026-04-01T22:00:00Z"
  }
}
```

## Erros

### `401 Unauthorized`

Quando o token está ausente ou inválido:

```json
{
  "error": "unauthorized"
}
```

### `404 Not Found`

Quando o recurso não existe:

```json
{
  "error": "not_found"
}
```

### `422 Unprocessable Entity`

Quando os parâmetros de geração são inválidos:

```json
{
  "errors": {
    "text": ["can't be blank"],
    "voice_id": ["can't be blank"],
    "model_id": ["can't be blank"]
  }
}
```

### `502 Bad Gateway`

Quando a ElevenLabs ou integração externa retorna erro:

```json
{
  "error": "mensagem do erro"
}
```
