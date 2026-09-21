// Tabular reinforcement learning over a row-major action-value table
// (`states × actions`) in caller storage: `q_learning` and `sarsa` apply
// one temporal-difference update each, `epsilon_greedy` picks an action
// through the caller's PCG generator, and `greedy` the best one (ties to
// the smallest index).

use e.algo.rand

error TooSmall
error Invalid

fn greedy(q: []const f64, actions: usize, state: usize) -> usize {
    var best = 0usize
    var a = 1usize
    while a < actions {
        if q[state * actions + a] > q[state * actions + best] { best = a }
        a += 1usize
    }
    ret best
}

// The greedy action with probability `1 - epsilon`, else a uniform one.
fn epsilon_greedy(q: []const f64, actions: usize, state: usize, epsilon: f64, r: *rand.Pcg64) -> usize {
    if rand.pcg64_f64(r) < epsilon { ret usize(rand.pcg64_bounded(r, u64(actions))) }
    ret greedy(q, actions, state)
}

// `Q(s, a) += rate (reward + gamma max_a' Q(s', a') - Q(s, a))`; a terminal
// `next` (`terminal` true) contributes no future value. Answers the error.
fn q_learning(q: []f64, actions: usize, state: usize, action: usize, reward: f64, next: usize, terminal: bool, rate: f64, gamma: f64) -> (f64, err) {
    if q.len < (state + 1usize) * actions || q.len < (next + 1usize) * actions { ret (0.0f64, TooSmall) }
    if action >= actions { ret (0.0f64, Invalid) }
    var future = 0.0f64
    if !terminal { future = q[next * actions + greedy(q, actions, next)] }
    let delta = reward + gamma * future - q[state * actions + action]
    q[state * actions + action] += rate * delta
    ret (delta, ok)
}

// `Q(s, a) += rate (reward + gamma Q(s', a') - Q(s, a))` with the action
// `next_action` actually taken next.
fn sarsa(q: []f64, actions: usize, state: usize, action: usize, reward: f64, next: usize, next_action: usize, terminal: bool, rate: f64, gamma: f64) -> (f64, err) {
    if q.len < (state + 1usize) * actions || q.len < (next + 1usize) * actions { ret (0.0f64, TooSmall) }
    if action >= actions || next_action >= actions { ret (0.0f64, Invalid) }
    var future = 0.0f64
    if !terminal { future = q[next * actions + next_action] }
    let delta = reward + gamma * future - q[state * actions + action]
    q[state * actions + action] += rate * delta
    ret (delta, ok)
}
