// Same template name as beta.make, declared in a different module.

type Cell[T: type] = struct { value: T }

fn make[T: type](v: T) -> Cell[T] { ret Cell[T] { value: v } }
