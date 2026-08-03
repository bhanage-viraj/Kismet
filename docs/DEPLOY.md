# Deploying Kismet to Railway

Vercel cannot host this service: it has no Java runtime, and the STOMP WebSocket
broker needs a long-lived process. Railway runs the existing Dockerfile.

## Prerequisites

1. A [Railway](https://railway.app) account
2. A MongoDB Atlas cluster with a connection string that includes the database
   name (`.../kismet?retryWrites=true&w=majority`)
3. An Atlas Network Access rule that allows Railway's outbound IPs — for a first
   deploy, `0.0.0.0/0` is fine; tighten later

## One-time setup

From `server/`:

```bash
railway login
railway init          # create or link a project
railway up            # first build; it will fail until variables are set
```

Then set the production variables (Railway → Variables, or via CLI):

```bash
railway variables set \
  JWT_SECRET='<output of: openssl rand -base64 48>' \
  APPLE_VERIFY_TOKEN=true \
  APPLE_CLIENT_ID=bhanageviraj.indeKismet,sanjivanand.IndeKismet \
  MONGODB_URI='mongodb+srv://USER:PASS@CLUSTER/kismet?retryWrites=true&w=majority' \
  CORS_ORIGINS='*'
```

Do **not** set `ALLOW_INSECURE_CONFIG`. The startup guard will refuse to boot if
`JWT_SECRET` is still the development default or Apple verification is off.

Redeploy after setting variables:

```bash
railway up
railway domain        # attach a public HTTPS hostname
```

## Health check

`GET https://<your-domain>/actuator/health` should return `{"status":"UP"}`.

Unauthenticated calls to protected routes return `401` with the usual JSON body.

## Pointing the iOS app at it

Set `APIConfig.baseURL` to `https://<your-domain>` (no trailing slash). The
WebSocket endpoint is `wss://<your-domain>/ws`.

## Notes

- Railway injects `PORT`; Spring Boot already reads `${PORT:8080}`.
- The STOMP broker is in-memory, so run a single replica. Scaling out needs a
  Redis or RabbitMQ relay first.
- Invite codes and blob TTLs are Mongo TTL indexes; Atlas will expire them.
