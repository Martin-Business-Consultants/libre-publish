package cms

import (
	"bytes"
	"encoding/json"
)

// Obj is a JSON object that keeps its keys in the order written, so answers
// read the way the Rails core's did (id first, timestamps last).
type Obj []kv

type kv struct {
	K string
	V any
}

// O builds an Obj from alternating keys and values.
func O(pairs ...any) Obj {
	o := make(Obj, 0, len(pairs)/2)
	for i := 0; i+1 < len(pairs); i += 2 {
		o = append(o, kv{pairs[i].(string), pairs[i+1]})
	}
	return o
}

func (o Obj) Set(k string, v any) Obj {
	for i := range o {
		if o[i].K == k {
			o[i].V = v
			return o
		}
	}
	return append(o, kv{k, v})
}

func (o Obj) Get(k string) any {
	for _, p := range o {
		if p.K == k {
			return p.V
		}
	}
	return nil
}

func (o Obj) MarshalJSON() ([]byte, error) {
	var buf bytes.Buffer
	buf.WriteByte('{')
	for i, p := range o {
		if i > 0 {
			buf.WriteByte(',')
		}
		k, _ := json.Marshal(p.K)
		buf.Write(k)
		buf.WriteByte(':')
		v, err := json.Marshal(p.V)
		if err != nil {
			return nil, err
		}
		buf.Write(v)
	}
	buf.WriteByte('}')
	return buf.Bytes(), nil
}
