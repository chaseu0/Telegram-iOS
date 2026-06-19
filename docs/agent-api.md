# SweetGram Agent API

The Agent HTTP server listens on a configurable local port (default `8787`) and exposes Telegram data + LLM management endpoints over plain HTTP. All responses are JSON, CORS headers are set (`Access-Control-Allow-Origin: *`).

## LLM Configuration

### View current LLM config

```bash
curl http://localhost:8787/api/config/llm
```

### Set LLM config (OpenAI Compatible)

Replace placeholders with your own values:

```bash
curl -X POST http://localhost:8787/api/config/llm \
  -H "Content-Type: application/json" \
  -d '{
    "base_url": "https://hub.cnbita.com:9821",
    "model": "Qwen3.6-35B-A3B",
    "api_key": "sk-a13c8a1c60b5b53c2e921aed19f1fffa",
    "name": "CCSwitch LLM"
  }'
```

### Test connectivity

In the SweetGram Settings -> SweetGram AI, tap "Test Connection".

## Health

```bash
curl http://localhost:8787/health
```

## Contacts

### List contacts

```bash
curl http://localhost:8787/api/contacts
```

### Get contact messages (last N)

```bash
curl "http://localhost:8787/api/contacts/123456789/messages?limit=100"
```

### Get contact profile

```bash
curl http://localhost:8787/api/contacts/123456789/profile
```

### Get contact bio

```bash
curl http://localhost:8787/api/contacts/123456789/bio
```

### Extract group links from bio

```bash
curl http://localhost:8787/api/contacts/123456789/bio/groups
```

## Groups

### List groups

```bash
curl http://localhost:8787/api/groups
```

### Get group messages

```bash
curl "http://localhost:8787/api/groups/987654321/messages?limit=500"
```

### Get full group history

```bash
curl "http://localhost:8787/api/groups/987654321/messages?limit=10000"
```

### Preview group (last 50 messages)

```bash
curl http://localhost:8787/api/groups/987654321/preview
```

## Market Research Agent Workflow

Example for collecting seller info from an industry group:

1. Find relevant group from contact bio:
```bash
curl http://localhost:8787/api/contacts/123456789/bio/groups
```

2. Join/preview the group messages:
```bash
curl http://localhost:8787/api/groups/987654321/preview
```

3. Get full history:
```bash
curl "http://localhost:8787/api/groups/987654321/messages?limit=10000"
```

4. Use `/api/config/llm` to have AI summarize and extract market data.
