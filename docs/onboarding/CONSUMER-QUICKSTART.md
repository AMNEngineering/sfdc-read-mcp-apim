# SFDCRead MCP — Consumer Quickstart (Power Automate + Copilot Studio)

Use this quickstart if you are an **AI user or maker** who wants to call SFDCRead from a Power Automate flow or Copilot Studio agent you're building. This doc walks the actual UX end-to-end — with the exact strings you'll see on screen and what to do when the connection setup misbehaves. It is not the ops runbook that publishes the connector; it assumes the connector already exists in your environment.

If you are the ops engineer who publishes the connector (once, per environment, under change control), see:
- `POWER-AUTOMATE-CUSTOM-CONNECTOR-INT.md` — creating and publishing the Custom Connector
- `IDENTITY-BOOTSTRAP-INT.md` — the identity surface behind the connector

## What SFDCRead lets you do

SFDCRead exposes read-only Salesforce access as an **MCP (Model Context Protocol) tool**. When you install it on your Copilot Studio agent or use it in a Power Automate flow, it provides these actions to your assistant:

- `getUserInfo` — the Salesforce identity being used for reads (a service account, not your Entra identity — details below)
- `getObjectSchema` — describes the shape of a Salesforce object (fields, types) for supported objects
- `soqlQuery` — runs a bounded SOQL query
- `listRecentSobjectRecords` — the "recent" list a user just viewed in Salesforce, per object type
- `getRelatedRecords` — pulls child records for a parent (e.g., Contacts on an Account)

**Important boundary:** `Account` is **excluded** by design. Any request for Account schema or a SOQL query touching Account returns `sObject type 'Account' is not supported`. That is not a bug — the APIM surface intentionally narrows what's callable. If you need Account data, that is a separate scope discussion — do not treat the "not supported" response as something to work around.

## Prerequisites — what you need before starting

You don't need to configure Entra, app registrations, or Key Vault. You do need three things in place:

1. **You're signed in with your daily-driver AMN account** (`<your-name>@amnhealthcare.com`). Not an `.adm` break-glass account.
2. **You have the SFDCRead MCP.Read role.** If you don't, the connection setup will succeed but your first tool call will return `User does not have MCP.Read role`. That's the signal to request access — see "Getting help" at the bottom.
3. **You're in the right Power Platform environment.** The connector is published per-environment. If you don't see it, you're either in the wrong environment or it hasn't been published where you are. Also see "Getting help."

Do NOT try to fix any of these three yourself by editing app registrations, group memberships, or environment settings. Route through the named contacts below.

---

# Path A: Copilot Studio agent

Use this path if you are building a Copilot Studio agent (an AI assistant) and want it to be able to answer SFDCRead-related questions.

## A1. Confirm the tool is available in your environment

1. Open Copilot Studio. Confirm the environment picker (top-right) shows the environment where the SFDCRead connector was published.
2. Left nav → **Tools**.
3. In the tools list, look for `SFDCRead INT MCP`. It should show:
   - Type: `Custom Connector`
   - Status: `Ready`

**Not there?** The connector hasn't been published to this environment — see "Getting help."

## A2. Install the tool on your agent

1. Left nav → **Agents**.
2. Open your agent (or create one with **Create blank agent**).
3. Open the agent's Tools / Actions surface (the exact label depends on your UI version — look for a section that lists installed tools with an add / plus button).
4. Add `SFDCRead INT MCP` from the tool list.
5. Save the agent. Return to the Tools list — the tool should now show `Installed on: <your agent name>`.

## A3. First-run connection setup — the messy part

The first time your agent tries to call SFDCRead, Copilot Studio has to set up a delegated OAuth connection under your identity. The UX for this is not obvious — walk through it deliberately.

### A3.1. Trigger the connection prompt

