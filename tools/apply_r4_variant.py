#!/usr/bin/env python3
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]

VARIANTS = {
    "r4.2.1": {
        "policy": "WINDOW_POLICY_SOFT_HIDE",
        "name": "R4.2.1 Soft Hide",
        "build_id": "2026-08-05-r4.2.1-soft-hide",
        "slug": "r4.2.1",
        "branch": "r4.2.1-soft-hide",
        "behavior": "After the first primary maneuver, leave context 74 active and hide only the renderer surface outside the approach zone.",
        "behavior_zh": "首个主 maneuver 结束后，接近区外保持 Context 74，仅软隐藏 renderer 画面。",
    },
    "r4.2.2": {
        "policy": "WINDOW_POLICY_CONTEXT_72",
        "name": "R4.2.2 Context 72",
        "build_id": "2026-08-05-r4.2.2-context72",
        "slug": "r4.2.2",
        "branch": "r4.2.2-context72",
        "behavior": "After the first primary maneuver, hide the renderer and return to context 72 outside the approach zone.",
        "behavior_zh": "首个主 maneuver 结束后，接近区外隐藏 renderer 并明确返回 Context 72。",
    },
    "r4.3": {
        "policy": "WINDOW_POLICY_ALWAYS_ON",
        "name": "R4.3 Always On",
        "build_id": "2026-08-05-r4.3-always-on",
        "slug": "r4.3",
        "branch": "r4.3-always-on",
        "behavior": "Keep context 74 and the renderer visible for the whole active route; show ICON_APPROACH outside the approach zone.",
        "behavior_zh": "有效导航期间持续占用 Context 74；接近区外显示 ICON_APPROACH 直行线头。",
    },
}


def fail(msg: str) -> None:
    raise RuntimeError(msg)


def replace_once(text: str, old: str, new: str, label: str) -> str:
    count = text.count(old)
    if count != 1:
        fail(f"{label}: expected exactly one match, found {count}")
    return text.replace(old, new, 1)


def replace_between(text: str, start: str, end: str, replacement: str, label: str) -> str:
    i = text.find(start)
    if i < 0:
        fail(f"{label}: start marker not found")
    j = text.find(end, i)
    if j < 0:
        fail(f"{label}: end marker not found")
    return text[:i] + replacement + text[j:]


