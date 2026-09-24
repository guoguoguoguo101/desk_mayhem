"""Real UDP lifecycle/authority/round test against an already-running isolated server."""
import json, socket, sys, time
port = int(sys.argv[1])

class Peer:
    def __init__(self):
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.sock.connect(('127.0.0.1', port))
        self.sock.setblocking(False)
        self.session = ''
        self.slot = -1
        self.seq = 0
        self.event = 0
        self.pending = {}
        self.seen = set()
        self.seen_present = set()
        self.events = []
        self.players = {}
        self.npcs = {}
        self.rejected = False
        self.tick = -1
        self.round_id = 1
        self.last_move = (0,0)
    def send(self, data):
        if data.get('type')=='hello': data=dict(data, debug_roster=True)
        self.sock.send(json.dumps(dict(data, session=self.session)).encode())
    def pump(self):
        while True:
            try: data = json.loads(self.sock.recv(65536))
            except BlockingIOError: break
            if data.get('type') == 'rejected': self.rejected = True
            if data.get('type') == 'admitted':
                self.session, self.slot = data['session'], data['slot']
            if 'ack' in data: self.pending.pop(data['ack'], None)
            if 'reliable' in data:
                self.send({'ack':data['reliable']})
                if data['reliable'] not in self.seen:
                    self.seen.add(data['reliable'])
                    self.events.append(data['payload'])
            elif data.get('type') in ('combat','action_start','blink'):
                key = (data.get('type'), data.get('tick'), data.get('attacker_id'), data.get('victim_id'), data.get('attack'), data.get('slot'))
                if key not in self.seen_present:
                    self.seen_present.add(key)
                    self.events.append(data)
            if 'players' in data and data.get('tick',-1)>self.tick:
                self.round_id = data['round_id']
                self.tick = data['tick']
                self.players = {p['slot']:p for p in data['players']}
                self.npcs = {p['entity_id']:p for p in data.get('npcs',[])}
        for event, payload in self.pending.items():
            self.send({'reliable':event,'payload':payload})
    def attack(self, name, aim=(1,0)):
        self.event += 1
        self.seq += 1
        frame = self.frame(self.last_move, aim)
        frame['actions'] = [{'attack_seq':self.event, 'attack':name, 'aim':aim}]
        self.pending[self.event] = {'type':'input','frames':[frame]}
    def input(self, move=(0,0)):
        self.seq += 1
        self.last_move = move
        self.send({'type':'input','frames':[self.frame(move,(1,0))]})
    def frame(self, move, aim):
        return {'seq':self.seq,'tick':self.tick+4,'round_id':self.round_id,'life':self.players.get(self.slot,{}).get('life',1),'move':move,'aim':aim,'actions':[]}


a,b = Peer(),Peer()
def run(seconds, callback=None):
    until=time.monotonic()+seconds
    while time.monotonic()<until:
        for p in (a,b): p.pump()
        if callback: callback()
        else:
            for p in (a,b):
                if p.session: p.input()
        time.sleep(1/60)
a.send({'type':'hello'})
run(.3)
assert len(a.npcs)==2 and len(a.players)==1, 'NPCs do not consume seats'
dummy_id=min(a.npcs)
def approach():
    pos=a.players[0]['position']
    goal=a.npcs[dummy_id]['position']
    dx,dz=goal[0]-pos[0],goal[2]-pos[2]
    distance=(dx*dx+dz*dz)**.5
    a.input((dx/distance,dz/distance) if distance>1.6 else (0,0))
run(2.5,approach)
run(.3)
pos=a.players[0]['position']; goal=a.npcs[dummy_id]['position']
dx,dz=goal[0]-pos[0],goal[2]-pos[2]
distance=(dx*dx+dz*dz)**.5
aim=(dx/distance,dz/distance)
a.attack('punch',aim)
run(.35)
assert a.npcs[dummy_id]['health']==1992, ('authoritative NPC damage',a.npcs)
b.send({'type':'hello'})
run(.4)
assert b.slot==1 and len(b.npcs)==2, 'late join and capacity'
for id in a.npcs:
    assert a.npcs[id]['health']==b.npcs[id]['health'], 'late join health'
    assert a.npcs[id]['position']==b.npcs[id]['position'], 'late join position'
a.attack('returning_pot',aim)
run(1.8)
assert a.npcs[dummy_id]['health']==1970, ('NPC pot two legs',a.npcs[dummy_id])
assert a.npcs[dummy_id]['health']==b.npcs[dummy_id]['health'], 'both clients agree'
assert sum(e.get('type')=='combat' and e.get('victim_id')==dummy_id for e in b.events)==2, 'NPC events unique'
assert not any(e.get('type')=='round_end' for e in a.events), 'no NPC round'
third=Peer(); third.send({'type':'hello'}); run(.2); third.pump()
assert third.rejected, 'still two player capacity'
a.send({'type':'leave'}); b.send({'type':'leave'})
print('BATTLE_NPC_PROTOCOL PASS two NPCs two seats late join HP position pot both legs consistent events',flush=True)
