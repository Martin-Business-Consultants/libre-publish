package datalock

import (
	"errors"
	"testing"
)

func TestAcquire(t *testing.T) {
	t.Parallel()
	dir := t.TempDir()
	first, err := Acquire(dir)
	if err != nil {
		t.Fatal(err)
	}
	// A second holder, even in this process (a lock is per open file), is
	// refused at once, and told who has it.
	if _, err := Acquire(dir); !errors.Is(err, ErrLocked) {
		t.Fatalf("second acquire: %v", err)
	}
	if err := first.Release(); err != nil {
		t.Fatal(err)
	}
	if err := first.Release(); err != nil {
		t.Fatalf("second release: %v", err)
	}
	again, err := Acquire(dir)
	if err != nil {
		t.Fatalf("after release: %v", err)
	}
	again.Release()
}
