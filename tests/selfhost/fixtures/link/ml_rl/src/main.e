// `e.ml.rl` on a four-state corridor with a goal at the right end:
// Q-learning from random exploration converges to the optimal values
// (`gamma` powers of the goal reward), SARSA under a greedy policy reaches
// the same values, epsilon-greedy explores at the asked rate, and the
// argument checks answer. Each check exits with its own code.

use e.algo.rand
use e.io
use e.mem
use e.ml.rl
use e.os

fn near(x: f64, want: f64, eps: f64) -> bool {
    var d = x - want
    if d < 0.0f64 { d = 0.0f64 - d }
    ret d <= eps
}

// Two actions: 0 moves left, 1 moves right; state 3 is the goal (terminal, reward 1).
fn step(state: usize, action: usize) -> (usize, f64, bool) {
    var next = state
    if action == 1usize && state < 3usize { next = state + 1usize } else if action == 0usize && state > 0usize { next = state - 1usize }
    if next == 3usize { ret (next, 1.0f64, true) }
    ret (next, 0.0f64, false)
}

fn main(a: *mem.Arena, args: []str) -> err {
    var q: [8]f64 = zero
    var r = rand.pcg64(12u64, 12u64)

    // 1: Q-learning with random actions.
    var episode = 0usize
    while episode < 300usize {
        var state = 0usize
        var moving = true
        var steps = 0usize
        while moving && steps < 100usize {
            let action = rl.epsilon_greedy(q[..], 2usize, state, 1.0f64, &r)
            let (next, reward, terminal) = step(state, action)
            let (_, update_error) = rl.q_learning(q[..], 2usize, state, action, reward, next, terminal, 0.5f64, 0.9f64)
            if update_error != ok { os.exit(1i32) }
            state = next
            moving = !terminal
            steps += 1usize
        }
        episode += 1usize
    }
    // Optimal: Q(2, right) = 1, Q(1, right) = 0.9, Q(0, right) = 0.81, and left is a step behind.
    if !near(q[5usize], 1.0f64, 0.000001f64) || !near(q[3usize], 0.9f64, 0.000001f64) || !near(q[1usize], 0.81f64, 0.000001f64) { os.exit(1i32) }
    if !near(q[0usize], 0.729f64, 0.000001f64) || !near(q[2usize], 0.729f64, 0.000001f64) || !near(q[4usize], 0.81f64, 0.000001f64) { os.exit(1i32) }
    if rl.greedy(q[..], 2usize, 0usize) != 1usize || rl.greedy(q[..], 2usize, 2usize) != 1usize { os.exit(1i32) }
    let (_, q_invalid) = rl.q_learning(q[..], 2usize, 0usize, 2usize, 0.0f64, 1usize, false, 0.5f64, 0.9f64)
    if q_invalid != rl.Invalid { os.exit(1i32) }
    let (_, q_room) = rl.q_learning(q[..], 2usize, 4usize, 0usize, 0.0f64, 1usize, false, 0.5f64, 0.9f64)
    if q_room != rl.TooSmall { os.exit(1i32) }

    // 2: SARSA with a mostly greedy policy from zero.
    var i = 0usize
    while i < 8usize {
        q[i] = 0.0f64
        i += 1usize
    }
    episode = 0usize
    while episode < 400usize {
        var state = 0usize
        var action = rl.epsilon_greedy(q[..], 2usize, state, 0.2f64, &r)
        var moving = true
        var steps = 0usize
        while moving && steps < 100usize {
            let (next, reward, terminal) = step(state, action)
            let next_action = rl.epsilon_greedy(q[..], 2usize, next, 0.2f64, &r)
            let (_, update_error) = rl.sarsa(q[..], 2usize, state, action, reward, next, next_action, terminal, 0.3f64, 0.9f64)
            if update_error != ok { os.exit(2i32) }
            state = next
            action = next_action
            moving = !terminal
            steps += 1usize
        }
        episode += 1usize
    }
    // On-policy values sit a little under the optimal ones but keep the ordering.
    if q[5usize] < 0.95f64 || q[5usize] > 1.0000001f64 || q[3usize] < 0.75f64 || q[3usize] > 0.9000001f64 || q[1usize] < 0.55f64 || q[1usize] > 0.8100001f64 { os.exit(2i32) }
    if rl.greedy(q[..], 2usize, 0usize) != 1usize || rl.greedy(q[..], 2usize, 1usize) != 1usize || rl.greedy(q[..], 2usize, 2usize) != 1usize { os.exit(2i32) }
    let (_, s_invalid) = rl.sarsa(q[..], 2usize, 0usize, 0usize, 0.0f64, 1usize, 2usize, false, 0.5f64, 0.9f64)
    if s_invalid != rl.Invalid { os.exit(2i32) }

    // 3: epsilon-greedy explores at the asked rate.
    var random_picks = 0usize
    i = 0usize
    while i < 10000usize {
        if rl.epsilon_greedy(q[..], 2usize, 0usize, 0.3f64, &r) != 1usize { random_picks += 1usize }
        i += 1usize
    }
    // Only exploratory draws pick left, half of the 30 percent: about 1500.
    if random_picks < 1350usize || random_picks > 1650usize { os.exit(3i32) }
    if rl.epsilon_greedy(q[..], 2usize, 0usize, 0.0f64, &r) != 1usize { os.exit(3i32) }

    try io.print("ml rl ok\n")
    ret ok
}
