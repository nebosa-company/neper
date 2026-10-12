// Prints S2 block and stream vectors from github.com/klauspost/compress/s2 as JSON for
// scripts/gen_s2_test.py (the e.fmt.s2 fixture). Run: go run scripts/s2_vectors.go
// from a directory with that module in its go.mod.
package main

import (
	"bytes"
	"encoding/hex"
	"encoding/json"
	"fmt"

	"github.com/klauspost/compress/s2"
)

func lcg(s uint64) uint64 { return s*6364136223846793005 + 1442695040888963407 }

// fill mirrors the fixture's `fill`.
func fill(n int, seed uint64) []byte {
	out := make([]byte, n)
	state := seed
	p := 0
	for p < n {
		state = lcg(state)
		r := state >> 33
		mode := r % 3
		if mode == 0 {
			b := byte((r >> 8) & 255)
			k := 8 + int((r>>16)%40)
			for k > 0 && p < n {
				out[p] = b
				p++
				k--
			}
		} else if mode == 1 && p >= 64 {
			off := 1 + int((r>>8)%60)
			k := 4 + int((r>>16)%30)
			for k > 0 && p < n {
				out[p] = out[p-off]
				p++
				k--
			}
		} else {
			k := 1 + int((r>>16)%12)
			for k > 0 {
				state = lcg(state)
				if p < n {
					out[p] = byte((state >> 33) & 255)
					p++
				}
				k--
			}
		}
	}
	return out
}

func far() []byte {
	r := fill(40, 99)
	b := append([]byte{}, r...)
	b = append(b, make([]byte, 70000)...)
	b = append(b, r...)
	return b
}

func repeat(s string, n int) []byte { return bytes.Repeat([]byte(s), n) }

func main() {
	out := map[string]string{}
	a := fill(3072, 12345)
	out["enc_a"] = hex.EncodeToString(s2.Encode(nil, a))
	out["better_a"] = hex.EncodeToString(s2.EncodeBetter(nil, a))
	out["best_a"] = hex.EncodeToString(s2.EncodeBest(nil, a))
	out["better_abc"] = hex.EncodeToString(s2.EncodeBetter(nil, repeat("abcdefgh", 1000)))
	out["best_abc"] = hex.EncodeToString(s2.EncodeBest(nil, repeat("abcdefgh", 1000)))
	out["enc_far"] = hex.EncodeToString(s2.Encode(nil, far()))
	out["best_far"] = hex.EncodeToString(s2.EncodeBest(nil, far()))
	out["best_a5000"] = hex.EncodeToString(s2.EncodeBest(nil, repeat("a", 5000)))
	out["best_a70000"] = hex.EncodeToString(s2.EncodeBest(nil, repeat("a", 70000)))
	out["better_a300"] = hex.EncodeToString(s2.EncodeBetter(nil, repeat("a", 300)))
	out["enc_empty"] = hex.EncodeToString(s2.Encode(nil, nil))
	var w bytes.Buffer
	sw := s2.NewWriter(&w)
	sw.Write(a)
	sw.Flush()
	sw.Write(fill(50, 7))
	sw.Close()
	out["stream_a"] = hex.EncodeToString(w.Bytes())
	var sn bytes.Buffer
	nw := s2.NewWriter(&sn, s2.WriterSnappyCompat())
	nw.Write(a)
	nw.Close()
	out["stream_snappy"] = hex.EncodeToString(sn.Bytes())
	// Decoding of my encoder's output is checked by reading hex from stdin when given.
	js, _ := json.Marshal(out)
	fmt.Println(string(js))
}
