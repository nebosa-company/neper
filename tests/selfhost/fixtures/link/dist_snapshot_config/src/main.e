// An uncommitted membership entry after a snapshot boundary must not be sent
// to, or installed by, a lagging follower with that earlier snapshot.
use e.os
use e.dist.consensus

fn main() {
    var leader_log: [4]consensus.Entry = zero
    var follower_log: [4]consensus.Entry = zero
    var leader_next: [2]u64 = zero
    var follower_next: [2]u64 = zero
    var leader_match: [2]u64 = zero
    var follower_match: [2]u64 = zero
    var nodes: [2]consensus.Node = zero
    nodes[0usize] = consensus.raft_node(0u32, leader_log[0..], leader_next[0..], leader_match[0..], 3u64)
    nodes[1usize] = consensus.raft_node(1u32, follower_log[0..], follower_next[0..], follower_match[0..], 3u64)
    var cluster = consensus.raft_cluster(nodes[0..], 7u64, 1u64, 1u64, 1u64)

    cluster.nodes[0usize].role = .Leader
    cluster.nodes[0usize].term = 7u64
    if consensus.append_entry(&cluster.nodes[0usize], consensus.Entry { term: 7u64, value: 20i64, cfg_old: 0u64, cfg_new: 0u64 }) != ok { os.exit(1) }
    // This joint configuration is appended but has not committed/applied.
    if consensus.append_entry(&cluster.nodes[0usize], consensus.Entry { term: 7u64, value: 0i64, cfg_old: 3u64, cfg_new: 7u64 }) != ok { os.exit(2) }
    cluster.nodes[0usize].commit = 1u64
    cluster.nodes[0usize].applied = 1u64
    cluster.nodes[0usize].state = 20i64
    if consensus.raft_snapshot(&cluster, 0usize) != ok { os.exit(3) }
    if cluster.nodes[0usize].snap_index != 1u64 || cluster.nodes[0usize].snap_cfg_old != 3u64 || cluster.nodes[0usize].snap_cfg_new != 3u64 { os.exit(4) }
    // The node's latest appended configuration is deliberately newer than its snapshot.
    if cluster.nodes[0usize].cfg_old != 3u64 || cluster.nodes[0usize].cfg_new != 7u64 { os.exit(5) }

    cluster.nodes[0usize].next_index[1usize] = 1u64
    var wire: [4]consensus.Message = zero
    var outgoing = consensus.pool(wire[0..])
    if consensus.send_append(&cluster, &cluster.nodes[0usize], 1u32, &outgoing) != ok || outgoing.len != 1usize { os.exit(6) }
    let snapshot = outgoing.items[0usize]
    if snapshot.kind != .InstallSnapshot || snapshot.entry.cfg_old != 3u64 || snapshot.entry.cfg_new != 3u64 { os.exit(7) }

    var replies: [4]consensus.Message = zero
    var response = consensus.pool(replies[0..])
    if consensus.raft_snapshot_step(&cluster, 1usize, 10u64, &snapshot, &response) != ok { os.exit(8) }
    if cluster.nodes[1usize].snap_index != 1u64 || cluster.nodes[1usize].snap_cfg_old != 3u64 || cluster.nodes[1usize].snap_cfg_new != 3u64 { os.exit(9) }
    if cluster.nodes[1usize].cfg_old != 3u64 || cluster.nodes[1usize].cfg_new != 3u64 { os.exit(10) }
    os.exit(0)
}
