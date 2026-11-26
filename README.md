# Deploy and Host Whatomate on Railway

[![Deploy on Railway](https://railway.com/button.svg)](https://railway.com/new/template/whatsapp-business?referralCode=sLjDXb&utm_medium=integration&utm_source=button&utm_campaign=whatomate)

Whatomate is an open-source WhatsApp Business platform built on Meta's official WhatsApp Cloud API. It gives a team one shared inbox for every WhatsApp conversation, with real-time chat, agent teams and assignment, canned replies with `/shortcuts`, and contact tags. On top of that come Meta-approved message templates, bulk campaigns with retries, keyword auto-replies and branching chatbot flows, AI replies from OpenAI, Anthropic or Google, outbound webhooks, an API, analytics, and fine-grained roles across several organizations. This template runs Whatomate 0.1.1-beta-0.18 on Railway with Postgres, a persistent Redis queue, file storage on a volume, and the first admin account ready on boot.

## About Hosting Whatomate

Deploy, wait for the green check, and open the Railway domain. Sign in with `WHATOMATE_DEFAULT_ADMIN__EMAIL` (set it to your email before deploying) and the generated `WHATOMATE_DEFAULT_ADMIN__PASSWORD`, both on the Whatomate service's Variables tab. Change the password in your profile afterwards; the variable is only used to create the account on the first boot.

**Connecting WhatsApp:** you need a Meta developer app with the WhatsApp product, a WhatsApp Business account and a phone number. In Whatomate, open Settings > Accounts and add the phone number ID, business account ID and access token from Meta. Then in Meta's app dashboard, under WhatsApp > Configuration, set:

- **Callback URL:** `https://your-app.up.railway.app/api/webhook`
- **Verify token:** the value of `WHATOMATE_WHATSAPP__WEBHOOK_VERIFY_TOKEN` from the Variables tab

and subscribe to the `messages` field. Incoming messages then appear in the inbox live. Add the app secret to the account in Whatomate as well, so incoming webhooks are checked against Meta's signature.

**Your data:** conversations, contacts, templates and settings are in the Postgres service. Uploaded media and IVR audio are on the Whatomate volume at `/data`. The message and campaign queue is in Redis, which writes to its own volume, so queued jobs survive a restart. Redeploys and upgrades keep all of it. WhatsApp access tokens are encrypted in the database with `WHATOMATE_APP__ENCRYPTION_KEY`, so never change that variable once accounts are connected.

**Custom domain:** add it under the Whatomate service's Settings > Networking, set `WHATOMATE_SERVER__PUBLIC_URL=https://chat.example.com` (scheme and host only), redeploy, and update the callback URL in Meta. The Railway domain keeps working.

**More settings:** every option in [Whatomate's configuration](https://shridarpatil.github.io/whatomate/getting-started/configuration/) can be set as a variable: `WHATOMATE_`, then the section and the key joined by a double underscore. For example, `WHATOMATE_STORAGE__TYPE=s3` with `WHATOMATE_STORAGE__S3_BUCKET`, `WHATOMATE_STORAGE__S3_REGION`, `WHATOMATE_STORAGE__S3_KEY` and `WHATOMATE_STORAGE__S3_SECRET` moves media to S3. A full config file at `/data/config.toml` also works; variables still override it.

## Common Use Cases

- A shared WhatsApp inbox for a support or sales team, with assignment and canned replies
- Order updates, reminders and announcements sent as approved template campaigns
- A WhatsApp chatbot that answers common questions and hands over to an agent
- AI-drafted replies to customer messages using your own OpenAI, Anthropic or Google key
- Pushing WhatsApp conversations into a CRM or helpdesk through webhooks and the API

## Dependencies for Whatomate Hosting

- Postgres (included)
- Redis (included)
- A Meta developer app with the WhatsApp Cloud API and a business phone number

### Deployment Dependencies

- [Whatomate on GitHub](https://github.com/shridarpatil/whatomate)
- [Whatomate documentation](https://shridarpatil.github.io/whatomate/)
- [WhatsApp Cloud API: get started](https://developers.facebook.com/docs/whatsapp/cloud-api/get-started)
- [Template source](https://github.com/two-workspaces/whatomate)

### Implementation Details

- **Services:** Whatomate (the server with its built-in queue worker and web app), Postgres 18, and Redis 8 with append-only persistence and no eviction, all on Railway's private network. Database migrations run on every start.
- **Secrets:** the admin password, JWT secret, encryption key and webhook verify token are generated per deploy. If one is emptied, a replacement is generated once and kept on the volume, so nothing ever falls back to upstream's sample `admin` / `admin` login or sample keys.
- **Security:** production mode, secure cookies, CORS and WebSocket origins limited to your public URL and Railway domain, and login rate limits counted per visitor.
- **Never crash-looping on a variable:** Whatomate waits for Postgres and Redis on start. If the server stops within a minute of starting, the service shows a "Whatomate is not running" page and the deploy logs say what to fix.
- **Voice calling** needs UDP media ports, which Railway services don't receive, so WhatsApp calls and IVR are untested here; messaging doesn't depend on them.
- **Image:** upstream's official `shridh0r/whatomate:0.1.1-beta-0.18`, pinned, plus a small entrypoint.

## Why Deploy Whatomate on Railway?

Railway is a singular platform to deploy your infrastructure stack. Railway will host your infrastructure so you don't have to deal with configuration, while allowing you to vertically and horizontally scale it.

By deploying Whatomate on Railway, you are one step closer to supporting a complete full-stack application with minimal burden. Host your servers, databases, AI agents, and more on Railway.
