# Trato

WhatsApp-based conversational business assistant for Mexican independent workers (electricians, plumbers, carpenters, tutors, etc.). Trato helps providers manage their business — clients, appointments, payments, reviews, and social media — entirely through WhatsApp, without learning any new app.

## Tech Stack

- Ruby on Rails 8
- PostgreSQL
- Sidekiq + Redis (background jobs)
- Hotwire (Turbo + Stimulus) + Tailwind CSS
- Claude API (Anthropic) — conversational AI
- Meta Cloud API — WhatsApp messaging
- Meta Graph API — Facebook/Instagram posting
- AWS S3 + Active Storage — file uploads
- Railway — hosting

## Features

### Dual WhatsApp Numbers

Trato operates with two separate WhatsApp numbers:

- **Provider Number** — For provider (technician) conversations: onboarding, appointment management, financial queries, social media posting
- **Client Number** — For client conversations: provider discovery, appointment booking, emergency notifications, service reviews

Messages are automatically routed to the appropriate conversation handler based on the `phone_number_id` from Meta Cloud API webhooks.

### Region-Based Provider Discovery

Clients messaging the client number receive region-based provider discovery:
1. System detects client's region from phone prefix (Veracruz, Puebla, Hidalgo, Oaxaca)
2. Client confirms or selects different region
3. Client selects zone and service category
4. System displays matching providers with dynamic availability

### Telegram Admin Notifications

When clients request services in unavailable areas, the system sends notifications to admin via Telegram bot, enabling quick response to expansion opportunities.

## Setup

### Prerequisites

- Ruby 3.3+
- PostgreSQL 14+
- Redis
- Node.js 20+

### Installation

```bash
git clone <repo-url>
cd trato
bundle install
```

### Environment Variables

Copy `.env.example` to `.env.local` and fill in your credentials:

```bash
cp .env.example .env.local
```

#### Required Variables

**Database & Redis:**
- `DATABASE_URL` — PostgreSQL connection string
- `REDIS_URL` — Redis connection string for Sidekiq

**WhatsApp / Meta Cloud API:**
- `TRATO_WHATSAPP_NUMBER` — Your WhatsApp business number (display purposes)
- `WHATSAPP_VERIFY_TOKEN` — Webhook verification token
- `WHATSAPP_ACCESS_TOKEN` — Meta Cloud API access token
- `WHATSAPP_PHONE_NUMBER_ID` — Legacy phone number ID (deprecated, use dual numbers below)
- `WHATSAPP_PROVIDER_PHONE_NUMBER_ID` — Phone number ID for provider conversations
- `WHATSAPP_CLIENT_PHONE_NUMBER_ID` — Phone number ID for client conversations

**Claude AI:**
- `ANTHROPIC_API_KEY` — Anthropic API key for conversational AI

**AWS S3:**
- `AWS_ACCESS_KEY_ID` — AWS access key
- `AWS_SECRET_ACCESS_KEY` — AWS secret key
- `AWS_REGION` — AWS region (default: us-east-1)
- `AWS_BUCKET` — S3 bucket name for file uploads

**Facebook OAuth:**
- `FACEBOOK_APP_ID` — Facebook app ID for social media posting
- `FACEBOOK_APP_SECRET` — Facebook app secret

**Admin Panel:**
- `ADMIN_USERNAME` — Admin panel username
- `ADMIN_PASSWORD` — Admin panel password
- `ADMIN_EMAIL` — Admin email address

**Telegram Notifications:**
- `TELEGRAM_BOT_TOKEN` — Telegram bot token for admin notifications
- `TELEGRAM_CHAT_ID` — Telegram chat ID to receive notifications

#### Optional Variables

- `FEATURE_DIRECTORY_HOMEPAGE` — Enable directory homepage (default: false)
- `STITCH_API_KEY` — Stitch design system API key

### Database

```bash
rails db:create
rails db:migrate
```

### Configuration Files

**Zones Configuration** (`config/zones.json`):

This file contains the geographic and service category data used for client discovery flows:
- States: Veracruz, Puebla, Hidalgo, Oaxaca
- Cities and zones within each state
- Phone prefixes for automatic region detection
- Service categories (Plomería, Electricidad, Construcción, etc.)

The file is loaded into memory on application boot. Invalid JSON will cause the app to fail fast with a clear error message.

### Running

```bash
# Web server
bin/dev

# Sidekiq (separate terminal)
bundle exec sidekiq
```

### Tests

```bash
bundle exec rspec
```

## Sidekiq Web UI

Available at `/sidekiq` (protected with HTTP basic auth using `ADMIN_USERNAME` / `ADMIN_PASSWORD`).
