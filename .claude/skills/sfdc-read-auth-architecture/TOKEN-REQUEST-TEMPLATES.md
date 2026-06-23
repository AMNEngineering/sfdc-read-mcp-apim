# Salesforce Token Request Templates

Use My Domain token endpoint for each environment:
- Int sandbox: https://amnhealthcare--qa.sandbox.my.salesforce.com/services/oauth2/token
- Prod: https://<prod-my-domain>.my.salesforce.com/services/oauth2/token

## 1) Client Credentials

```bash
curl -sS -X POST "$SF_TOKEN_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_id=$SF_CLIENT_ID" \
  --data-urlencode "client_secret=$SF_CLIENT_SECRET"
```

Expected success shape:
```json
{
  "access_token": "...",
  "token_type": "Bearer",
  "instance_url": "https://...",
  "scope": "..."
}
```

## 2) JWT Bearer

```bash
curl -sS -X POST "$SF_TOKEN_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer" \
  --data-urlencode "assertion=$SF_SIGNED_JWT"
```

JWT payload baseline:
- iss = consumer key/client_id
- sub = integration user username
- aud = login host or My Domain (org policy dependent)
- exp = short lived (for example now + 180s)

## 3) Authorization Code + PKCE (one-time bootstrap)

Token exchange after user consent:

```bash
curl -sS -X POST "$SF_TOKEN_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=authorization_code" \
  --data-urlencode "client_id=$SF_CLIENT_ID" \
  --data-urlencode "code=$SF_AUTH_CODE" \
  --data-urlencode "code_verifier=$PKCE_CODE_VERIFIER" \
  --data-urlencode "redirect_uri=$SF_REDIRECT_URI"
```

Store returned refresh_token in Key Vault for broker usage.

## 4) Refresh Token (runtime broker flow)

```bash
curl -sS -X POST "$SF_TOKEN_URL" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  --data-urlencode "grant_type=refresh_token" \
  --data-urlencode "client_id=$SF_CLIENT_ID" \
  --data-urlencode "client_secret=$SF_CLIENT_SECRET" \
  --data-urlencode "refresh_token=$SF_REFRESH_TOKEN"
```

## 5) Token Introspection Quick Checks

Use errors to route decisions:
- unsupported_grant_type: flow blocked for app/policy
- invalid_client: key/secret/policy mismatch
- invalid_scope: app scopes do not authorize request
- invalid_grant: auth code/refresh token invalid, revoked, or wrong domain

## 6) Safe Logging

Never log raw secrets, refresh tokens, or full bearer tokens.
Log only:
- token endpoint host
- grant type
- status code
- correlation id
- trimmed error fields
