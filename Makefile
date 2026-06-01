.PHONY: audit audit-ci audit-shell audit-deps audit-secrets help

help:  ## Show available targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-20s %s\n", $$1, $$2}'

audit: audit-shell audit-secrets audit-deps  ## Run all local audit tools (CI-only tools skipped)

audit-shell:  ## Run shellcheck on all files in ci.yml shellcheck job (must match exactly)
	shellcheck -e SC2155,SC1091,SC1083,SC2317,SC2329 \
		install.sh \
		bin/walter-os \
		scripts/sync.sh \
		scripts/sync-repos.sh \
		scripts/agent-memory-setup.sh \
		scripts/profile-bootstrap.sh \
		scripts/secrets-bootstrap.sh \
		scripts/secrets-identity-init.sh \
		scripts/secrets-keychain-init.sh \
		scripts/wiki.sh \
		scripts/agent-runtime-watchdog.sh \
		scripts/agent-audit-log.sh \
		scripts/agent-secret-redactor.sh \
		scripts/release/reproduce.sh \
		scripts/agents/run.sh \
		scripts/agents/main.sh \
		scripts/agents/lib/plane.sh \
		scripts/agents/lib/llm.sh \
		scripts/agents/lib/alerts.sh \
		scripts/agents/lib/metrics.sh \
		scripts/agents/lib/spend.sh \
		tests/lint-frontmatter.sh \
		hooks/approval-gate.sh \
		hooks/bash-denylist.sh \
		hooks/network-gate.sh \
		hooks/branch-flow-guard.sh \
		hooks/daily-audit-gate.sh \
		hooks/pre-commit-tests.sh \
		setup/walter-host/services/openclaw/deploy.sh \
		skills/daily-supply-chain-audit/scripts/audit.sh \
		scripts/walter/subcommands/bridge.sh

audit-secrets:  ## Run gitleaks on the working tree
	@command -v gitleaks >/dev/null 2>&1 || { echo "ERROR: gitleaks not installed. See https://github.com/gitleaks/gitleaks"; exit 1; }
	gitleaks detect --config=.gitleaks.toml --no-git --source=.

audit-deps:  ## Run osv-scanner on lockfiles (soft-warn if not installed)
	@if command -v osv-scanner >/dev/null 2>&1; then \
		osv-scanner --lockfile=pnpm-lock.yaml; \
	else \
		echo "WARN: osv-scanner not installed. Install from https://github.com/google/osv-scanner"; \
	fi

audit-ci:  ## (CI only) Documents tools that require OIDC context (cosign, scorecard)
	@echo "audit-ci runs in GitHub Actions only. See .github/workflows/release.yml and .github/workflows/scorecard.yml."
	@echo "Local audit tools: run 'make audit'"
