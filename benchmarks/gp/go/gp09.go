package main

import "fmt"

const n, iterations = 4194317, 8

func main() {
	input, text, back := make([]byte, n), make([]byte, 2*n), make([]byte, n)
	hex := []byte("0123456789abcdef")
	for i := range input { input[i] = byte(i*73 + 19) }
	for iteration := 0; iteration < iterations; iteration++ {
		for i, value := range input { text[2*i], text[2*i+1] = hex[value>>4], hex[value&15] }
		for i := range back {
			nibble := func(c byte) byte { if c <= '9' { return c - '0' }; return c - 'a' + 10 }
			hi, lo := nibble(text[2*i]), nibble(text[2*i+1])
			if hi > 15 || lo > 15 { panic("invalid") }
			back[i] = hi<<4 | lo
		}
	}
	var checksum uint64
	for i, value := range back { if value != input[i] { panic("mismatch") }; checksum += uint64(value) }
	fmt.Printf("gp09 %d\n", checksum)
}
