package main

import (
	"flag"
	"fmt"
	"os"

	"apm-inject-min/internal/apminject/utils"
)

func main() {
	var (
		action     string
		mode       string
		installDir string
	)

	flag.StringVar(&action, "action", "install", "install | uninstall")
	flag.StringVar(&mode, "mode", "host,docker", "host | docker | host,docker | disable")
	flag.StringVar(&installDir, "install-dir", "/usr/local/datakit", "datakit install dir")
	flag.Parse()

	log := utils.NewLogger("injectctl")

	opts := []utils.Opt{
		utils.WithInstallDir(installDir),
		utils.WithInstrumentationEnabled(mode),
	}

	switch action {
	case "install":
		if err := utils.Install(log, opts...); err != nil {
			fmt.Fprintf(os.Stderr, "install failed: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("install ok")
	case "uninstall":
		if err := utils.Uninstall(opts...); err != nil {
			fmt.Fprintf(os.Stderr, "uninstall failed: %v\n", err)
			os.Exit(1)
		}
		fmt.Println("uninstall ok")
	default:
		fmt.Fprintf(os.Stderr, "unknown action: %s\n", action)
		os.Exit(2)
	}
}
