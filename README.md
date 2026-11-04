# vuetify-project

Scaffolded with Vuetify CLI.

## ❗️ Documentation

- Primary docs: https://vuetifyjs.com/
- Getting started guide: https://vuetifyjs.com/en/getting-started/installation/
- Community support: https://community.vuetifyjs.com/
- Issue tracker: https://issues.vuetifyjs.com/

## 🧱 Stack

- Framework: Vue 3 + Vite
- UI Library: Vuetify
- Language: TypeScript
- Package manager: npm

## 🧭 Start Here

- Main entry: `src/main.ts`
- Main app component: `src/App.vue`
- Main styles: `src/styles/`
- Plugin setup: `src/plugins/`

## 📁 Project Structure

- `src/main.ts` — application entry point
- `src/App.vue` — root component
- `src/components/` — reusable Vue components
- `src/plugins/` — plugin registration and setup
- `src/styles/` — global styles and theme settings
- `public/` — static public files

## ✨ Enabled Features

- ESLint
- Pinia
- Vue I18n
- Vuetify MCP
- Vue Router
- UnoCSS + Vuetify Preset

## 💿 Install

Use your selected package manager (npm) to install dependencies:

```bash
npm install
```

## 🚀 Quick Start

```bash
npm install
npm run dev
```

## 🏗️ Build

```bash
npm run build
```

## Employee call configuration

Voice and video calls use browser WebRTC and Supabase call signalling. Optional
`VITE_NORTHSTAR_STUN_URLS` may add STUN URIs. The client obtains Twilio's short-lived
ICE server configuration from authenticated `GET /api/v1/calls/ice-servers`; it gets
the current Supabase bearer token from the existing Auth session. During local Vite
development, `/api` is proxied to FastAPI on port 8000. If the frontend and API use
different production origins, set the public `VITE_NORTHSTAR_API_BASE_URL` to the
HTTPS API origin. Twilio permanent credentials belong only in the backend secret
environment (`TWILIO_ACCOUNT_SID`, `TWILIO_API_KEY`, `TWILIO_API_SECRET`), never in
Vite variables. The client keeps returned short-lived credentials in memory for the
call; verify real two-user connectivity with configured Twilio credentials before
claiming production call reliability.

## FastAPI backend

The foundation API lives in `backend/` and runs separately from the Vue application.
Use Python 3.11 or newer:

```bash
cd backend
python -m venv .venv
# Windows PowerShell: .\.venv\Scripts\Activate.ps1
# macOS/Linux: source .venv/bin/activate
python -m pip install -e ".[dev]"
Copy-Item .env.example .env  # Windows PowerShell; use `cp .env.example .env` elsewhere
uvicorn app.main:app --reload
```

Set `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and a comma-separated list of explicit
`CORS_ORIGINS` in `backend/.env`. Health and process readiness are `/api/v1/health`
and `/api/v1/ready`; neither probes Supabase. Interactive API docs are at `/docs`
while running locally. Run backend checks with
`pytest` from `backend/`. Do not put server secrets in Vite variables; this backend
foundation uses the public Supabase anon key and forwards the verified user's bearer
token so Supabase RLS continues to apply.

See [backend/README.md](backend/README.md) for configuration security, request
limits, and the current Supabase/FastAPI implementation map.

## 🧪 Available Scripts

- `npm run dev`
- `npm run build`
- `npm run preview`
- `npm run build-only`
- `npm run type-check`
- `npm run lint`
- `npm run lint:fix`

## 🤖 Vuetify MCP Server

This project is configured with the Vuetify Model Context Protocol (MCP) server.
To install and configure the MCP server for your favorite IDE (Cursor, Trae, Windsurf, VS Code, Claude Desktop, etc.) run:

```bash
npx -y @vuetify/mcp-cli
```

This will open an interactive setup wizard to help you connect your AI assistant to the Vuetify ecosystem.

## 💪 Support Vuetify Development

This project uses Vuetify - an MIT licensed Open Source project. We are glad to welcome contributors and any support for ongoing development:

- Contribute to Vuetify and ecosystem projects: https://github.com/vuetifyjs
- Request enterprise support: https://support.vuetifyjs.com/
- Sponsor on GitHub: https://github.com/sponsors/vuetifyjs
- Support on Open Collective: https://opencollective.com/vuetify