def modify_bap(cfg: dict) -> None:
    path = ROOT / "java_patch/com/luka/carplay/routeguidance/BAPBridge.java"
    text = path.read_text(encoding="utf-8")
    marker = f"R4_VARIANT_POLICY: {cfg['slug']}"
    if marker in text:
        return
    if "R4_VARIANT_POLICY:" in text:
        fail("BAPBridge already contains a different R4 variant marker")

    old_constants = """    private static final int CITY_PREPARE_THRESHOLD_M = 1500;\n    private static final int HIGHWAY_PREPARE_THRESHOLD_M = 3000;\n    private static final int BARGRAPH_ACTION_PERCENT_OF_PREPARE = 15;\n"""
    new_constants = f"""    /* {marker}\n     * Simple and deterministic threshold policy:\n     * - route step > 2 km: expose the real maneuver at 1000 m\n     * - otherwise: expose it at 350 m\n     * - when step length is unavailable, explicit highway maneuver types are\n     *   used only as a fallback.\n     */\n    private static final int CITY_PREPARE_THRESHOLD_M = 350;\n    private static final int HIGHWAY_PREPARE_THRESHOLD_M = 1000;\n    private static final int HIGHWAY_STEP_THRESHOLD_M = 2000;\n\n    private static final int WINDOW_POLICY_SOFT_HIDE = 1;\n    private static final int WINDOW_POLICY_CONTEXT_72 = 2;\n    private static final int WINDOW_POLICY_ALWAYS_ON = 3;\n    private static final int WINDOW_POLICY = {cfg['policy']};\n\n    private static final int BARGRAPH_ACTION_PERCENT_OF_PREPARE = 15;\n"""
    text = replace_once(text, old_constants, new_constants, "threshold constants")

    text = replace_once(
        text,
        "    private boolean inApproachZone = false;\n",
        """    private boolean inApproachZone = false;\n    /* The first primary maneuver is allowed to expose ICON_APPROACH even when\n     * it is farther than the approach threshold.  Once the primary slot/version\n     * changes, normal per-version window policy takes over. */\n    private boolean firstPrimaryPending = true;\n    private boolean customRendererSoftHidden = false;\n""",
        "approach fields",
    )

    text = replace_once(
        text,
        "    private boolean customRendererPrepared = false;\n    private boolean customRendererStarted = false;\n",
        """    private boolean customRendererPrepared = false;\n    private boolean customRendererStarted = false;\n    private boolean rendererPrepareThreadRunning = false;\n""",
        "renderer fields",
    )

    text = replace_once(
        text,
        """            markCustomRendererRouteActive();\n            inApproachZone = false;\n            lastFirstManeuverIdx = -1;\n            lastFirstManeuverVer = -1;\n""",
        """            markCustomRendererRouteActive();\n            inApproachZone = false;\n            firstPrimaryPending = true;\n            customRendererSoftHidden = false;\n            lastFirstManeuverIdx = -1;\n            lastFirstManeuverVer = -1;\n""",
        "onStart state reset",
    )

    text = replace_once(
        text,
        "                isHighway = rawStepM > 1500;\n",
        "                isHighway = rawStepM > HIGHWAY_STEP_THRESHOLD_M;\n",
        "2km route-step threshold",
    )

    old_primary = """            if (primaryChanged) {\n                inApproachZone = false;\n                lastFirstManeuverIdx = firstIdx;\n                lastFirstManeuverVer = currentFirstVer;\n            }\n"""
    new_primary = """            if (primaryChanged) {\n                /* A real slot/version transition after the first valid primary\n                 * ends the startup exception.  Later far maneuvers follow the\n                 * selected window policy instead of remaining visible merely\n                 * because they are first in a refreshed list. */\n                if (lastFirstManeuverIdx >= 0) {\n                    firstPrimaryPending = false;\n                }\n                inApproachZone = false;\n                lastFirstManeuverIdx = firstIdx;\n                lastFirstManeuverVer = currentFirstVer;\n            }\n"""
    text = replace_once(text, old_primary, new_primary, "first primary transition")

    old_after_clear = """            if (explicitClear || shouldClearManeuver) {\n                latchedTurnToText = \"\";\n            }\n\n"""
    new_after_clear = """            if (explicitClear || shouldClearManeuver) {\n                latchedTurnToText = \"\";\n            }\n\n            /* Decide renderer visibility once and reuse the exact same state\n             * for preparation and the final renderer update.  Starting the\n             * renderer on a helper thread overlaps its READY wait with the BAP\n             * descriptor/distance/ExitView work below. */\n            boolean rendererApproach = nowApproach\n                && showManeuver\n                && hasManeuverList\n                && !explicitClear\n                && !shouldClearManeuver;\n            boolean rendererHasValidState = showManeuver\n                && hasManeuverList\n                && hasUsableDistance\n                && !explicitClear\n                && !shouldClearManeuver;\n            boolean rendererTransientState = customRendererStarted\n                && hasAnyManeuver\n                && !explicitClear\n                && !shouldClearManeuver\n                && (!hasManeuverList || !hasUsableDistance);\n            boolean rendererFollowStreet = rendererHasValidState && !rendererApproach;\n            boolean rendererShouldBeVisible;\n            if (WINDOW_POLICY == WINDOW_POLICY_ALWAYS_ON) {\n                rendererShouldBeVisible = rendererHasValidState || rendererTransientState;\n            } else {\n                rendererShouldBeVisible = rendererApproach\n                    || (firstPrimaryPending && rendererHasValidState)\n                    || rendererTransientState;\n            }\n            if (rendererShouldBeVisible && rendererHasValidState\n                    && !customRendererPrepared && !customRendererStarted) {\n                startCustomRendererAsync();\n            }\n\n"""
    text = replace_once(text, old_after_clear, new_after_clear, "renderer decision insertion")

    start_marker = "            /* 10. c_render: CMD_MANEUVER only when icon actually changes,"
    end_marker = "            Log.d(TAG, \"Update: dist=\""
    renderer_block = """            /* 10. c_render: variant-specific visibility policy. */\n            if (customRendererStarted && !rendererShouldBeVisible) {\n                if (WINDOW_POLICY == WINDOW_POLICY_SOFT_HIDE) {\n                    softHideCustomRendererForCruise();\n                } else {\n                    hideCustomRendererForCruise();\n                }\n            }\n\n            if (rendererShouldBeVisible && rendererHasValidState\n                    && !customRendererPrepared && !customRendererStarted) {\n                startCustomRendererAsync();\n            }\n\n            if (rendererShouldBeVisible && rendererHasValidState\n                    && !customRendererStarted) {\n                awaitRendererPreparation(CR_READY_TIMEOUT_MS + 500);\n                if (customRendererPrepared && !customRendererStarted) {\n                    activatePreparedCustomRenderer(s, bargraphDenominatorM, rendererFollowStreet);\n                }\n            }\n\n            if (rendererClient != null && customRendererStarted\n                    && rendererShouldBeVisible && rendererHasValidState) {\n                if (customRendererSoftHidden) {\n                    resumeSoftHiddenCustomRenderer(s, bargraphDenominatorM, rendererFollowStreet);\n                } else if (rendererFollowStreet) {\n                    sendRendererFollowStreet();\n                    noteRendererSendResult(rendererClient.sendBargraph(0, 0));\n                } else {\n                    if (approachChanged && nowApproach) {\n                        updateRendererBargraph(s, bargraphDenominatorM);\n                    }\n                    boolean iconChanged = false;\n                    int crIconMask = RouteGuidance.State.DIRTY_MANEUVER_ICON\n                        | RouteGuidance.State.DIRTY_MANEUVER_LIST\n                        | RouteGuidance.State.DIRTY_MANEUVER_COUNT;\n                    if ((dirty & crIconMask) != 0 || lastCrIcon == RendererMapper.ICON_APPROACH) {\n                        iconChanged = updateRendererIfChanged(s, bargraphDenominatorM);\n                    }\n                    if (!iconChanged && !approachChanged && inApproachZone\n                            && (dirty & RouteGuidance.State.DIRTY_DIST_MAN) != 0) {\n                        updateRendererBargraph(s, bargraphDenominatorM);\n                    }\n                }\n            }\n\n"""
    text = replace_between(text, start_marker, end_marker, renderer_block, "renderer policy block")

    old_activate_sig = """    private synchronized boolean activatePreparedCustomRenderer(\n            RouteGuidance.State s, int bargraphDenominatorM) {\n"""
    new_activate_sig = """    private synchronized boolean activatePreparedCustomRenderer(\n            RouteGuidance.State s, int bargraphDenominatorM, boolean followStreet) {\n"""
    text = replace_once(text, old_activate_sig, new_activate_sig, "activate signature")

    old_preload = """        /* The first real maneuver is preloaded at alpha=0.  The renderer\n         * acknowledges a defined transparent frame before the LVDS path is\n         * exposed, so no synthetic FOLLOW_STREET frame is needed. */\n        if (!updateRendererIfChanged(s, bargraphDenominatorM)) {\n            return false;\n        }\n"""
    new_preload = """        /* Preload exactly what will be exposed after the context switch.\n         * A far first maneuver (and R4.3 cruise state) uses ICON_APPROACH;\n         * approach-zone activation uses the real maneuver. */\n        boolean preloaded = followStreet\n            ? preloadRendererFollowStreet()\n            : updateRendererIfChanged(s, bargraphDenominatorM);\n        if (!preloaded) {\n            return false;\n        }\n"""
    text = replace_once(text, old_preload, new_preload, "prepared preload selection")

    text = replace_once(
        text,
        """        customRendererPrepared = false;\n        customRendererStarted = true;\n        Log.i(TAG, \"CR: started with real maneuver\");\n""",
        """        customRendererPrepared = false;\n        customRendererStarted = true;\n        customRendererSoftHidden = false;\n        Log.i(TAG, \"CR: started with \" + (followStreet ? \"FOLLOW_STREET\" : \"real maneuver\"));\n""",
        "activation completion",
    )

    async_marker = "    private synchronized void startCustomRenderer() {\n"
    async_methods = """    private synchronized void startCustomRendererAsync() {\n        if (customRendererPrepared || customRendererStarted || rendererPrepareThreadRunning) return;\n        rendererPrepareThreadRunning = true;\n        Thread t = new Thread(new Runnable() {\n            public void run() {\n                try {\n                    startCustomRenderer();\n                } finally {\n                    synchronized (BAPBridge.this) {\n                        rendererPrepareThreadRunning = false;\n                        BAPBridge.this.notifyAll();\n                    }\n                }\n            }\n        }, \"CRPrepare\");\n        t.setDaemon(true);\n        t.start();\n    }\n\n    private synchronized void awaitRendererPreparation(long timeoutMs) {\n        long deadline = System.currentTimeMillis() + timeoutMs;\n        while (rendererPrepareThreadRunning\n                && !customRendererPrepared && !customRendererStarted) {\n            long left = deadline - System.currentTimeMillis();\n            if (left <= 0) break;\n            try { wait(left); }\n            catch (InterruptedException e) {\n                Thread.currentThread().interrupt();\n                break;\n            }\n        }\n    }\n\n""" + async_marker
    text = replace_once(text, async_marker, async_methods, "async renderer preparation")

    hide_marker = "    private synchronized void hideCustomRendererForCruise() {\n"
    soft_methods = """    private synchronized void softHideCustomRendererForCruise() {\n        if (!customRendererStarted || customRendererSoftHidden) return;\n        try {\n            if (rendererClient != null) {\n                noteRendererSendResult(rendererClient.sendBargraph(0, 0));\n                if (!rendererClient.sendHideDisplay()) {\n                    Log.w(TAG, \"CR: soft hide-display send failed\");\n                }\n            }\n            customRendererSoftHidden = true;\n            lastCrIcon = -1;\n            lastCrDirection = -99;\n            lastCrExitAngle = -9999;\n            lastCrDrivingSide = -1;\n            lastCrVer = -1;\n            Log.i(TAG, \"CR: soft-hidden outside approach zone; context 74 retained\");\n        } catch (Throwable t) {\n            Log.w(TAG, \"CR soft hide failed: \" + t.getMessage());\n        }\n    }\n\n    private synchronized void resumeSoftHiddenCustomRenderer(\n            RouteGuidance.State s, int bargraphDenominatorM, boolean followStreet) {\n        if (!customRendererStarted || !customRendererSoftHidden || rendererClient == null) return;\n        boolean sent = followStreet\n            ? sendRendererFollowStreet()\n            : updateRendererIfChanged(s, bargraphDenominatorM);\n        if (!sent) return;\n        if (!rendererClient.sendStartAnimation()) {\n            noteRendererSendResult(false);\n            Log.w(TAG, \"CR: resume animation send failed\");\n            return;\n        }\n        noteRendererSendResult(true);\n        customRendererSoftHidden = false;\n        Log.i(TAG, \"CR: resumed from soft hide\");\n    }\n\n""" + hide_marker
    text = replace_once(text, hide_marker, soft_methods, "soft hide methods")

    follow_start = "    /**\n     * Send ICON_APPROACH to c_render — mirrors BAP sendFollowStreet()."
    follow_end = "    /**\n     * Send standalone CMD_BARGRAPH to c_render on distance-only updates."
    follow_methods = """    /**\n     * Preload ICON_APPROACH while the renderer surface is still transparent.\n     */\n    private boolean preloadRendererFollowStreet() {\n        if (rendererClient == null || !customRendererPrepared || customRendererStarted) return false;\n        try {\n            boolean ok = rendererClient.sendPreloadManeuver(\n                RendererMapper.ICON_APPROACH, 0, 0, 0, null, 0, 0, 1);\n            noteRendererSendResult(ok);\n            if (ok) {\n                lastCrIcon = RendererMapper.ICON_APPROACH;\n                lastCrDirection = 0;\n                lastCrExitAngle = 0;\n                lastCrDrivingSide = 0;\n                lastCrVer = -1;\n            }\n            return ok;\n        } catch (Throwable t) {\n            Log.w(TAG, \"CR follow-street preload failed: \" + t.getMessage());\n            noteRendererSendResult(false);\n            return false;\n        }\n    }\n\n    /**\n     * Send ICON_APPROACH to c_render — mirrors BAP sendFollowStreet().\n     */\n    private boolean sendRendererFollowStreet() {\n        if (rendererClient == null || !customRendererStarted) return false;\n        int icon = RendererMapper.ICON_APPROACH;\n        if (icon == lastCrIcon && !customRendererSoftHidden) return false;\n        try {\n            boolean ok = rendererClient.sendManeuver(icon, 0, 0, 0, null, 0, 0, 1);\n            noteRendererSendResult(ok);\n            if (ok) {\n                lastCrIcon = icon;\n                lastCrDirection = 0;\n                lastCrExitAngle = 0;\n                lastCrDrivingSide = 0;\n                lastCrVer = -1;\n            }\n            return ok;\n        } catch (Throwable t) {\n            Log.w(TAG, \"CR follow street failed: \" + t.getMessage());\n            noteRendererSendResult(false);\n            return false;\n        }\n    }\n\n""" + follow_end
    text = replace_between(text, follow_start, follow_end, follow_methods, "follow street renderer methods")

    text = text.replace(
        "            customRendererPrepared = true;\n            customRendererStarted = false;\n",
        "            customRendererPrepared = true;\n            customRendererStarted = false;\n            customRendererSoftHidden = false;\n",
    )
    text = text.replace(
        "            customRendererStarted = false;\n            customRendererPrepared = true;\n",
        "            customRendererStarted = false;\n            customRendererPrepared = true;\n            customRendererSoftHidden = false;\n",
    )
    text = text.replace(
        "        customRendererPrepared = false;\n        customRendererStarted = false;\n        lastCrIcon = -1;\n",
        "        customRendererPrepared = false;\n        customRendererStarted = false;\n        customRendererSoftHidden = false;\n        lastCrIcon = -1;\n",
    )

    path.write_text(text, encoding="utf-8")


