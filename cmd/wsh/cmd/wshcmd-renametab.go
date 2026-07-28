// Copyright 2026, Command Line Inc.
// SPDX-License-Identifier: Apache-2.0

package cmd

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
	"github.com/wavetermdev/waveterm/pkg/wshrpc"
	"github.com/wavetermdev/waveterm/pkg/wshrpc/wshclient"
)

var renameTabCmd = &cobra.Command{
	Use:     "renametab [name]",
	Short:   "rename a tab",
	Long:    `Set the title of the current tab (or a specified tab via --tabid).`,
	Args:    cobra.ExactArgs(1),
	RunE:    renameTabRun,
	PreRunE: preRunSetupRpcClient,

	DisableFlagsInUseLine: true,
}

var renameTabTabId string

func init() {
	rootCmd.AddCommand(renameTabCmd)
	renameTabCmd.Flags().StringVar(&renameTabTabId, "tabid", "", "tab id (defaults to WAVETERM_TABID)")
}

func renameTabRun(cmd *cobra.Command, args []string) (rtnErr error) {
	defer func() {
		sendActivity("renametab", rtnErr == nil)
	}()

	tabId := renameTabTabId
	if tabId == "" {
		tabId = os.Getenv("WAVETERM_TABID")
	}
	if tabId == "" {
		return fmt.Errorf("no tab id specified (use --tabid or set WAVETERM_TABID)")
	}

	newName := args[0]
	err := wshclient.UpdateTabNameCommand(RpcClient, tabId, newName, &wshrpc.RpcOpts{Timeout: 2000})
	if err != nil {
		return fmt.Errorf("renaming tab: %w", err)
	}

	fmt.Printf("tab renamed to %q\n", newName)
	return nil
}
