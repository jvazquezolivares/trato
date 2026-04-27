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

Copy `.env` to `.env.local` and fill in your credentials:

```bash
cp .env .env.local
```

Required variables: `DATABASE_URL`, `REDIS_URL`, `TRATO_WHATSAPP_NUMBER`, `WHATSAPP_VERIFY_TOKEN`, `WHATSAPP_ACCESS_TOKEN`, `WHATSAPP_PHONE_NUMBER_ID`, `ANTHROPIC_API_KEY`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_BUCKET`, `FACEBOOK_APP_ID`, `FACEBOOK_APP_SECRET`, `ADMIN_USERNAME`, `ADMIN_PASSWORD`, `ADMIN_EMAIL`.

### Database

```bash
rails db:create
rails db:migrate
```

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
