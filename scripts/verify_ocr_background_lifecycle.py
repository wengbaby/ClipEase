#!/usr/bin/env python3
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
STORE = ROOT / "Sources/ClipEase/Core/Storage/ClipboardHistoryStore.swift"
CONTROLLER = ROOT / "Sources/ClipEase/Features/HistoryWindow/HistoryWindowController.swift"
MODEL = ROOT / "Sources/ClipEase/Core/Models/ClipboardItem.swift"


def fail(message: str) -> None:
    print(f"FAIL: {message}")
    sys.exit(1)


def require(condition: bool, message: str) -> None:
    if not condition:
        fail(message)


def body_of_function(source: str, name: str) -> str:
    match = re.search(rf"\bfunc\s+{re.escape(name)}\b[^\{{]*\{{", source)
    if not match:
        fail(f"missing function {name}")

    depth = 1
    index = match.end()
    while index < len(source) and depth > 0:
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
        index += 1
    return source[match.end():index - 1]


def main() -> None:
    store = STORE.read_text(encoding="utf-8")
    controller = CONTROLLER.read_text(encoding="utf-8")
    model = MODEL.read_text(encoding="utf-8")

    enqueue = body_of_function(store, "enqueueOCRIfNeeded")
    perform = body_of_function(store, "performOCR")
    delete_item = body_of_function(store, "deleteItem")
    clear_all = body_of_function(store, "clearAllItems")
    delete_group = body_of_function(store, "deleteGroup")
    delete_groups = body_of_function(store, "deleteGroups")
    upsert = body_of_function(store, "upsertClipboardItem")
    prune = body_of_function(store, "pruneExpiredItems")

    require("guard item.ocrStatus == .pending else" in enqueue,
            "OCR enqueue must only schedule pending items")
    require("ocrTaskByItemID[item.id]?.cancel()" in enqueue,
            "OCR enqueue must cancel older item tasks before replacing them")
    require("Task(priority: .utility)" in enqueue,
            "OCR tasks must run as utility background work")
    require("ClipboardOCRConcurrencyLimiter.shared.waitForTurn()" in perform
            and "ClipboardOCRConcurrencyLimiter.shared.finishTurn()" in perform,
            "OCR work must pass through the dynamic concurrency limiter")
    require("guard !Task.isCancelled else" in perform,
            "OCR work must honor cancellation before applying status or results")
    require("setOCRStatus(.processing" in perform,
            "OCR work must mark processing only after it has a limiter turn")
    require("finishOCRTask(for:" in perform,
            "OCR work must clean task bookkeeping on cancellation")
    require("applyOCRResult" in perform,
            "OCR work must persist recognized results through the store")

    require("private actor ClipboardOCRConcurrencyLimiter" in store,
            "OCR dynamic concurrency limiter missing")
    require("private let idleLimit = 5" in store,
            "OCR idle concurrency limit must be 5")
    require("private let interactiveLimit = 2" in store,
            "OCR interactive concurrency limit must be 2")
    require("func setInteractionActive(_ isActive: Bool)" in store
            and "resumeAvailableWaiters()" in store,
            "OCR limiter must respond dynamically when interaction state changes")
    require("setOCRInteractiveThrottleActive" in store,
            "store must expose OCR interaction throttle update")

    require("cancelOCRTasks(for: deletedItems)" in delete_item,
            "single item deletion must cancel OCR")
    require("cancelAllOCRTasks()" in clear_all,
            "clear all must cancel every OCR task")
    require("cancelOCRTasks(for: removedItems)" in delete_group
            and "cancelOCRTasks(for: removedItems)" in delete_groups
            and "cancelOCRTasks(for: removedItems)" in prune,
            "bulk removal and retention pruning must cancel OCR")
    require("cancelOCRTasks(for: duplicateIDs)" in upsert,
            "dedupe replacement must cancel OCR tasks for removed duplicates")

    require("store.setOCRInteractiveThrottleActive(true)" in controller
            and "store.setOCRInteractiveThrottleActive(false)" in controller,
            "history window visibility must lower OCR concurrency during interaction and restore it after hiding")

    require("var ocrStatus: ClipboardOCRStatus = .none" in model
            and "var ocrText: String = \"\"" in model
            and "func updatingOCR(" in model,
            "OCR results must remain persisted on ClipboardItem rather than recomputed on window open")

    print("OK OCR background lifecycle checks passed")


if __name__ == "__main__":
    main()
