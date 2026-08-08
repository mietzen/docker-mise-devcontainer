#!/bin/sh
set -eu

# Start the Docker daemon for Docker-in-Docker, then run the container command.
# The container must run privileged (SYS_ADMIN/NET_ADMIN + unconfined seccomp)
# for dockerd to work. Used as the ENTRYPOINT of the docker-in-docker image.
#
# dockerd needs root to start, so this script runs as root (the image's default
# user) and then drops to the vscode user via setpriv before exec'ing the
# container command.
#
# The runtime prep mirrors the official moby dind wrapper (hack/dind): tell
# containerd we are inside a container, mount tmpfs/securityfs so nested
# containers can create devices and AppArmor profiles work, enable cgroup v2
# nesting, and share mount propagation.

export container=docker

# Let AppArmor work inside the container (profiles for nested containers).
if [ -d /sys/kernel/security ] && ! mountpoint -q /sys/kernel/security; then
  mount -t securityfs none /sys/kernel/security 2>/dev/null || true
fi

# cgroup v2: nested containers need their own cgroups. Move the current
# processes into an "init" cgroup and enable the controllers, otherwise
# writing subtree_control fails with EBUSY. The retry loop handles the race
# with docker exec creating new processes. Best-effort: without privileges
# this stays read-only and dockerd fails below with a clear message.
if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
  mkdir -p /sys/fs/cgroup/init 2>/dev/null || true
  for i in $(seq 1 10); do
    if xargs -rn1 < /sys/fs/cgroup/cgroup.procs > /sys/fs/cgroup/init/cgroup.procs 2>/dev/null \
      && sed -e 's/ / +/g' -e 's/^/+/' < /sys/fs/cgroup/cgroup.controllers \
        > /sys/fs/cgroup/cgroup.subtree_control 2>/dev/null; then
      break
    fi
    sleep 1
  done
fi

# Shared mount propagation: mounts made by nested containers stay visible to
# their siblings (systemd-style root".
mount --make-rshared / 2>/dev/null || true

# Only start dockerd if the socket is not already present (e.g. a host-mounted
# /var/run/docker.sock).
if [ ! -S /var/run/docker.sock ]; then
  echo "Starting dockerd..."

  # Fall back to vfs when the kernel cannot do overlayfs (e.g. docker-in-docker
  # on top of another overlay). Containing the probe only touches the "merged"
  # mountpoint, not the snapshot dirs.
  STORAGE_ARGS=""
  PROBE_DIR=$(mktemp -d)
  mkdir -p "${PROBE_DIR}/lower" "${PROBE_DIR}/upper" "${PROBE_DIR}/work"
  if [ -w / ] && ! mount -t overlay overlay \
      -o "lowerdir=${PROBE_DIR}/lower,upperdir=${PROBE_DIR}/upper,workdir=${PROBE_DIR}/work" \
      "${PROBE_DIR}/merged" 2>/dev/null; then
    echo "  overlayfs not available, using vfs storage driver"
    STORAGE_ARGS="--storage-driver=vfs"
  fi
  umount "${PROBE_DIR}/merged" 2>/dev/null || true
  rm -rf "${PROBE_DIR}"

  dockerd \
    --host=unix:///var/run/docker.sock \
    --group docker \
    ${STORAGE_ARGS} \
    >/var/log/dockerd.log 2>&1 &

  # Wait until the daemon actually responds. Checking the socket file is not
  # enough: dockerd binds it before network setup and a daemon that dies there
  # (e.g. iptables without privileges) leaves a stale socket behind.
  for i in $(seq 1 60); do
    if docker info >/dev/null 2>&1; then
      break
    fi
    sleep 1
  done

  if ! docker info >/dev/null 2>&1; then
    echo "ERROR: dockerd is not responding. Is the container running with --privileged?" >&2
    echo "  See /var/log/dockerd.log" >&2
    cat /var/log/dockerd.log >&2 || true
    exit 1
  fi
  echo "dockerd is ready"
fi

# Drop remaining privileges to the vscode user. The docker group (vscode is a
# member) provides socket access, no sudo needed. HOME must be reset: the
# process runs as root initially, where $HOME=/root.
exec setpriv \
  --reuid=vscode \
  --regid=vscode \
  --init-groups \
  -- env HOME=/home/vscode USER=vscode "$@"