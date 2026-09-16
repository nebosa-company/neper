// The types the dispatches of `main` ask about (D430).
type Point = struct { x: i64, y: i64 }
type Shape = union enum u8 { Dot: Point, Empty }