def modify_route_guidance(cfg: dict) -> None:
    path = ROOT / "java_patch/com/luka/carplay/routeguidance/RouteGuidance.java"
    text = path.read_text(encoding="utf-8")
    marker = f"R4_SOFT_INACTIVE: {cfg['slug']}"
    if marker in text:
        return
    if "R4_SOFT_INACTIVE:" in text:
        fail("RouteGuidance already contains a different R4 variant marker")

    text = replace_once(
        text,
        """    private boolean rgActive = false;\n    private boolean hasRouteUpdate = false;\n""",
        f"""    private boolean rgActive = false;\n    private boolean hasRouteUpdate = false;\n\n    /* {marker} */\n    private static final long SOFT_INACTIVE_GRACE_MS = 5000;\n    private boolean softInactivePending = false;\n    private int softInactiveGeneration = 0;\n""",
        "soft inactivity fields",
    )

    text = replace_once(
        text,
        "    public void onFrame(int type, int flags, byte[] payload, int len) {\n",
        "    public synchronized void onFrame(int type, int flags, byte[] payload, int len) {\n",
        "synchronized onFrame",
    )

    text = replace_once(
        text,
        """        running = true;\n        rgActive = false;\n        hasRouteUpdate = false;\n""",
        """        running = true;\n        cancelSoftInactive(\"start\");\n        rgActive = false;\n        hasRouteUpdate = false;\n""",
        "start timer reset",
    )

    text = replace_once(
        text,
        """        running = false;\n        rgActive = false;\n        hasRouteUpdate = false;\n""",
        """        running = false;\n        cancelSoftInactive(\"stop\");\n        rgActive = false;\n        hasRouteUpdate = false;\n""",
        "stop timer reset",
    )

    old_disconnect = """        /* Check for disconnect */\n        if (state.disconnectReason != null) {\n            if (bap != null) { bap.onStop(); bap.onShutdown(); }\n            rgActive = false;\n            hasRouteUpdate = false;\n            state.reset();\n            return;\n        }\n"""
    new_disconnect = """        /* Check for an actual transport/session disconnect. */\n        if (state.disconnectReason != null) {\n            deactivateNow(\"disconnect: \" + state.disconnectReason);\n            hasRouteUpdate = false;\n            state.reset();\n            return;\n        }\n"""
    text = replace_once(text, old_disconnect, new_disconnect, "disconnect hard stop")

    activation_start = "        /*\n         * Start/stop gating:"
    activation_end = "        if (!rgActive) {\n"
    activation_block = """        /*\n         * Start/stop gating with a 5-second soft-inactive window.\n         * Hard stop: route_state=0, source_supports_rg=0, disconnect.\n         * Soft stop: visible_in_app=0 while a route still exists, or\n         * route_state=1 with an empty maneuver list.\n         */\n        int actMask = State.DIRTY_ROUTE_STATE\n            | State.DIRTY_MANEUVER_STATE\n            | State.DIRTY_MANEUVER_COUNT\n            | State.DIRTY_MANEUVER_LIST\n            | State.DIRTY_MANEUVER_ICON\n            | State.DIRTY_VISIBLE_IN_APP\n            | State.DIRTY_SOURCE_SUPPORTS_RG;\n        boolean hasActivationDelta = (state.dirtyMask & actMask) != 0;\n\n        if (hasActivationDelta) {\n            boolean hardInactive = state.routeState == ROUTE_STATE_NO_ROUTE_SET\n                || state.sourceSupportsRg == 0;\n            boolean softInactive = !hardInactive\n                && ((state.visibleInApp == 0 && state.routeState > ROUTE_STATE_NO_ROUTE_SET)\n                    || (state.routeState == ROUTE_STATE_ROUTE_SET\n                        && state.maneuverCount == 0));\n\n            boolean hasActiveAuthority = state.visibleInApp >= 0;\n            boolean wantActive;\n            if (hasActiveAuthority) {\n                wantActive = state.visibleInApp != 0;\n            } else {\n                wantActive = state.routeState >= ROUTE_STATE_ROUTE_SET\n                    || state.maneuverCount > 0\n                    || (state.maneuverOrder != null && state.maneuverOrder.length > 0);\n            }\n            if (hardInactive || softInactive) wantActive = false;\n\n            if (hardInactive) {\n                deactivateNow(\"hard inactive route_state=\" + state.routeState\n                    + \" source_supports_rg=\" + state.sourceSupportsRg);\n            } else if (softInactive && rgActive) {\n                scheduleSoftInactive(\"route_state=\" + state.routeState\n                    + \" maneuver_count=\" + state.maneuverCount\n                    + \" visible_in_app=\" + state.visibleInApp);\n            } else if (wantActive) {\n                cancelSoftInactive(\"active update\");\n                if (!rgActive) {\n                    Log.i(TAG, \"RG activate: route_state=\" + state.routeState\n                        + \" maneuver_count=\" + state.maneuverCount\n                        + \" visible_in_app=\" + state.visibleInApp\n                        + \" source_supports_rg=\" + state.sourceSupportsRg);\n                    if (bap != null) bap.onStart();\n                    rgActive = true;\n                }\n            }\n        }\n\n"""
    text = replace_between(text, activation_start, activation_end, activation_block, "activation state machine")

    lifecycle_marker = "    /* ============================================================\n     * Parsing\n"
    helper_methods = """    private synchronized void cancelSoftInactive(String reason) {\n        if (softInactivePending) {\n            Log.d(TAG, \"Soft inactive cancelled: \" + reason);\n        }\n        softInactivePending = false;\n        ++softInactiveGeneration;\n    }\n\n    private synchronized void scheduleSoftInactive(final String reason) {\n        if (softInactivePending) return;\n        softInactivePending = true;\n        final int generation = ++softInactiveGeneration;\n        Log.i(TAG, \"Soft inactive armed for 5000ms: \" + reason);\n        Thread t = new Thread(new Runnable() {\n            public void run() {\n                try { Thread.sleep(SOFT_INACTIVE_GRACE_MS); }\n                catch (InterruptedException e) { return; }\n                synchronized (RouteGuidance.this) {\n                    if (!softInactivePending || generation != softInactiveGeneration || !rgActive) return;\n                    boolean stillSoft = state.routeState != ROUTE_STATE_NO_ROUTE_SET\n                        && state.sourceSupportsRg != 0\n                        && ((state.visibleInApp == 0)\n                            || (state.routeState == ROUTE_STATE_ROUTE_SET\n                                && state.maneuverCount == 0));\n                    if (!stillSoft) {\n                        cancelSoftInactive(\"state recovered before timeout\");\n                        return;\n                    }\n                    softInactivePending = false;\n                    Log.i(TAG, \"Soft inactive timeout: \" + reason);\n                    if (bap != null) { bap.onStop(); bap.onShutdown(); }\n                    rgActive = false;\n                }\n            }\n        }, \"RGSoftInactive\");\n        t.setDaemon(true);\n        t.start();\n    }\n\n    private synchronized void deactivateNow(String reason) {\n        cancelSoftInactive(reason);\n        if (!rgActive) return;\n        Log.i(TAG, \"RG deactivate now: \" + reason);\n        if (bap != null) { bap.onStop(); bap.onShutdown(); }\n        rgActive = false;\n    }\n\n    private static String normalizeDestination(String value) {\n        if (value == null) return null;\n        String v = value.trim();\n        if (v.length() == 0) return null;\n        if (\"未知位置\".equals(v)\n                || \"Unknown Location\".equalsIgnoreCase(v)\n                || \"Unknown destination\".equalsIgnoreCase(v)) {\n            return null;\n        }\n        return v;\n    }\n\n""" + lifecycle_marker
    text = replace_once(text, lifecycle_marker, helper_methods, "soft timer helpers")

    old_dest = """        if (d.has(\"destination\")) {\n            String v = d.str(\"destination\");\n            if (!strEq(state.destination, v)) {\n                state.destination = v;\n                state.markDirty(State.DIRTY_DESTINATION);\n            }\n        }\n"""
    new_dest = """        if (d.has(\"destination\")) {\n            String v = normalizeDestination(d.str(\"destination\"));\n            /* Invalid placeholders never clear or overwrite the last valid\n             * destination shown on the cluster. */\n            if (v != null && !strEq(state.destination, v)) {\n                state.destination = v;\n                state.markDirty(State.DIRTY_DESTINATION);\n            }\n        }\n"""
    text = replace_once(text, old_dest, new_dest, "destination filtering")

    path.write_text(text, encoding="utf-8")


