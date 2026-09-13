use leaf

fn twice(n: usize) -> usize { ret leaf.add(n, n) }

fn fail() { leaf.boom() }
