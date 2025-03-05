#!/bin/bash
set -xeou pipefail

# Mount a base container image
ctr=$(buildah from registry.access.redhat.com/ubi9/ubi-minimal:9.5)
mnt=$(buildah mount "$ctr")

buildah copy "$ctr" ../supercronic/supercronic /usr/local/bin/supercronic
buildah copy "$ctr" solr-backup /var/solr-backup
buildah run "$ctr" -- chmod 666 /var/solr-backup/crontab

# Install jq
buildah run "$ctr" -- microdnf update -y
buildah run "$ctr" -- microdnf -y install jq
buildah run "$ctr" -- microdnf clean all

# Remove cached dnf files
rm -rf "$mnt/var/cache/dnf" "$mnt/var/log/dnf.*"

buildah config \
    --cmd '[ "/var/solr-backup/entrypoint.sh" ]' \
    --label org.opencontainers.image.created="$(date --rfc-3339=seconds)" \
    --label org.opencontainers.image.authors="Filiph Schaaf" \
    --label org.opencontainers.image.vendor="White Red Consulting AB" \
    --label org.opencontainers.image.title="ETERNA SOLR Backup" \
    "$ctr"

# Commit the image
buildah commit --format docker "$ctr" eterna-solr-backup:latest
buildah unmount "$ctr"
buildah rm "$ctr"

if [[ -n "$1" ]]; then
    echo "Tags:"
    echo "$@"
    buildah tag eterna-solr-backup:latest "$@"
fi
