package main

import "fmt"

const n, iterations = 1048576, 16

func main() {
	x, y := make([]uint32, n), make([]uint32, n)
	for i := range x { x[i], y[i] = uint32(i&1023), 1 }
	for iteration := 0; iteration < iterations; iteration++ { for i := range y { y[i] = 3*x[i] + y[i] } }
	var checksum uint64
	for _, value := range y { checksum += uint64(value) }
	fmt.Printf("gp10 %d\n", checksum)
}
