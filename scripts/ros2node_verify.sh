#!/usr/bin/env bash
# One-shot picoruby-ros2node QEMU <-> micro-ROS agent verification.
# Boots build-qemu/ (must already contain storage/home/app.rb's
# ROS2::Node test script) and bridges its UART1 to a micro-ROS agent,
# handling the boot-order/timing dance itself.
#
# Usage:
#   scripts/ros2node_verify.sh         # rebuild+run, print firmware log
#   scripts/ros2node_verify.sh stop    # tear down both containers
#
# Run this from the R2P2-ESP32 repo root, in a single shell. Everything
# (QEMU, the agent, socat) runs in background Docker containers, so
# there is nothing else to start manually or in another terminal.
set -uo pipefail

cd "$(dirname "$0")/.."

QEMU_CONTAINER=ros2node-qemu-e2e
PORT=5556
IMAGE=r2p2-esp32-idf:v5.5.4
AGENT_SCRIPT="$(dirname "$0")/ros2node_agent.sh"

stop() {
  docker stop "$QEMU_CONTAINER" >/dev/null 2>&1 || true
  "$AGENT_SCRIPT" stop
  echo "Stopped."
}

if [ "${1:-}" = "stop" ]; then
  stop
  exit 0
fi

echo "== Preparing the micro-ROS agent container (slow on first run) =="
"$AGENT_SCRIPT" prepare

echo "== Stopping any previous QEMU instance =="
docker stop "$QEMU_CONTAINER" >/dev/null 2>&1 || true

echo "== Starting QEMU (UART0=console, UART1 -> TCP:$PORT) =="
docker run --rm -d --name "$QEMU_CONTAINER" \
  -v "$PWD":/project -w /project -u "$(id -u):$(id -g)" -e HOME=/tmp \
  -p "$PORT:$PORT" \
  "$IMAGE" bash -lc \
  "idf.py -B build-qemu qemu --qemu-extra-args='-m 8M -serial tcp::${PORT},server,nowait'"

echo "== Waiting for the UART1 TCP port =="
for i in $(seq 1 20); do
  python3 -c "import socket; socket.create_connection(('127.0.0.1',$PORT),timeout=1).close()" 2>/dev/null && break
  sleep 1
done

# The firmware only retries session establishment for ~10s from boot, so
# the bridge has to come up fast -- no extra delay here on purpose.
echo "== Bridging to the micro-ROS agent =="
"$AGENT_SCRIPT" start "$PORT"

echo "== Firmware boot log (waiting ~15s for it to reach app.rb) =="
sleep 15
docker logs "$QEMU_CONTAINER" --tail 15

echo
echo "Run again:      $0"
echo "Stop everything: $0 stop"
