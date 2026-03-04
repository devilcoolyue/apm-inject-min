package utils

import (
	"log"
	"os"
)

type Logger struct {
	l *log.Logger
}

func NewLogger(prefix string) *Logger {
	if prefix == "" {
		prefix = "apm-inject"
	}
	return &Logger{l: log.New(os.Stderr, prefix+" ", log.LstdFlags)}
}

func (l *Logger) Info(v ...any) {
	if l != nil && l.l != nil {
		l.l.Println(v...)
	}
}

func (l *Logger) Warn(v ...any) {
	if l != nil && l.l != nil {
		l.l.Println(v...)
	}
}

func (l *Logger) Error(v ...any) {
	if l != nil && l.l != nil {
		l.l.Println(v...)
	}
}

func (l *Logger) Infof(f string, v ...any) {
	if l != nil && l.l != nil {
		l.l.Printf(f, v...)
	}
}

func (l *Logger) Warnf(f string, v ...any) {
	if l != nil && l.l != nil {
		l.l.Printf(f, v...)
	}
}
