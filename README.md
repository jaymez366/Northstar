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

Voice and video calls use browser WebRTC and the private Supabase call-signaling
RPCs described in the application change review. Configure `VITE_NORTHSTAR_STUN_URLS`
as a comma-separated list of STUN URIs. Production deployments also need
`VITE_NORTHSTAR_TURN_URLS` and `VITE_NORTHSTAR_TURN_CREDENTIALS_URL`. The HTTPS
credential endpoint must authenticate the Supabase bearer token and return short-lived
`{ "username": "...", "credential": "...", "expires_at": "ISO-8601" }` TURN credentials.
Do not put TURN passwords or long-lived credentials in Vite variables; Vite variables
are public in the browser bundle. Set the three values in local untracked environment
configuration and Cloudflare Pages build variables. The current client accepts short-lived
credentials in memory only. A real TURN service and two-user connectivity test are
required before production call reliability can be claimed.

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
