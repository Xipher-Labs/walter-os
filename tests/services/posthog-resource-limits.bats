#!/usr/bin/env bats
# Static coverage for PostHog resource limits.
#
# The PostHog compose file uses `extends: docker-compose.base.yml`; that base
# file is cloned during deployment and is not vendored in this repo. This test
# intentionally validates the local resource-limit contract without running
# `docker compose config`.

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  POSTHOG_COMPOSE="$REPO_ROOT/setup/walter-host/services/posthog/compose.yml"
}

assert_posthog_limits() {
  python3 - "$POSTHOG_COMPOSE" <<'PY'
import sys
import yaml

compose_path = sys.argv[1]
expected = {
    "db": "POSTHOG_DB",
    "redis7": "POSTHOG_REDIS7",
    "clickhouse": "POSTHOG_CLICKHOUSE",
    "zookeeper": "POSTHOG_ZOOKEEPER",
    "kafka": "POSTHOG_KAFKA",
    "worker": "POSTHOG_WORKER",
    "web": "POSTHOG_WEB",
    "plugins": "POSTHOG_PLUGINS",
    "ingestion-general": "POSTHOG_INGESTION_GENERAL",
    "ingestion-sessionreplay": "POSTHOG_INGESTION_SESSIONREPLAY",
    "recording-api": "POSTHOG_RECORDING_API",
    "ingestion-error-tracking": "POSTHOG_INGESTION_ERROR_TRACKING",
    "ingestion-logs": "POSTHOG_INGESTION_LOGS",
    "ingestion-traces": "POSTHOG_INGESTION_TRACES",
    "proxy": "POSTHOG_PROXY",
    "objectstorage": "POSTHOG_OBJECTSTORAGE",
    "seaweedfs": "POSTHOG_SEAWEEDFS",
    "asyncmigrationscheck": "POSTHOG_ASYNC_MIGRATIONS_CHECK",
    "temporal": "POSTHOG_TEMPORAL",
    "elasticsearch": "POSTHOG_ELASTICSEARCH",
    "temporal-admin-tools": "POSTHOG_TEMPORAL_ADMIN_TOOLS",
    "temporal-ui": "POSTHOG_TEMPORAL_UI",
    "temporal-django-worker": "POSTHOG_TEMPORAL_DJANGO_WORKER",
    "cyclotron-janitor": "POSTHOG_CYCLOTRON_JANITOR",
    "capture": "POSTHOG_CAPTURE",
    "replay-capture": "POSTHOG_REPLAY_CAPTURE",
    "property-defs-rs": "POSTHOG_PROPERTY_DEFS_RS",
    "livestream": "POSTHOG_LIVESTREAM",
    "personhog-replica": "POSTHOG_PERSONHOG_REPLICA",
    "personhog-router": "POSTHOG_PERSONHOG_ROUTER",
    "feature-flags": "POSTHOG_FEATURE_FLAGS",
    "hypercache-server": "POSTHOG_HYPERCACHE_SERVER",
    "kafka-init": "POSTHOG_KAFKA_INIT",
    "cymbal": "POSTHOG_CYMBAL",
}

with open(compose_path, "r", encoding="utf-8") as handle:
    compose = yaml.safe_load(handle)

services = compose["services"]
missing_services = sorted(set(expected) - set(services))
assert not missing_services, f"missing services in compose: {missing_services}"

for service_name, prefix in expected.items():
    service = services[service_name]
    markers = {
        "mem_limit": "${" + prefix + "_MEM_LIMIT:-",
        "mem_reservation": "${" + prefix + "_MEM_RESERVATION:-",
        "cpus": "${" + prefix + "_CPUS:-",
        "pids_limit": "${" + prefix + "_PIDS_LIMIT:-",
    }
    for key, marker in markers.items():
        value = service.get(key)
        assert value, f"{service_name} missing {key}"
        assert str(value).startswith(marker), (
            f"{service_name} {key} is not overrideable by {prefix}: {value!r}"
        )
PY
}

@test "all PostHog services have overrideable resource limits" {
  assert_posthog_limits
}

@test "PostHog compose documents why render needs deploy-time base file" {
  grep -q "docker-compose.base.yml" "$POSTHOG_COMPOSE"
  [[ ! -f "$REPO_ROOT/setup/walter-host/services/posthog/docker-compose.base.yml" ]]
}
