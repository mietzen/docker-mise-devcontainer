#!/bin/sh
set -eu

# Start the Docker daemon for Docker-in-Docker, then run the container command.
# The container must run privileged (SYS_ADMIN/NET_ADMIN + unconfined seccomp)
# for dockerd to work. Used as the ENTRYPOINT of the docker-in-docker image.
#
# dockerd needs root to start, so this script runs as root (the image's default
# user) and then drops to the vscode user via setpriv before exec'ing the
# container command.

# Only start dockerd if the socket is not already present (e.g. a host-mounted
# /var/run/docker.sock).
if [ ! -S /var/run/docker.sock ]; then
  echo "Starting dockerd..."
  dockerd \
    --host=unix:///var/run/docker.sock \
    --group docker \
    >/var/log/dockerd.log 2>&1 &

  for i in $(seq 1 30); do
    if [ -S /var/run/docker.sock ]; then
      break
    fi
    sleep 1
  done

  if [ ! -S /var/run/docker.sock ]; then
    echo "ERROR: dockerd did not start. See /var/log/dockerd.log" >&2
    cat /var/log/dockerd.log >&2 || true
    exit 1
  fi
fi

# Drop remaining privileges to the vscode user. The docker group (vscode is a
# member) provides socket access, no sudo needed. HOME must be reset: the
# process runs as root initially, where $HOME=/root.
exec setpriv \
  --reuid=vscode \
  --regid=vscode \
  --init-groups \
  -- env HOME=/home/vscode USER=vscode "$@"