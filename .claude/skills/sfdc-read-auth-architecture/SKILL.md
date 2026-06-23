---
name: sfdc-read-auth-architecture
description: Use when designing or troubleshooting authentication for SFDCRead APIM to Salesforce integration, especially when choosing between client credentials, JWT bearer, and PKCE plus refresh token broker patterns.
---

# SFDCRead Auth Architecture

## Overview
This skill standardizes auth decisions for the SFDCRead gateway. It is optimized for the current project requirement: many upstream clients, one APIM identity, and a least-privileged read-only Salesforce integration user.

## When to Use
Use this skill when:
- You need to choose an auth pattern for APIM to Salesforce.
- Client credentials fails or is not allowed by Salesforce app policy.
- You need a single integration identity for hundreds of clients.
- You are updating APIM policy, named values, or test harness auth logic.

Do not use this skill for:
- Frontend/OAuth UX design.
- Non-Salesforce backends.

## Decision Flow
1. Confirm target endpoint type:
- Salesforce standard REST API
- Salesforce Hosted MCP endpoint

2. Test whether app-only flow is allowed for that endpoint in the org policy.

3. Choose pattern:
- If allowed: use app-only flow with one read-only integration user.
- If not allowed: use one-time interactive PKCE bootstrap plus refresh-token broker.

## Recommended Patterns
1. Preferred when allowed: Client Credentials
- Single integration user.
- No interactive login during runtime.
- Strong fit for APIM funnel model.

2. Alternative when allowed: JWT Bearer
- Single integration user.
- Certificate-based server-to-server token exchange.
- Good if client credentials is blocked but JWT bearer is permitted.

3. Fallback when app-only is blocked: PKCE + Refresh Token Broker
- One-time interactive consent for the integration user.
- Store refresh token in Key Vault.
- Broker/APIM refreshes access token as needed.

## Required Security Baseline
- Dedicated integration user (non-admin).
- Read-only permission set only.
- Minimum object and field scope.
- Secrets and refresh tokens in Key Vault.
- APIM inbound controls: JWT validation, per-client quotas, and rate limits.

## Verification Checklist
1. Token endpoint test
- Execute token request for chosen grant type.
- Capture exact HTTP status and error body.

2. API reachability test
- Call target Salesforce endpoint with returned access token.
- Confirm real endpoint response behavior (not just token issuance).

3. APIM end-to-end test
- Use current smoke harness through APIM.
- Verify expected success/failure with correlation IDs.

4. Final truth gate
- Mark as working only when real client flow works end-to-end.

## Project-Specific Notes
- This repo currently contains mixed historical notes across docs.
- Before changing policy behavior, align docs and policy in the same PR.
- Keep temporary triage docs out of permanent docs unless explicitly requested.

## Companion Artifacts
- TOKEN-REQUEST-TEMPLATES.md: Exact token request templates for client credentials, JWT bearer, authorization code with PKCE, and refresh token grants.
- APIM-REFRESH-BROKER-SNIPPETS.xml: APIM policy fragments for refresh-token broker implementation.
- RUNBOOK-INT-PROD.md: Step-by-step int/prod rollout and validation runbook for the current environment layout.
