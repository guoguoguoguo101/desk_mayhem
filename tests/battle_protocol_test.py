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
        self.rejected = False
        self.tick = -1
        self.round_id = 1
        self.last_move = (0,0)
    def send(self, data):
        if data.get('type')=='hello': data=dict(data, debug_roster=True)
        if data.get('type')=='hello': self.joining=True
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
        for p in (a,b):
            p.pump()
            if not p.session and getattr(p,'joining',False): p.send({'type':'hello'})
        if callback: callback()
        else:
            for p in (a,b):
                if p.session: p.input()
        time.sleep(1/60)

a.send({'type':'hello'})
run(1)
b.send({'type':'hello'})
run(1)
assert (a.slot,b.slot)==(0,1), 'admission'
third=Peer(); third.send({'type':'hello'}); run(.2); third.pump()
assert third.rejected, 'third player must be refused'
# Fake outcome and invalid movement cannot modify authoritative state.
a.send({'type':'input','seq':999,'move':[1000,0],'health':0,'position':[0,99,0]})
a.send({'type':'combat','victim_slot':1,'damage':400})
run(.2)
assert b.players[1]['health']==400 and abs(a.players[0]['position'][0]+12)<.1
def approach():
    x=a.players.get(0,{}).get('position',[-12])[0]
    a.input((1 if x<10.5 else 0,0)); b.input()
run(4.2,approach)
assert 9.9<a.players[0]['position'][0]<11.8, ('authoritative movement',a.players[0]['position'])
a.attack('punch_uppercut') # Caller may not choose combo stage.
run(.3)
assert b.players[1]['health']==400, 'forged combo stage'
a.attack('punch')
run(.35)
assert b.players[1]['health']==392, 'retransmitted attack applied once'
assert sum(e.get('type')=='combat' for e in a.events)==1, 'event applied once'
print('BATTLE_PROTOCOL PASS admission capacity movement forged-results duplicate attack',flush=True)
a.attack('returning_pot')
run(1.5)
assert b.players[1]['health']==370, ('pot outbound and return damage', b.players[1]['health'])
start_x=a.players[0]['position'][0]
a.attack('blink')
run(.2)
blink_x=a.players[0]['position'][0]
assert abs(blink_x-start_x-4.5)<.05, 'blink authoritative displacement'
a.attack('blink')
run(.2)
assert abs(a.players[0]['position'][0]-blink_x)<.05, 'blink cooldown'
print('BATTLE_PROTOCOL PASS pot damage each leg blink distance cooldown',flush=True)
next_attack=0
facing_ready=False
def fight():
    global next_attack,facing_ready
    states=a.players
    if len(states)==2:
        gap=states[1]['position'][0]-states[0]['position'][0]
        # Blink crossed the victim. Stay on that side and turn toward it;
        # do not assume a fixed camera aim overrides the body's >30 degree cone.
        facing_ready = facing_ready or states[0]['facing'][0]<-.95
        a.input(((-1 if gap<0 else 1) if abs(gap)>1.4 else 0,0)); b.input()
        if abs(gap)<1.9 and time.monotonic()>next_attack:
            a.attack('punch',(-1 if gap<0 else 1,0))
            next_attack=time.monotonic()+.26
run(43,fight)
assert any(e.get('type')=='round_end' for e in a.events), ('round end',a.players,[(e.get('type'),e.get('attack'),e.get('health')) for e in a.events[-8:]])
assert any(e.get('type')=='round_reset' for e in a.events), 'round reset'
assert a.players[0]['score']>=1, 'score persists'
print('BATTLE_PROTOCOL PASS death score reset',flush=True)
# Abrupt disappearance is reclaimed by timeout, without a leave packet.
a.sock.close()
until=time.monotonic()+5.6
while time.monotonic()<until:
    b.pump(); b.input(); time.sleep(1/60)
replacement=Peer(); replacement.send({'type':'hello'})
time.sleep(.15); replacement.pump()
assert replacement.slot==0, 'vacant slot reused after timeout'
replacement.send({'type':'leave'}); b.send({'type':'leave'})
print('BATTLE_PROTOCOL PASS timeout reconnect slot reuse',flush=True)