1. In your agent, open the **Test your agent** pane (right-hand side; click the Test button if it's collapsed).
2. Type a prompt that will exercise the tool. A good first test:

   > Get my Salesforce user info

3. Expected first-run response:

   > Let's get you connected first, and then I can find that info for you. **Open connection manager** to verify your credentials.

4. Click **Open connection manager**. A new page opens (or side-panel) titled **Manage your connections**.

### A3.2. Read the connection status carefully

On the Manage your connections page you'll see a row for `SFDCRead INT MCP` with a status column. The possible values matter — they each need a different action:

| Status | What it means | What to do |
|---|---|---|
| **Not connected** | No connection has ever been set up under your identity | Click **Connect**. Sign-in popup opens. Sign in as your daily-driver account and complete any consent prompt. |
| **Stale** | A connection existed but the token expired or the connector's config changed since. This is normal — it doesn't mean anything is broken. | Click **Review**. In most cases no popup opens — Copilot Studio silently refreshes the token using your existing Copilot Studio session. Wait for the row to flip to **Connected**. |
| **Connected** | Ready to go | Return to the agent test pane. |
| **Expired** | The refresh token itself expired (rare for daily-active users) | Click **Reconnect**. Full sign-in popup opens. |
| **Deactivated** | Admin disabled this connection | Not something you fix yourself. See "Getting help." |

### A3.3. Return to the agent and retry

1. Go back to the agent's test pane.
2. Click **Retry** on the earlier message (or re-type "Get my Salesforce user info").
3. Expected response — a formatted table of Salesforce user details. Key things you should see:
   - `Display Name: CopilotStudio Integration` (or similar service-account name)
   - `Email: sfdcadmin@amnhealthcare.com` (or similar service-account email)
   - `Local Time: Wednesday, 2:49 PM` (or whatever the actual current time is)

**Why the identity is not you:** the Entra token proves *you* have the MCP.Read role at the APIM edge; APIM then swaps in Salesforce's own service credentials to actually make the read. Salesforce sees a service account. This is intentional — the surface exists to limit what Salesforce identity data can leave the org.

## A4. When the popup or connection setup misbehaves

The connection setup is where 90% of user friction lives. Read this section top-to-bottom before assuming your setup is broken.

### Popup closes immediately or "consent pop-up window has been closed unexpectedly"

Most common cause: **enterprise-managed Chrome** with an extension policy that closes third-party auth popups.

1. Close Chrome.
2. Reopen Copilot Studio in **Edge** (regular window, not InPrivate).
3. Confirm Edge allows popups and third-party cookies for these hosts:
   - `copilotstudio.microsoft.com`
   - `login.microsoftonline.com`
   - `global.consent.azure-apim.net`
4. Retry the Connect / Review action.

If Chrome is mandated by policy on your workstation, escalate the policy exception through IT — that is a separate workstream and not something to work around locally.

### Popup opens but hangs on `login.microsoftonline.com`

Most common cause: **Zscaler VPN + AMN corp broker** interfering with the OAuth handshake. Well-documented internally. Two fallbacks:

1. Try Edge instead of Chrome (Zscaler behaves differently across browsers).
2. If Edge also hangs, escalate — do not paste your credentials into an alternate flow.

### "Stale" status keeps returning after Review

If Review doesn't produce a **Connected** state on the second try, this typically means the connector's OAuth values were changed by ops recently (a client secret rotation, for example) and your session doesn't match the new config. See "Getting help."

### Agent returns "Let's get you connected first" over and over even though the connection shows Connected

Two things to try:

1. Sign out of Copilot Studio (top-right avatar → Sign out), close the browser, sign back in.
2. Verify the environment picker (top-right) hasn't drifted — the connection lives in a specific environment; if you switched environments, the connection doesn't follow.

### Agent replies with the raw JSON of the SF response, not a formatted table

Not a bug. The agent's response formatting depends on its system instructions. If you want prettier formatting, add explicit instructions to the agent ("When returning Salesforce data, render it as a markdown table"). This has nothing to do with the connection or the tool itself.

## A5. Verifying it actually worked

You can only claim end-to-end success if:

1. The agent's response contains real data (a name, a timestamp, a record ID — not a canned "let's get you connected" message).
2. The timestamp is fresh — `userTimeAndLocale.localTimeIso` should be within a minute of when you sent the prompt.
3. There's no error banner or tool-invocation trace showing 401 / 403 / 406.

Save the transcript as evidence if you're validating for an ops story.

---

# Path B: Power Automate flow

Use this path if you are building a Power Automate flow (a workflow) that needs to call SFDCRead as part of a business process.

## B1. Confirm the connector is available in your environment

1. Open Power Automate. Environment picker (top-right) shows the correct environment.
2. Left nav → **Data → Custom connectors** (or **Discover** → **Custom connectors** in newer UI).
3. Look for `SFDCRead INT MCP` in the list. Status column shows something like `Ready` or `Enabled`.

**Not there?** The connector hasn't been shared to you or your environment — see "Getting help."

## B2. Use the connector in a flow

1. Create or open a flow.
2. Add a new action. In the action picker's search, type `SFDCRead`. The custom connector should appear.
3. Choose the operation. For SFDCRead the primary operation is `Invoke MCP` (MCP protocol invocation).

Note: because `Invoke MCP` runs in MCP protocol mode, its request/response shape in the designer looks empty — no obvious fields to fill in. That is correct. The Power Automate runtime injects the MCP JSON-RPC body from the surrounding agent context, not from designer inputs. **If you're not driving this from an AI-agentic surface, the raw `Invoke MCP` action is not usable as a data-plumbing step.** Use Copilot Studio (Path A) if you want AI-driven consumption.

For non-AI flows: SFDCRead does not currently expose non-MCP REST operations. If you have a business flow that needs a direct read (e.g., "on trigger X, look up Contact by email") — that's a scope discussion with ops, not something to build around the MCP surface.

## B3. First-run connection setup

Same UX shape as Copilot Studio, different location:

1. When you first drop the action, Power Automate prompts for a connection: **My connections → + New connection**.
2. Sign in with your daily-driver account.
3. **Watch the sign-in popup URL** — this is the key signal:
   - **Good:** `https://login.microsoftonline.com/6232c2ec-fa42-4f27-92cd-787913fba489/oauth2/v2.0/authorize?...` (tenant-scoped v2 endpoint)
   - **Bad:** `https://login.microsoftonline.com/common/oauth2/authorize?...` (v1 common tenant) — connector was misconfigured by ops, see "Getting help"
4. Complete consent if prompted, close the popup, verify the connection appears in the connections list with status **Connected**.

## B4. Do not test via the connector's own "Test" tab

If you open the Custom Connector's edit surface (as opposed to using the connector from a flow) and try to invoke the operation from the connector's Test tab, you will get:

```json
{"error":{"code":406,"message":"Accept header must include both application/json and text/event-stream"}}
```

**This is expected.** The Test tab is not an MCP client — it sends a plain HTTP POST without the `Accept: text/event-stream` header that MCP's streamable-HTTP transport requires. Getting a 406 from the Test tab does not mean the connector is broken. It means the Test tab is the wrong instrument. Use Copilot Studio (Path A) to actually invoke the MCP tool.

## B5. Common failure modes in flow context

| Symptom | Likely cause | Action |
|---|---|---|
| Connection popup won't open | Corp-managed Chrome extension policy | Switch to Edge; check popup + cookie settings for the three hosts listed in A4 |
| Popup opens on `/common/` URL | Connector's Security tab is misconfigured by ops | See "Getting help" — do not try to fix by editing the connector; you'll break other users |
| Action fails with `AADSTS65001 consent required` | Your identity has not been pre-authorized for this scope | See "Getting help" |
| Action returns 403 `User does not have MCP.Read role` | Missing group membership | See "Getting help" |
| Action returns 406 (Accept header) | You invoked from the Test tab, not a real flow | Move the action into a running flow instead of using the connector's Test surface |

---

# Getting help

Do not raise a support ticket in ITSM for these. This surface is owned by the Ops Engineering team internally.

| Situation | Contact |
|---|---|
| "The connector isn't in my environment" | AMN Ops Engineering — request environment provisioning for SFDCRead |
| "I get 403 User does not have MCP.Read role" | AMN Ops Engineering — request MCP.Read role assignment; provide your `<your-name>@amnhealthcare.com` UPN |
| "AADSTS65001 consent required" | AMN Ops Engineering — this indicates pre-authorization gap in the app reg |
| "Popup opens on `/common/` URL" | AMN Ops Engineering — this is a connector misconfiguration on their side |
| Anything else that looks like the connector is broken | AMN Ops Engineering — reference the Story AB#513441 track that owns SFDCRead |

When contacting Ops Engineering, include:
- Your environment ID (from the URL, e.g. `2c2b2771-...`)
- Your daily-driver UPN
- A screenshot of the error message with its full text visible
- The name of the connector (`SFDCRead INT MCP`) and INT / prod scope

Do not include:
- Client secrets
- Bearer tokens (even expired)
- Full URL bars with query-string tokens visible (redact the `code=` parameter)

---

# Appendix — why the UX is like this

Two design choices produce most of the friction you'll hit:

1. **Delegated OAuth, not a service account.** Every call is made under YOUR identity so the role check (`MCP.Read`) actually protects the surface. If we used a service account, anyone with access to the connector could read Salesforce data with no user-level authorization. The tradeoff: first-time consent, occasional refresh prompts, "Stale" statuses when things change.
2. **MCP protocol mode.** The connector is annotated `x-ms-agentic-protocol: mcp-streamable-1.0`, which puts Power Automate's Custom Connector into "MCP tool" mode. This changes several UI behaviors — empty designer inputs, Test tab returning 406, tool auto-discovery in Copilot Studio. It is not a bug when the designer looks empty or the Test tab misbehaves; that surface is being consumed by AI hosts, not typed against by hand.

If either of these is a blocker for a specific use case, that is a scope conversation with Ops — bring the use case, don't try to bypass the protection at the connector level.
