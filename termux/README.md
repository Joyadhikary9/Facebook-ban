# Termux client

This is an interactive Bash client for an authorized deployment of Social Security Cloud Pro. It makes real HTTPS requests and displays server responses; it does not generate analytics, submit Facebook reports, or simulate bot status. The API/backend is not included in this repository yet, so the routes below must be implemented by the cloud service before the corresponding menu options can work. A missing route or unavailable integration is displayed as an error, not reported as success.

## Install and run

In Termux:

```bash
pkg update
pkg install bash curl jq
chmod +x termux/social-security-cloud.sh
export SOCIAL_SECURITY_API_URL='https://your-deployed-api.example'
./termux/social-security-cloud.sh
```

You can omit the environment variable and enter the HTTPS API URL when prompted. The script refuses plain HTTP. Do not put passwords, bearer tokens, API keys, or other secrets in this script or in a public repository. Login credentials are prompted without echo and are sent to the server; the access token stays in the process memory and is not saved to disk. Use a trusted device and a short-lived, revocable token policy on the backend.

## Required REST API contract

All paths are relative to `/api/v1`. Requests and successful responses use JSON. Authenticated requests send `Authorization: Bearer <access-token>`.

| Method and path | Auth | Expected behavior |
| --- | --- | --- |
| `POST /auth/login` | No | Accept `{ "username": "...", "password": "..." }`; authenticate against the real identity provider and return `{ "accessToken": "..." }` only on success. |
| `POST /auth/logout` | Yes | Revoke/invalidate the current session/token and return success only after confirmation. |
| `GET /admin/dashboard/stats` | Yes | Return statistics the user is authorized to see, with unavailable data explicitly marked unavailable. |
| `GET /security/lookups?reference=...` | Yes | Perform only an authorized lookup using public or explicitly connected information; do not access private accounts. |
| `GET /reports` | Yes | Return report records and statuses; creating/submitting a report is intentionally not exposed by this client. |
| `GET /telegram/bots/status` | Yes | Return the status of bots/groups the authenticated user administers. |
| `GET /integrations/status` | Yes | Return configured integration health without exposing credentials or secret values. |

Backend requirements: enforce TLS, validate sessions and roles on every request, rate-limit and audit sensitive actions, redact credentials from logs, return accurate provider/API errors, and never claim an operation succeeded unless the upstream service confirms it. Store provider secrets only in server-side secret storage. Facebook/Meta access must use official authorized APIs and permissions; Telegram operations must be limited to bots and groups the operator administers. Do not implement mass reporting, automated engagement, or unauthorized actions.

The client expects login tokens in `accessToken` or `access_token`. All other responses are printed as JSON so the actual server response remains visible. This repository currently contains no backend, provider credentials, or deployed API; configure and test those independently with authorized accounts before relying on any feature.
