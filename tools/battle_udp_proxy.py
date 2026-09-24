"""Test-only deterministic impairment: one proxy per game client, no gameplay logic."""
import argparse
import heapq
import random
import select
import socket
import time

parser = argparse.ArgumentParser()
parser.add_argument('--listen', type=int, required=True)
parser.add_argument('--server', type=int, required=True)
args = parser.parse_args()
rng = random.Random(args.listen)
front = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
front.bind(('127.0.0.1', args.listen))
back = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
back.connect(('127.0.0.1', args.server))
queue = []
client = None
serial = 0
while True:
    ready, _, _ = select.select([front, back], [], [], 0.002)
    for sock in ready:
        try:
            data, address = sock.recvfrom(65536)
        except ConnectionResetError:
            continue
        if sock is front:
            client = address
        if client is None or rng.random() < 0.05:
            continue
        serial += 1
        # 50 ms each way, +/-20 ms jitter, 5% loss and 2% duplicates.
        heapq.heappush(queue, (time.monotonic()+rng.uniform(.03,.07),serial,sock is front,data))
        if rng.random() < .02:
            serial += 1
            heapq.heappush(queue,(time.monotonic()+.08,serial,sock is front,data))
    while queue and queue[0][0] <= time.monotonic():
        _, _, upstream, data = heapq.heappop(queue)
        if upstream:
            back.send(data)
        else:
            front.sendto(data, client)
