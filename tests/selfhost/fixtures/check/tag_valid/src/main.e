use dep as d

type Local = union enum u8 {
    Empty,
    Value: i32,
}

fn run(local: Local, remote: d.Remote) {
    let local_tag: Local.Tag = local.tag
    let remote_tag: d.Remote.Tag = remote.tag
    if local_tag == Local.Tag.Value && remote_tag == d.Remote.Tag.Empty {
        let copy = local_tag
    }
    if local.tag == .Empty {
        let copy = remote_tag
    }
    switch local.tag {
    case .Empty:
        let copy = local_tag
    case .Value:
        let copy = local_tag
    }
}
