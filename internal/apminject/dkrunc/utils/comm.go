// Unless explicitly stated otherwise all files in this repository are licensed
// under the MIT License.
// This product includes software developed at Guance Cloud (https://www.guance.com/).
// Copyright 2021-present Guance, Inc.

package utils

import (
	"os"
	"path/filepath"
)

var (
	installDir = envOr("DK_INSTALL_DIR", "/usr/local/datakit")

	DirInject          = filepath.Join(installDir, "apm_inject/")
	DirInjectSubInject = filepath.Join(installDir, "apm_inject/inject")
	DirInjectSubLib    = filepath.Join(installDir, "apm_inject/lib")
	DirInjectSubLog    = filepath.Join(installDir, "apm_inject/log")

	InjectSubInject = "inject"
	InjectSubLib    = "lib"
	InjectSubLog    = "log"
)

func envOr(k, fallback string) string {
	if v := os.Getenv(k); v != "" {
		return v
	}
	return fallback
}
