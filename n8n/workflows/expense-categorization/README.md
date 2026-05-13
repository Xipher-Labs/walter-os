# Workflow: Expense Categorization — Email to Google Sheets

## Use case

Forward expense-related emails (receipts, invoices, bank notifications) to
a dedicated inbox. n8n polls the inbox, extracts merchant name, amount, and
date using an LLM, maps to a category, and appends a row to a Google Sheet
for personal finance tracking.

Useful for: automating personal expense tracking without a paid app.
Replaces manual receipt logging with email-forward-and-forget.

## Prerequisites

**n8n credentials required:**

- Gmail OAuth 2.0 (gmail.readonly scope) or IMAP credentials for your email
- LLM API key (Anthropic, OpenAI, or LiteLLM proxy)
- Google Sheets OAuth 2.0 (spreadsheets scope)

**External services required:**

- Gmail account (or any IMAP-compatible email provider)
- Google Sheets spreadsheet with appropriate columns (see schema below)
- LLM API access

**Google Sheet column schema:**

```
Date | Merchant | Amount | Currency | Category | Raw Subject | Source Email
```

## Customization points

- `EXPENSE_INBOX_LABEL`: Gmail label applied to expense emails (e.g., `expenses`)
- `EXPENSE_EMAIL_ADDRESS`: dedicated forwarding address or filter pattern
- `SPREADSHEET_ID`: Google Sheets document ID from the URL
- `SHEET_NAME`: tab name within the spreadsheet (default: `Expenses`)
- `CATEGORY_LIST`: your personal expense categories (Food, Transport, etc.)
- `POLL_INTERVAL`: how often to check for new emails (default: every 30 minutes)
- `CURRENCY_DEFAULT`: default currency if not detected from email

## Env vars

| Variable | Description | Example value |
|---|---|---|
| `LLM_API_KEY` | LLM API key | `sk-ant-...` |
| `LLM_ENDPOINT` | LLM endpoint (or LiteLLM proxy) | `http://localhost:4000/v1` |
| `SPREADSHEET_ID` | Google Sheets document ID | `1BxiM...` |
| `SHEET_NAME` | Sheet tab name | `Expenses` |

Store Gmail and Google Sheets credentials in n8n's OAuth credential store.

## Walter-OS contexts

`personal`

## Node overview

```
[Schedule Trigger]
    → Every 30 minutes

[Gmail: Get Messages]
    → List unread messages with label EXPENSE_INBOX_LABEL
    → Mark as read after fetching

[Loop: For Each Email]
    → Iterate over fetched messages

[HTTP Request: LLM Extract]
    → Prompt: "Extract merchant, amount, currency, and date from this
      email. Subject: {subject}. Body: {body}. Return JSON."
    → Model: REPLACE_WITH_MODEL

[Code: Parse + Categorize]
    → Parse LLM JSON output
    → Map merchant or description to CATEGORY_LIST via keyword matching
    → Fall back to "Uncategorized" if no match

[Google Sheets: Append Row]
    → Append one row: [date, merchant, amount, currency, category,
      raw_subject, source_email]
    → Spreadsheet: SPREADSHEET_ID, Sheet: SHEET_NAME
```

## Authoring steps

1. Create a Gmail label called `expenses` (or your preferred label name).
2. Set up a Gmail filter to apply this label to forwarded receipt emails.
3. Create a Google Sheet with the columns listed in the schema above.
4. In n8n, create a Schedule Trigger running every 30 minutes.
5. Add a Gmail node to fetch unread messages with the expense label.
6. Add a Loop Over Items node to process each email.
7. Add an HTTP Request node to call your LLM with the extraction prompt.
8. Add a Code node to parse the response and apply category mapping.
9. Add a Google Sheets node to append the row.
10. Test by forwarding a sample receipt email to the inbox.
11. Export and save as `workflow.json` in your private overlay repo.

## Privacy note

This workflow sends email content (including merchant names and amounts) to
an external LLM API. If you prefer not to send this data externally, use a
local LLM via Ollama and point the LiteLLM proxy at it. Amounts and merchant
names are generally not PHI, but review what your expense emails contain
before connecting this workflow.
