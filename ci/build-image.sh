#!/usr/bin/env bash
#
# Builds the image and pushes <IMAGE_REPO>:latest, :<fedora version> and
# :<YYYYMMDD>-<5-char sha>. Shared by .gitlab-ci.yml (image-build) and
# .github/workflows/build-image.yml (image-build); both shell out to buildah.
#
# Environment (fallbacks let both CI systems call this directly):
#   IMAGE_NAME         local image name                     (default: custom-silverblue)
#   IMAGE_REPO         registry repo to push to             (required)
#   REGISTRY           registry host        (default: host part of IMAGE_REPO)
#   REGISTRY_USER /    when set (or CI_REGISTRY_USER/CI_REGISTRY_PASSWORD are),
#   REGISTRY_PASSWORD  the script logs in before pushing
#   RECHUNK            "true" to re-split layers with chunkah (default: false)
#   COMMIT_SHA         (default: CI_COMMIT_SHA, GITHUB_SHA, or git rev-parse HEAD)
#   BUILD_DATE         UTC YYYY-MM-DD (default: CI_PIPELINE_CREATED_AT date, or
#                      today); build-iso.sh must see the same value
#   SOURCE_URL         org.opencontainers.image.source label (optional)
#
# Writes image-digests.txt into the current directory. When GITHUB_OUTPUT is
# set, appends fedora_version= and image_tag= lines for later jobs.
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-custom-silverblue}"
IMAGE_REPO="${IMAGE_REPO:-${CI_REGISTRY_IMAGE:-}}"
if [ -z "${IMAGE_REPO}" ]; then
	echo "::error::IMAGE_REPO is not set (container registry not available)"
	exit 1
fi
# Registry paths must be lowercase in refs.
IMAGE_REPO="${IMAGE_REPO,,}"
REGISTRY="${REGISTRY:-${CI_REGISTRY:-${IMAGE_REPO%%/*}}}"
if [ -z "${REGISTRY}" ]; then
	echo "::error::container registry is not enabled on this project or instance"
	exit 1
fi

COMMIT_SHA="${COMMIT_SHA:-${CI_COMMIT_SHA:-${GITHUB_SHA:-}}}"
COMMIT_SHA="${COMMIT_SHA:-$(git rev-parse HEAD)}"
if [ -n "${CI_PIPELINE_CREATED_AT:-}" ]; then
	BUILD_DATE="${BUILD_DATE:-${CI_PIPELINE_CREATED_AT:0:10}}"
else
	BUILD_DATE="${BUILD_DATE:-$(date -u +%Y-%m-%d)}"
fi
IMAGE_TAG="${BUILD_DATE//-/}-${COMMIT_SHA:0:5}"

FEDORA_VERSION="$(sed -n 's/^ARG BASE_IMAGE_TAG="\([0-9]*\)"/\1/p' Containerfile)"
test -n "${FEDORA_VERSION}"
echo "Building Fedora Silverblue ${FEDORA_VERSION} at ${COMMIT_SHA} as ${IMAGE_TAG}"

# Always exists so artifacts: paths never matches nothing.
: > image-digests.txt

buildah build \
	--log-level=info \
	--file Containerfile \
	--label "org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
	--label "org.opencontainers.image.revision=${COMMIT_SHA}" \
	--label "org.opencontainers.image.source=${SOURCE_URL:-${CI_PROJECT_URL:-}}" \
	--tag "${IMAGE_NAME}:latest" \
	--tag "${IMAGE_NAME}:${FEDORA_VERSION}" \
	--tag "${IMAGE_NAME}:${IMAGE_TAG}" \
	.
echo "Build: done"

# Optional: re-split the image into content-based layers with chunkah
# (Containerfile.rechunk). Only the :latest tag is rechunked; the other tags
# are then pointed at the chunked image, so every published tag is the
# chunked variant.
if [ "${RECHUNK:-false}" = "true" ]; then
	echo "Rechunking into content-based layers (chunkah)"
	CHUNKAH_EXTRA_ARGS="--label org.opencontainers.image.created=$(date -u +%Y-%m-%dT%H:%M:%SZ) --label org.opencontainers.image.revision=${COMMIT_SHA} --label org.opencontainers.image.source=${SOURCE_URL:-${CI_PROJECT_URL:-}}"
	rm -rf out
	buildah build \
		--log-level=info \
		--skip-unused-stages=false \
		--from "localhost/${IMAGE_NAME}:latest" \
		--security-opt=label=disable \
		-v "$PWD:/run/src" \
		--build-arg "CHUNKAH_EXTRA_ARGS=${CHUNKAH_EXTRA_ARGS}" \
		--file Containerfile.rechunk \
		--tag "localhost/${IMAGE_NAME}:latest" \
		.
	rm -rf out
	buildah tag "localhost/${IMAGE_NAME}:latest" \
		"localhost/${IMAGE_NAME}:${FEDORA_VERSION}" \
		"localhost/${IMAGE_NAME}:${IMAGE_TAG}"
	echo "Rechunking: done"
fi

# stdin keeps the token out of the process list.
REGISTRY_USER="${REGISTRY_USER:-${CI_REGISTRY_USER:-}}"
REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-${CI_REGISTRY_PASSWORD:-}}"
if [ -n "${REGISTRY_USER}" ] && [ -n "${REGISTRY_PASSWORD}" ]; then
	printf '%s' "${REGISTRY_PASSWORD}" | buildah login \
		--username "${REGISTRY_USER}" \
		--password-stdin \
		"${REGISTRY}"
	echo "Logging in to registry: done"
fi

for TAG in "latest" "${FEDORA_VERSION}" "${IMAGE_TAG}"; do
	buildah tag "localhost/${IMAGE_NAME}:${TAG}" "${IMAGE_REPO}:${TAG}"
	buildah push --digestfile "/tmp/digest.${TAG}" "${IMAGE_REPO}:${TAG}"
	printf '%-12s %s\n' "${TAG}" "$(cat "/tmp/digest.${TAG}")" \
		| tee -a image-digests.txt
done
echo "Pushing images: done"

if [ -n "${GITHUB_OUTPUT:-}" ]; then
	{
		echo "fedora_version=${FEDORA_VERSION}"
		echo "image_tag=${IMAGE_TAG}"
	} >> "${GITHUB_OUTPUT}"
fi
