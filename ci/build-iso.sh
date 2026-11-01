#!/usr/bin/env bash
#
# Builds the installation ISO from the already-published image using osbuild's
# bootc-image-builder (the bootc `bootc-installer` recipe that Bluefin Classic
# uses): Containerfile.installer adds Anaconda to a copy of the image (the live
# installer environment), and the image itself is embedded in the ISO as the
# payload Anaconda installs. Shared by .gitlab-ci.yml (iso-build) and
# .github/workflows/build-image.yml (iso-build).
#
# Environment (fallbacks let both CI systems call this directly):
#   IMAGE_NAME         local image name                     (default: custom-silverblue)
#   IMAGE_REPO         registry repo the image was pushed to (required)
#   IMAGE_TAG          tag to build the ISO from             (required)
#   FEDORA_VERSION     (default: parsed from Containerfile)
#   BIB_IMAGE          bootc-image-builder ref (required; pinned in the CI configs)
#   ISO_UPLOAD         github | gitlab | none                (default: none)
#   REGISTRY_USER /    when both are set the script logs in before pulling
#   REGISTRY_PASSWORD
#
# Runner requirements (verified up front so failures are fast, not late):
#   - podman next to buildah, usable rootful (root, or passwordless sudo for
#     both); bootc-image-builder refuses to run rootless and buildah must
#     share its container store
#   - ~30 GiB free next to the container store
#   - osbuild-selinux installed while SELinux is enforcing
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-custom-silverblue}"
IMAGE_REPO="${IMAGE_REPO:-${CI_REGISTRY_IMAGE:-}}"
if [ -z "${IMAGE_REPO}" ]; then
	echo "::error::IMAGE_REPO is not set (container registry not available)"
	exit 1
fi
IMAGE_REPO="${IMAGE_REPO,,}"

if [ -z "${IMAGE_TAG:-}" ]; then
	COMMIT_SHA="${COMMIT_SHA:-${CI_COMMIT_SHA:-${GITHUB_SHA:-}}}"
	COMMIT_SHA="${COMMIT_SHA:-$(git rev-parse HEAD)}"
	if [ -n "${CI_PIPELINE_CREATED_AT:-}" ]; then
		BUILD_DATE="${BUILD_DATE:-${CI_PIPELINE_CREATED_AT:0:10}}"
	else
		BUILD_DATE="${BUILD_DATE:-$(date -u +%Y-%m-%d)}"
	fi
	IMAGE_TAG="${BUILD_DATE//-/}-${COMMIT_SHA:0:5}"
fi

FEDORA_VERSION="${FEDORA_VERSION:-$(sed -n 's/^ARG BASE_IMAGE_TAG="\([0-9]*\)"/\1/p' Containerfile)}"
test -n "${FEDORA_VERSION}"
if [ -z "${BIB_IMAGE:-}" ]; then
	echo "::error::BIB_IMAGE is not set (pinned bootc-image-builder ref)"
	exit 1
fi

echo "Building installation ISO for ${IMAGE_REPO}:${IMAGE_TAG}"

# Fail early and clearly rather than an hour into the build.
if ! command -v podman >/dev/null 2>&1; then
	echo "::error::podman is required to run bootc-image-builder"
	exit 1
fi
# bootc-image-builder only supports rootful podman (there is no rootless
# fallback in its CLI), and buildah has to share the storage with the podman
# that runs it, so every container command below goes through the same
# wrapper: as root, or through passwordless sudo.
if [ "$(id -u)" -eq 0 ]; then
	ROOT=""
elif sudo -n podman --version >/dev/null 2>&1 \
	&& sudo -n buildah --version >/dev/null 2>&1; then
	# -n everywhere: a password prompt would hang the job (no tty).
	ROOT="sudo -n"
else
	echo "::error::iso-build needs rootful podman (bootc-image-builder does not run rootless), but sudo as uid $(id -u) asks for a password. Give the runner user passwordless sudo for podman and buildah, e.g. in /etc/sudoers.d/<runner>: '<user> ALL=(root) NOPASSWD: /usr/bin/podman, /usr/bin/buildah'"
	exit 1
fi
# osbuild needs its SELinux policy, and only the host can provide it:
# bootc-image-builder runs privileged, so what applies inside is the host's
# policy.
if command -v getenforce >/dev/null 2>&1 \
	&& [ "$(getenforce)" = "Enforcing" ] \
	&& ! rpm -q osbuild-selinux >/dev/null 2>&1; then
	echo "::error::SELinux is enforcing but osbuild-selinux is not installed (required by bootc-image-builder)"
	exit 1
fi

# Both images, osbuild's store and the ISO live side by side here.
STORAGE_ROOT="$(${ROOT} podman info --format '{{.Store.GraphRoot}}')"
echo "uid $(id -u), container storage ${STORAGE_ROOT}"
FREE_GIB="$(( $(df -Pk "${STORAGE_ROOT}" | awk 'NR==2 {print $4}') / 1024 / 1024 ))"
if [ "${FREE_GIB}" -lt 30 ]; then
	echo "::error::ISO build needs about 30 GiB of scratch space, ${FREE_GIB} GiB free on ${STORAGE_ROOT}"
	exit 1
fi

