//go:build windows

package datalock

import (
	"os"
	"syscall"
	"unsafe"
)

// LockFileEx, from kernel32, without depending on golang.org/x/sys.
var (
	kernel32         = syscall.NewLazyDLL("kernel32.dll")
	procLockFileEx   = kernel32.NewProc("LockFileEx")
	procUnlockFileEx = kernel32.NewProc("UnlockFileEx")
)

const (
	lockfileExclusiveLock   = 0x2
	lockfileFailImmediately = 0x1
	errorLockViolation      = syscall.Errno(33)
)

var errWouldBlock = errorLockViolation

func lock(f *os.File) error {
	var ol syscall.Overlapped
	r, _, err := procLockFileEx.Call(f.Fd(), lockfileExclusiveLock|lockfileFailImmediately, 0, 1, 0, uintptr(unsafe.Pointer(&ol))) //nolint:gosec // the Win32 call takes the OVERLAPPED's address
	if r == 0 {
		return err
	}
	return nil
}

func unlock(f *os.File) error {
	var ol syscall.Overlapped
	r, _, err := procUnlockFileEx.Call(f.Fd(), 0, 1, 0, uintptr(unsafe.Pointer(&ol))) //nolint:gosec // the Win32 call takes the OVERLAPPED's address
	if r == 0 {
		return err
	}
	return nil
}
