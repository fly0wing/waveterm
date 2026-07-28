// Copyright 2026, Command Line Inc.
// SPDX-License-Identifier: Apache-2.0

import { FocusManager } from "@/app/store/focusManager";
import { atoms, getBlockMetaKeyAtom, getOrefMetaKeyAtom } from "@/app/store/global";
import { globalStore } from "@/app/store/jotaiStore";
import { RpcApi } from "@/app/store/wshclientapi";
import { getWaveObjectAtom, makeORef } from "@/app/store/wos";
import { TabRpcClient } from "@/app/store/wshrpcutil";

const MaxAutoNameLength = 30;

function dirBaseName(cwd: string): string {
    if (!cwd) {
        return null;
    }
    const parts = cwd.split("/").filter((p) => p !== "");
    if (parts.length === 0) {
        return "/";
    }
    const base = parts[parts.length - 1];
    return [...base].slice(0, MaxAutoNameLength).join("");
}

export class TabAutoNameModel {
    private static instance: TabAutoNameModel | null = null;

    unsubFocus: () => void = null;
    unsubCwd: () => void = null;
    curBlockId: string = null;

    private constructor() {
        this.unsubFocus = globalStore.sub(FocusManager.getInstance().blockFocusAtom, () => {
            this.onFocusChange();
        });
        this.onFocusChange();
    }

    static getInstance(): TabAutoNameModel {
        if (!TabAutoNameModel.instance) {
            TabAutoNameModel.instance = new TabAutoNameModel();
        }
        return TabAutoNameModel.instance;
    }

    static resetInstance(): void {
        if (TabAutoNameModel.instance) {
            TabAutoNameModel.instance.dispose();
            TabAutoNameModel.instance = null;
        }
    }

    onFocusChange() {
        const blockId = globalStore.get(FocusManager.getInstance().blockFocusAtom);
        if (blockId === this.curBlockId) {
            return;
        }
        this.curBlockId = blockId;
        if (this.unsubCwd != null) {
            this.unsubCwd();
            this.unsubCwd = null;
        }
        if (blockId == null) {
            return;
        }
        this.unsubCwd = globalStore.sub(getBlockMetaKeyAtom(blockId, "cmd:cwd"), () => {
            this.maybeRename();
        });
        this.maybeRename();
    }

    maybeRename() {
        const blockId = this.curBlockId;
        if (blockId == null) {
            return;
        }
        const cwd = globalStore.get(getBlockMetaKeyAtom(blockId, "cmd:cwd"));
        if (cwd == null) {
            return;
        }
        const newName = dirBaseName(cwd);
        if (!newName) {
            return;
        }
        const tabId = globalStore.get(atoms.staticTabId);
        if (!tabId) {
            return;
        }
        const isManual = globalStore.get(getOrefMetaKeyAtom(makeORef("tab", tabId), "tab:manualname"));
        if (isManual) {
            return;
        }
        const tabData = globalStore.get(getWaveObjectAtom<Tab>(makeORef("tab", tabId)));
        if (tabData?.name === newName) {
            return;
        }
        RpcApi.UpdateTabNameCommand(TabRpcClient, tabId, newName);
    }

    dispose() {
        if (this.unsubFocus != null) {
            this.unsubFocus();
            this.unsubFocus = null;
        }
        if (this.unsubCwd != null) {
            this.unsubCwd();
            this.unsubCwd = null;
        }
    }
}