# stdin keeps the token out of the process list.
REGISTRY_USER="${REGISTRY_USER:-${CI_REGISTRY_USER:-}}"
REGISTRY_PASSWORD="${REGISTRY_PASSWORD:-${CI_REGISTRY_PASSWORD:-}}"
if [ -n "${REGISTRY_USER}" ] && [ -n "${REGISTRY_PASSWORD}" ]; then
	printf '%s' "${REGISTRY_PASSWORD}" | ${ROOT} buildah login \
		--username "${REGISTRY_USER}" \
		--password-stdin \
		"${IMAGE_REPO%%/*}"
fi

# Pulled under its registry name on purpose: the kickstart that
# bootc-image-builder generates ends with
# `bootc switch --transport registry <payload ref>`, so this ref is what the
# installed system ends up tracking.
${ROOT} buildah pull "${IMAGE_REPO}:${IMAGE_TAG}"
echo "Pulling image: done"

${ROOT} buildah build \
	--log-level=info \
	--file Containerfile.installer \
	--from "${IMAGE_REPO}:${IMAGE_TAG}" \
	--tag "localhost/${IMAGE_NAME}-installer:${IMAGE_TAG}" \
	.
echo "Installer image: done"

rm -rf iso-out
mkdir -p iso-out
# bootc-image-builder is run privileged and with the caller's container store
# mounted, because that is where both images above live.
${ROOT} podman run --rm \
	--privileged \
	--security-opt label=type:unconfined_t \
	-v "${PWD}/iso-out:/output" \
	-v "${STORAGE_ROOT}:/var/lib/containers/storage" \
	"${BIB_IMAGE}" \
	--type bootc-installer \
	--installer-payload-ref "${IMAGE_REPO}:${IMAGE_TAG}" \
	"localhost/${IMAGE_NAME}-installer:${IMAGE_TAG}"
echo "ISO build: done"

ISO_BUILD="$(find iso-out -type f -name '*.iso' -print -quit)"
if [ -z "${ISO_BUILD}" ]; then
	echo "::error::bootc-image-builder produced no ISO, iso-out contains:"
	find iso-out -maxdepth 3 -print
	exit 1
fi

ISO_NAME="${IMAGE_NAME}-${FEDORA_VERSION}-${IMAGE_TAG}.iso"
mv "${ISO_BUILD}" "${ISO_NAME}"
sha256sum "${ISO_NAME}" | tee "${ISO_NAME}.sha256"
OSBUILD_MANIFEST="$(find iso-out -maxdepth 1 -name 'manifest-*.json' -print -quit)"
if [ -n "${OSBUILD_MANIFEST}" ]; then
	cp "${OSBUILD_MANIFEST}" iso-manifest.json
fi

case "${ISO_UPLOAD:-none}" in
gitlab)
	# Publish to GitLab's generic package registry; re-running the job
	# replaces what the previous run of the same commit uploaded. Job
	# artifacts would be far too small (~5 GB ISO).
	PKG_URL="${CI_API_V4_URL}/projects/${CI_PROJECT_ID}/packages/generic/installer-iso/${IMAGE_TAG}"
	curl --fail --silent --show-error --request DELETE \
		--header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
		"${PKG_URL}/${ISO_NAME}" \
		>/dev/null || true
	for FILE in "${ISO_NAME}" "${ISO_NAME}.sha256"; do
		curl --fail --show-error \
			--header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
			--upload-file "${FILE}" \
			"${PKG_URL}/${FILE}"
	done
	if [ -f iso-manifest.json ]; then
		curl --fail --show-error \
			--header "JOB-TOKEN: ${CI_JOB_TOKEN}" \
			--upload-file iso-manifest.json \
			"${PKG_URL}/iso-manifest.json"
	fi
	echo "Published: ${PKG_URL}/${ISO_NAME}"
	;;
github)
	# GitHub release assets must be under 2 GiB and the ISO is ~5 GB, so it
	# is split into parts; `cat` puts it back together (see the notes).
	RELEASE_TAG="installer-iso/${IMAGE_TAG}"
	rm -f "${ISO_NAME}".part*
	split --bytes=2000m --numeric-suffixes=0 --suffix-length=3 \
		"${ISO_NAME}" "${ISO_NAME}.part"
	NOTES="Installation ISO for ${IMAGE_REPO}:${IMAGE_TAG}.

Reassemble and verify:
  cat ${ISO_NAME}.part* > ${ISO_NAME}
  sha256sum -c ${ISO_NAME}.sha256"
	gh release create "${RELEASE_TAG}" \
		--title "Installer ISO ${IMAGE_TAG}" \
		--notes "${NOTES}" || true
	gh release upload "${RELEASE_TAG}" \
		"${ISO_NAME}".part* "${ISO_NAME}.sha256" \
		--clobber
	if [ -f iso-manifest.json ]; then
		gh release upload "${RELEASE_TAG}" iso-manifest.json --clobber
	fi
	echo "Published: ${RELEASE_TAG}"
	if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
		{
			echo "### Installer ISO"
			echo "Release: \`${RELEASE_TAG}\` (split into 2 GiB parts)"
			echo ""
			echo '```'
			echo "cat ${ISO_NAME}.part* > ${ISO_NAME}"
			echo "sha256sum -c ${ISO_NAME}.sha256"
			echo '```'
		} >> "${GITHUB_STEP_SUMMARY}"
	fi
	;;
none)
	echo "ISO_UPLOAD=none, leaving ${ISO_NAME} in the working directory"
	;;
*)
	echo "::error::unknown ISO_UPLOAD value '${ISO_UPLOAD}'"
	exit 1
	;;
esac
