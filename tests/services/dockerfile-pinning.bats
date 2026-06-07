#!/usr/bin/env bats
# tests/services/dockerfile-pinning.bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  ROUTER_ROOT="$REPO_ROOT/setup/walter-host/services"
}

@test "control tower Dockerfile pins both Node stages by digest" {
  dockerfile="$REPO_ROOT/apps/control-tower/Dockerfile"

  grep -q '^# tag: node:22-alpine$' "$dockerfile"
  [[ "$(grep -c '^FROM node:22-alpine@sha256:' "$dockerfile")" -eq 2 ]]
  ! grep -q '^FROM node:22-alpine AS ' "$dockerfile"
}

@test "subscription router Dockerfiles pin Node image digests" {
  for router in chatgpt-codex-router claude-sub-router gemini-sub-router; do
    dockerfile="$ROUTER_ROOT/$router/Dockerfile"
    grep -q '^# tag: node:22-slim$' "$dockerfile"
    grep -q '^FROM node:22-slim@sha256:' "$dockerfile"
    ! grep -q '^FROM node:22-slim$' "$dockerfile"
  done
}

@test "subscription routers install app deps from lockfiles" {
  for router in chatgpt-codex-router claude-sub-router gemini-sub-router; do
    dir="$ROUTER_ROOT/$router"
    [[ -f "$dir/package-lock.json" ]]
    grep -q '^COPY package.json package-lock.json ./ ' "$dir/Dockerfile" || \
      grep -q '^COPY package.json package-lock.json ./$' "$dir/Dockerfile"
    grep -q '^RUN npm ci --omit=dev --ignore-scripts$' "$dir/Dockerfile"
    ! grep -q '^RUN npm install --omit=dev$' "$dir/Dockerfile"
  done
}

@test "custom Postgres Dockerfile pins the Postgres base image by digest" {
  dockerfile="$ROUTER_ROOT/postgres/Dockerfile"

  grep -q '^# tag: postgres:17$' "$dockerfile"
  grep -q '^FROM postgres:17@sha256:' "$dockerfile"
  ! grep -q '^FROM postgres:17$' "$dockerfile"
}

@test "Hermes Agent Dockerfile pins the upstream base image by digest" {
  dockerfile="$ROUTER_ROOT/hermes-agent/Dockerfile"

  grep -q '^# tag: nousresearch/hermes-agent:v2026.5.7$' "$dockerfile"
  grep -q '^ARG BASE_IMAGE_REF=nousresearch/hermes-agent:v2026.5.7@sha256:' "$dockerfile"
  grep -q '^FROM ${BASE_IMAGE_REF}$' "$dockerfile"
  ! grep -q '^FROM nousresearch/hermes-agent:${BASE_VERSION}$' "$dockerfile"
}
