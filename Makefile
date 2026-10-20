COMPOSE := docker compose

.PHONY: help up down build logs ps migrate revision test test-backend test-frontend lint fmt clean shell-backend shell-db deploy-auth deploy-backend destroy-backend logs-backend migrate-backend package-report-mailer deploy-reports seed-report-meetings report-now llm-hello parse deploy-ai cert domain deploy-frontend destroy-frontend github-role

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

up: ## Start the whole stack (detached)
	$(COMPOSE) up -d --build

down: ## Stop the stack
	$(COMPOSE) down

clean: ## Stop the stack and wipe the database volume
	$(COMPOSE) down -v

build: ## Rebuild images
	$(COMPOSE) build

logs: ## Tail all logs
	$(COMPOSE) logs -f

ps: ## Show service status
	$(COMPOSE) ps

migrate: ## Apply migrations
	$(COMPOSE) exec backend alembic upgrade head

revision: ## Autogenerate a migration: make revision m="add x"
	$(COMPOSE) exec backend alembic revision --autogenerate -m "$(m)"

test: test-backend test-frontend ## Run all tests

test-backend: ## Run backend tests
	$(COMPOSE) exec backend pytest

test-frontend: ## Run frontend tests
	$(COMPOSE) exec frontend pnpm test

lint: ## Lint both sides
	$(COMPOSE) exec backend ruff check .
	$(COMPOSE) exec frontend pnpm lint

fmt: ## Format both sides
	$(COMPOSE) exec backend ruff format .
	$(COMPOSE) exec frontend pnpm format

shell-backend: ## Shell into the backend container
	$(COMPOSE) exec backend bash

shell-db: ## psql into the database
	$(COMPOSE) exec db psql -U $${POSTGRES_USER:-peach} -d $${POSTGRES_DB:-peach}

deploy-auth: ## Create/update Cognito email/password + Google Managed Login
	./scripts/deploy-auth.sh

deploy-backend: ## Build + push the image, roll the Lambda (function URL + Aurora), migrate, write BACKEND_URL to .env
	./scripts/deploy-backend.sh

destroy-backend: ## Delete the backend stack, Aurora cluster included
	./scripts/destroy-backend.sh

logs-backend: ## Tail the deployed backend's CloudWatch logs
	aws logs tail /aws/lambda/$${PROJECT_NAME:-peach}-backend --follow --since 10m

migrate-backend: ## Re-run migrations on the deployed backend (deploy-backend already does)
	aws lambda invoke --function-name $${PROJECT_NAME:-peach}-backend \
		--cli-binary-format raw-in-base64-out --payload '{"action":"migrate"}' /dev/stdout

package-report-mailer: ## Build the lightweight mailer Lambda ZIP locally
	./scripts/package-report-mailer.sh

deploy-reports: ## Deploy reports infrastructure; requires REPORT_RECIPIENT_EMAIL
	./scripts/deploy-reports.sh

seed-report-meetings: ## Seed deterministic samples: make seed-report-meetings WEEK=2026-W40
	WEEK="$(WEEK)" ./scripts/seed-report-meetings.sh

report-now: ## Queue a report for an ISO week: make report-now WEEK=2026-W40
	WEEK="$(WEEK)" ./scripts/report-now.sh

llm-hello: ## Verify Amazon Nova access through Bedrock Converse
	cd backend && AWS_REGION=us-east-1 uv run python -m app.ai.cli hello

parse: ## Parse text with Nova: make parse TEXT="Team sync tomorrow at 10"
	@test -n "$(TEXT)" || (echo 'TEXT is required' >&2; exit 2)
	cd backend && AWS_REGION=us-east-1 uv run python -m app.ai.cli parse --text "$(TEXT)"

deploy-ai: ## Deploy the isolated Nova agenda-parser Lambda and $5 budget
	./scripts/deploy-ai.sh

cert: ## Request + DNS-validate a us-east-1 certificate for the frontend: make cert DOMAIN=app.example.com
	./scripts/domain-frontend.sh cert

domain: ## Assign a custom domain to the frontend: make domain DOMAIN=app.example.com
	./scripts/domain-frontend.sh domain

deploy-frontend: ## Build the static export against BACKEND_URL and ship it to S3 + CloudFront
	./scripts/deploy-frontend.sh

destroy-frontend: ## Delete the frontend stack (bucket + distribution)
	./scripts/destroy-frontend.sh

github-role: ## Create the IAM role GitHub Actions assumes to deploy (OIDC, no keys)
	./scripts/github-role.sh
