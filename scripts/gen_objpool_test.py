"""Oracle for tests/selfhost/fixtures/link/data_objpool (L158, D2687).

An independent model of the e.data.objpool state machine (plain lists, the rules
restated from the module's header) driven by the fixture's LCG operation stream; the
rolling FNV-1a hash of every answer is the constant the fixture compares to. Run it
to print the constants:  python scripts/gen_objpool_test.py
"""
M = 2**64
NONE = 0xffffffff
EMPTY, PENDING, IDLE, BORROWED = 0, 1, 2, 3
REUSED, NEEDS_CREATE, QUEUED, EXHAUSTED = 0, 1, 2, 3


class Model:
    def __init__(self, max_total, max_idle, min_idle, idle_ticks, leak_ticks, lifo, wait, queue):
        self.n = max_total
        self.max_idle, self.min_idle = max_idle, min_idle
        self.idle_ticks, self.leak_ticks = idle_ticks, leak_ticks
        self.lifo, self.wait, self.queue = lifo, wait, queue
        self.state = [EMPTY] * max_total
        self.since = [0] * max_total
        self.waiters = []  # (who, at)
        self.created = self.destroyed = self.evicted = self.leaked = 0

    def idle_slots(self):
        return [i for i in range(self.n) if self.state[i] == IDLE]

    def pick(self, newest):
        idle = self.idle_slots()
        if not idle:
            return NONE
        key = (lambda i: (-self.since[i], i)) if newest else (lambda i: (self.since[i], i))
        return min(idle, key=key)

    def acquire(self, now, who):
        s = self.pick(self.lifo)
        if s != NONE:
            self.state[s] = BORROWED
            self.since[s] = now
            return REUSED, s
        for i in range(self.n):
            if self.state[i] == EMPTY:
                self.state[i] = PENDING
                self.since[i] = now
                return NEEDS_CREATE, i
        if self.wait and len(self.waiters) < self.queue:
            self.waiters.append((who, now))
            return QUEUED, NONE
        return EXHAUSTED, NONE

    def attach(self, slot, now):
        assert self.state[slot] == PENDING
        self.state[slot] = BORROWED
        self.since[slot] = now
        self.created += 1

    def release(self, slot, now, healthy):
        assert self.state[slot] == BORROWED
        if self.waiters:
            who, _ = self.waiters.pop(0)
            if healthy:
                self.state[slot] = BORROWED
                self.since[slot] = now
                return (False, True, who, False)
            self.destroyed += 1
            self.state[slot] = PENDING
            self.since[slot] = now
            return (True, True, who, True)
        if healthy and len(self.idle_slots()) < self.max_idle:
            self.state[slot] = IDLE
            self.since[slot] = now
            return (False, False, 0, False)
        self.state[slot] = EMPTY
        self.destroyed += 1
        return (True, False, 0, False)

    def evict(self, now, room):
        out = []
        if self.idle_ticks == 0:
            return out
        while len(out) < room and len(self.idle_slots()) > self.min_idle:
            oldest = self.pick(False)
            if oldest == NONE or now - self.since[oldest] < self.idle_ticks:
                break
            self.state[oldest] = EMPTY
            self.evicted += 1
            self.destroyed += 1
            out.append(oldest)
        return out

    def leaks(self, now, room):
        if self.leak_ticks == 0:
            return []
        return [i for i in range(self.n) if self.state[i] == BORROWED and now - self.since[i] >= self.leak_ticks][:room]

    def expire(self, now, max_wait, room):
        out, kept = [], []
        for who, at in self.waiters:
            if now - at >= max_wait and len(out) < room:
                out.append(who)
            else:
                kept.append((who, at))
        self.waiters = kept
        return out


def drive(iterations=400):
    m = Model(5, 3, 1, 20, 30, True, True, 4)
    h = 14695981039346656037

    def mix(v):
        nonlocal h
        h = ((h ^ (v % M)) * 1099511628211) % M

    x, now = 7, 0
    for it in range(iterations):
        x = (x * 6364136223846793005 + 1442695040888963407) % M
        r = x >> 33
        now += r % 7
        op = (r >> 3) % 8
        if op <= 2:
            outcome, slot = m.acquire(now, it)
            mix(1), mix(outcome), mix(slot)
        elif op <= 4:
            borrowed = [i for i in range(m.n) if m.state[i] == BORROWED]
            if not borrowed:
                mix(2)
            else:
                slot = borrowed[(r >> 8) % len(borrowed)]
                healthy = ((r >> 16) % 5) != 0
                d, ho, who, nc = m.release(slot, now, healthy)
                mix(3), mix(slot), mix(1 if healthy else 0), mix(int(d)), mix(int(ho)), mix(who), mix(int(nc))
        elif op == 5:
            pending = [i for i in range(m.n) if m.state[i] == PENDING]
            if not pending:
                mix(4)
            else:
                m.attach(pending[0], now)
                mix(5), mix(pending[0])
        elif op == 6:
            out = m.evict(now, 8)
            mix(6), mix(len(out))
            for s in out:
                mix(s)
        else:
            out = m.leaks(now, 8)
            mix(7), mix(len(out))
            for s in out:
                mix(s)
            if out:
                m.leaked += 1
                d, ho, who, nc = m.release(out[0], now, False)
                mix(int(d)), mix(int(ho)), mix(who), mix(int(nc))
        if it % 50 == 49:
            out = m.expire(now, 25, 8)
            mix(8), mix(len(out))
            for w in out:
                mix(w)
    for s in (EMPTY, PENDING, IDLE, BORROWED):
        mix(m.state.count(s))
    mix(m.created), mix(m.destroyed), mix(m.evicted), mix(m.leaked)
    return h, m


if __name__ == '__main__':
    h, m = drive()
    print('hash', h)
    print('states', [m.state.count(s) for s in (EMPTY, PENDING, IDLE, BORROWED)])
    print('created', m.created, 'destroyed', m.destroyed, 'evicted', m.evicted, 'leaked', m.leaked)
