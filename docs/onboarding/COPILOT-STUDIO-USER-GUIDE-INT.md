# Using SFDCRead in Copilot Studio — User Guide (INT)

This guide is for people who want to use SFDCRead data in their copilot. You do not need to set up anything technical — the SFDCRead connector has already been published in the AMN-wide Power Platform environment. You just add it to your copilot and sign in once.

For installer or maintainer steps (app registration, secrets, gateway configuration), see `COPILOT-STUDIO-MCP-SERVER-INT.md` in this folder. That doc is not for end users.

> **Rollout note:** The exact Power Platform environment name and connector display name are filled in when the AMN-wide rollout completes. Where you see `<AMN-WIDE-ENVIRONMENT>` or `<SFDCRead Connector Name>` in this guide, use the values from the rollout announcement.

## What SFDCRead gives you

SFDCRead is a read-only window into a small, deliberately narrow set of Salesforce data exposed through AMN's API gateway. Your copilot can ask questions like "look up account X" or "list recent opportunities for Y" and SFDCRead answers from Salesforce.

A few things to set expectations:

- **Read-only.** You cannot create, update, or delete records through SFDCRead.
- **Narrow on purpose.** Only a curated set of objects and fields is exposed. If a field you need is not available, that is by design, not a missing feature — file a request rather than assume it is a bug.
- **You see what your account can see.** SFDCRead uses your AMN identity, so Salesforce permissions still apply.

## Before you start

You only need two things, and most AMN employees already have both:

1. Your normal AMN sign-in (`<your-name>@amnhealthcare.com`) — the one you use for email and Teams. Do not use a `.adm` account.
2. Permission to use SFDCRead. You do not need to verify this up front — just follow the steps. If you do not have permission, Step 3 will tell you clearly and the troubleshooting table at the bottom of this guide explains how to request it.

That is it. Skip ahead to Step 1.

## Step 1 — Open your copilot in the right environment

1. Go to https://copilotstudio.microsoft.com.
2. In the top-right environment switcher, select **`<AMN-WIDE-ENVIRONMENT>`**.
3. Open the copilot you want to add SFDCRead to (or create a new one).

If you do not see `<AMN-WIDE-ENVIRONMENT>` in the switcher, stop and resolve the access prerequisite above before continuing — adding tools in the wrong environment will not work.

## Step 2 — Add the SFDCRead tool

1. In your copilot, open the **Tools** tab.
2. Click **Add tool**.
3. In the tool picker, search for **`<SFDCRead Connector Name>`**.
4. Select it and click **Add to agent**.

You do not need to enter a Server URL, OAuth fields, client secret, or scope. Those are already configured on the published connector — that is the whole point of the AMN-wide publication.

## Step 3 — Sign in on first use

The first time you (or your copilot) actually use the tool, a connection popup appears.

1. In the connection dialog, click **Create** (or **Sign in**).
2. A browser popup opens. Sign in with your AMN daily-driver account.
3. If a consent screen appears, review the permissions and accept.

After this, your connection is saved and you will not be asked again unless your sign-in expires.

### If the popup closes itself in Chrome

AMN's managed Chrome can close the consent popup before sign-in finishes. The symptom is a generic "consent pop-up window has been closed unexpectedly" message. If this happens:

1. Cancel the current attempt.
2. Reopen https://copilotstudio.microsoft.com in **Microsoft Edge** (regular window, not InPrivate).
3. Retry the connection.

This is a browser issue, not an SFDCRead problem. If Edge also fails, see the troubleshooting table below.

## Step 4 — Try it

In the copilot's test pane (right side of the authoring canvas), ask a question that should hit SFDCRead. Examples:

- *"Look up the account named Contoso."*
- *"Show me recent opportunities for account 0011x000003ABCD."*
- *"What contacts are on account Acme?"*

What you should see: the copilot replies with data from Salesforce, and the activity panel shows the SFDCRead tool being called.

If the copilot says it does not have access to that data or returns an error, see troubleshooting next.

## If something doesn't work

These are the things that actually go wrong for users. Match the message you see to the row, then take the action listed.

| What you see | What it means | What to do |
|---|---|---|
| "You don't have permission" or any "MCP.Read" / "access denied" error | You are signed in, but you have not been granted SFDCRead access yet | Request access through the SFDCRead support contact published with the rollout announcement. After you are granted access, sign out of Copilot Studio and back in to pick up the change |
| "Unable to sign in" or sign-in loop | Your AMN session expired or got into a stuck state | Sign out of Copilot Studio entirely, close the browser, sign back in |
| Consent popup closes immediately (Chrome) | Managed-Chrome extension policy closes the popup | Switch to Edge (see Step 3) |
| `<AMN-WIDE-ENVIRONMENT>` is not in the environment switcher | You do not have access to the environment yet | Request access through the SFDCRead support contact — this is separate from the data-access permission above and is usually granted together |
| Copilot says "no results" for data you know exists | Your Salesforce permissions may not cover that record, or the field is not exposed by SFDCRead | Confirm with someone who has the same Salesforce role; if they see it too and SFDCRead does not, file a request |
| Tool not visible in the **Add tool** picker | You are in the wrong Power Platform environment | Re-check the environment switcher (Step 1) shows `<AMN-WIDE-ENVIRONMENT>` |
| Everything was working yesterday, all users broken today | This is a platform-side outage, not your setup | Contact the SFDCRead support channel — do not try to recreate the connection |

For anything not in this table, capture: the exact message, the time, and your username. Send those to the SFDCRead support contact published with the rollout announcement.

## What SFDCRead does **not** do

So you do not waste time trying:

- It does not write to Salesforce.
- It does not expose every Salesforce object or field — only the curated set.
- It does not bypass your Salesforce permissions.
- It does not give your copilot access to other AMN systems (HRIS, ATS, etc.) — those would be separate connectors.

If you have a use case that needs any of the above, that is a new request for the platform team, not a configuration step in this guide.
