#!/usr/bin/env bash
# Starts/stops the micro-ROS agent side of the picoruby-ros2node QEMU
# verification flow: a persistent container running micro_ros_agent,
# bridged via socat from a TCP port (QEMU's second -serial, exposing
# UART1) to a PTY the agent reads as if it were a real serial device.
#
# Usage:
#   scripts/ros2node_agent.sh prepare          # create container, install socat (slow, run before QEMU)
#   scripts/ros2node_agent.sh start [tcp_port] # (re)connect to a running QEMU (fast; implies prepare)
#   scripts/ros2node_agent.sh logs
#   scripts/ros2node_agent.sh stop
#
# `prepare` has no timing constraints, so run it before QEMU boots. `start`
# has to win a race against the firmware's ~10s session-establishment
# retry window, so run it only after QEMU's TCP port is already open --
# never let it do the (slow, one-time) container/socat setup itself.
set -uo pipefail

CONTAINER=ros2node-agent
IMAGE=microros/micro-ros-agent:humble
PTY_LINK=/tmp/uart1
PORT="${2:-5556}"

prepare() {
  if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "== Starting $CONTAINER =="
    docker run --rm -d --name "$CONTAINER" --entrypoint bash "$IMAGE" -c "sleep infinity"
    docker exec "$CONTAINER" bash -lc "apt-get update -qq && apt-get install -y -qq socat"
  fi
}

start() {
  prepare

  echo "== (Re)starting micro_ros_agent (retries on its own until $PTY_LINK appears) =="
  docker exec "$CONTAINER" bash -lc "pkill -f micro_ros_agent" >/dev/null 2>&1 || true
  docker exec -d "$CONTAINER" bash -lc \
    "source /opt/ros/humble/setup.bash && source /uros_ws/install/setup.bash && \
     ros2 run micro_ros_agent micro_ros_agent serial --dev $PTY_LINK -b 115200 > /tmp/agent.log 2>&1"

  echo "== Bridging TCP:$PORT -> $PTY_LINK =="
  docker exec "$CONTAINER" bash -lc "pkill socat" >/dev/null 2>&1 || true
  # A connection made right as QEMU's chardev socket starts listening gets
  # an immediate EOF; retrying a couple seconds later succeeds.
  for attempt in $(seq 1 10); do
    docker exec -d "$CONTAINER" bash -lc \
      "socat -d -d PTY,link=$PTY_LINK,raw,echo=0 TCP:host.docker.internal:$PORT > /tmp/socat.log 2>&1"
    sleep 2
    if docker exec "$CONTAINER" bash -lc "pgrep socat >/dev/null"; then
      echo "socat bridge is up (attempt $attempt)"
      logs
      return 0
    fi
    echo "socat exited immediately (QEMU chardev not ready yet?), retrying ($attempt/10)..."
  done
  echo "Failed to establish the socat bridge after 10 attempts." >&2
  return 1
}

stop() {
  docker stop "$CONTAINER" >/dev/null 2>&1 || true
}

logs() {
  docker exec "$CONTAINER" bash -lc \
    "echo '--- agent ---'; tail -n 20 /tmp/agent.log; echo '--- socat ---'; tail -n 10 /tmp/socat.log"
}

case "${1:-}" in
  prepare) prepare ;;
  start) start ;;
  stop) stop ;;
  logs) logs ;;
  *) echo "Usage: $0 {prepare|start|stop|logs} [tcp_port]"; exit 1 ;;
esac