def modify_build_script(cfg: dict) -> None:
    path = ROOT / "build_java.sh"
    text = path.read_text(encoding="utf-8")
    old = "BUILD_ID=\"$(date +%Y-%m-%d)-$(git -C \"$SCRIPT_DIR\" rev-parse --short HEAD 2>/dev/null || echo 'nogit')\""
    new = f"BUILD_ID=\"${{CARPLAY_BUILD_ID:-{cfg['build_id']}}}\""
    if new not in text:
        text = replace_once(text, old, new, "fixed variant Build ID")
    path.write_text(text, encoding="utf-8")


def write_docs(cfg: dict) -> None:
    doc = f"""# {cfg['name']}\n\nBranch: `{cfg['branch']}`  \nBuild ID: `{cfg['build_id']}`  \nBase: R4.1 (`main` at branch creation)\n\n> Vehicle-test candidate. Back up the original files before deployment.\n\n## Shared changes / 共同修改\n\n- City/normal route step: real maneuver appears at **350 m**.\n- Route step longer than **2 km**: real maneuver appears at **1000 m**.\n- If step length is unavailable, explicit highway/ramp maneuver types are used only as a fallback.\n- The first valid primary maneuver is shown immediately: `ICON_APPROACH` while far, real maneuver inside the threshold.\n- Renderer preparation overlaps the BAP descriptor/distance/ExitView work.\n- Retains the safe conditional context bounce: when already on context 74, switch `74 → 72 → 74`; otherwise perform a real transition into 74.\n- `visible_in_app=0` or `route_state=1 + maneuver_count=0` uses a 5-second soft-inactive grace period.\n- `route_state=0`, `source_supports_rg=0`, disconnect, or grace timeout performs full teardown and releases the stock-navigation BAP gate.\n- Invalid destinations (`未知位置`, `Unknown Location`, `Unknown destination`, blank text) do not overwrite the last valid destination.\n- Straight-arrow mapping remains unchanged from R4.1.\n\n- 普通/城市路段在 **350 m** 内显示真实转向。\n- 相邻 maneuver 路段长度超过 **2 km** 时，在 **1000 m** 内显示真实转向。\n- 路段长度缺失时，仅以明确的高速/匝道 maneuver 类型兜底。\n- 本次导航的首个有效主 maneuver 立即显示：距离较远显示 `ICON_APPROACH`，进入阈值后显示真实箭头。\n- renderer 准备过程与 BAP 描述符、距离及 ExitView 发送重叠执行。\n- 保留安全的条件式 Context bounce：当前已是 74 时执行 `74 → 72 → 74`，其他情况下保证真实切入 74。\n- `visible_in_app=0` 或 `route_state=1 且 maneuver_count=0` 进入 5 秒软失效。\n- `route_state=0`、`source_supports_rg=0`、真实断开或软失效超时执行完整清理并释放原车导航 gate。\n- 无效目的地文字不覆盖最近一次有效目的地。\n- 直行箭头映射保持 R4.1 原样。\n\n## Variant behavior / 本版本窗口策略\n\n{cfg['behavior']}\n\n{cfg['behavior_zh']}\n\n## Output / 输出\n\n- `dist/{cfg['slug']}/carplay_hook.jar`\n- GitHub Actions artifact: `{cfg['slug']}-carplay-hook`\n\nThe C hook and renderer binary are unchanged from R4.1. Deploy this JAR with the matching R4.1 `maneuver_render`, `libcarplay_hook.so`, and `flag_atlas.rgba`.\n\nC hook 与 renderer 二进制沿用 R4.1。部署时应搭配 R4.1 对应的 `maneuver_render`、`libcarplay_hook.so` 和 `flag_atlas.rgba`。\n"""
    (ROOT / "VARIANT_README.md").write_text(doc, encoding="utf-8")
    dist = ROOT / "dist" / cfg["slug"]
    dist.mkdir(parents=True, exist_ok=True)
    (dist / "README.md").write_text(doc, encoding="utf-8")

    changelog = ROOT / "CHANGELOG.md"
    if changelog.exists():
        text = changelog.read_text(encoding="utf-8")
        header = f"## {cfg['name']} (2026-08-05)"
        if header not in text:
            entry = f"""# Changelog / 更新日志\n\n{header}\n\nBuild ID: `{cfg['build_id']}`\n\n- 350 m normal threshold; 1000 m threshold when route step exceeds 2 km.\n- First primary maneuver displays ICON_APPROACH while far.\n- 5-second soft-inactive handling and invalid-destination filtering.\n- {cfg['behavior']}\n- {cfg['behavior_zh']}\n\n"""
            if text.startswith("# Changelog / 更新日志\n"):
                text = entry + text[len("# Changelog / 更新日志\n\n"):]
            else:
                text = entry + text
            changelog.write_text(text, encoding="utf-8")


def main() -> None:
    if len(sys.argv) != 2 or sys.argv[1] not in VARIANTS:
        fail("usage: apply_r4_variant.py r4.2.1|r4.2.2|r4.3")
    cfg = VARIANTS[sys.argv[1]]
    modify_bap(cfg)
    modify_route_guidance(cfg)
    modify_build_script(cfg)
    write_docs(cfg)
    print(f"Applied {cfg['name']} ({cfg['build_id']})")


if __name__ == "__main__":
    main()
