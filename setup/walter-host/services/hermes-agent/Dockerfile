# walter-os/hermes-agent — Walter-OS flavor of nousresearch/hermes-agent.
#
# What this image adds on top of upstream:
#   - faster-whisper for local STT (privacy-preserving voice messages: audio
#     never leaves walter-vm). Hermes' .env.example calls this out as the
#     recommended install for `stt.provider: local`.
#
# What this image deliberately does NOT do:
#   - Pre-cache the Whisper model. faster-whisper auto-downloads it on first
#     use under `$HF_HOME/hub`; this Dockerfile sets `HF_HOME` inside
#     `/opt/data`, the `hermes_data` volume mount, so the model persists across
#     `docker compose up --force-recreate` and image upgrades. Baking it would
#     bloat the image by ~150 MB and the volume mount would shadow it at runtime
#     anyway.
#
# Build:
#   docker compose --profile hermes-agent build           # via the compose block
#   docker build --build-arg BASE_VERSION=v2026.5.7 .     # standalone
#
# Versioning convention: tag this image `walter-os/hermes-agent:<BASE_VERSION>-stt`
# so the upstream version is preserved in the tag. When upstream bumps to
# v2026.5.8, bump BASE_VERSION and rebuild — the `-stt` suffix marks the flavor.

ARG BASE_VERSION=v2026.5.7
FROM nousresearch/hermes-agent:${BASE_VERSION}

ARG BASE_VERSION
ARG FASTER_WHISPER_VERSION=1.2.1
ENV HF_HOME=/opt/data/.cache/huggingface

# Layer 1: install faster-whisper into Hermes' venv.
# Upstream uses uv as the package manager; we reuse it for consistency.
# --python pinpoints the target venv interpreter; --no-cache-dir keeps the
# image lean (model files come at runtime, not via pip).
USER root
RUN uv pip install \
      --python /opt/hermes/.venv/bin/python \
      --no-cache-dir \
      "faster-whisper==${FASTER_WHISPER_VERSION}"

# Sanity check at build time so a broken release of faster-whisper fails the
# build instead of breaking the running container at first voice message.
RUN /opt/hermes/.venv/bin/python3 -c "from faster_whisper import WhisperModel; print('faster-whisper', __import__('faster_whisper').__version__)"

# Drop back to upstream's runtime user so behavior matches base image.
USER hermes

# OCI metadata: makes `docker inspect` self-documenting and lets us tell this
# image apart from upstream in audits / Grafana dashboards.
LABEL org.opencontainers.image.title="walter-os/hermes-agent" \
      org.opencontainers.image.description="Hermes Agent with faster-whisper local STT baked in" \
      org.opencontainers.image.source="https://github.com/Xipher-Labs/walter-os" \
      org.opencontainers.image.licenses="MIT" \
      walter-os.flavor="stt" \
      walter-os.faster-whisper="${FASTER_WHISPER_VERSION}" \
      walter-os.upstream="nousresearch/hermes-agent:${BASE_VERSION}"
