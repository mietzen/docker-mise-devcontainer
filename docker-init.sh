#!/bin/sh
set -eu

# Start the Docker daemon for Docker-in-Docker, then run the container command.
# The container must run privileged (SYS_ADMIN/NET_ADMIN + unconfined seccomp)
# for dockerd to work. Used as the ENTRYPOINT of Dockerfile.did.

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

exec "$@"