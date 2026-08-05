#!/usr/bin/env python3
from pathlib import Path
import hashlib
import os
import shutil
import struct
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[1]
VARIANTS = {
    "r4.2.1": "2026-08-05-r4.2.1-soft-hide",
    "r4.2.2": "2026-08-05-r4.2.2-context72",
    "r4.3": "2026-08-05-r4.3-always-on-handoff-fix",
}

STUBS = {
"de/audi/atip/base/IFrameworkAccess.java": r'''package de.audi.atip.base;
public interface IFrameworkAccess {
    long getUTCTime();
    long convertUTCTimeToLocalTime(long value);
    int getKombiType();
    int getSysConst(int id);
}
''',
"de/audi/atip/log/LogChannel.java": r'''package de.audi.atip.log;
public class LogChannel {
    public LogChannel() {}
    public void log(int level, String pattern, Object a, Object b, Object c, Object d,
                    long l1, long l2, long l3, int flags, Throwable t) {}
    public void log(int level, int messageId, Object a, Object b, Object c, Object d,
                    long l1, long l2, long l3, int flags, Throwable t) {}
}
''',
"de/audi/atip/metrics/DateMetric.java": r'''package de.audi.atip.metrics;
public class DateMetric { public static int timeFormat = 10; }
''',
"de/audi/atip/metrics/Distance.java": r'''package de.audi.atip.metrics;
public class Distance {
    public static final int NONE = 0;
    public static final int METERS = 1;
    public static final int KM = 2;
    public static int getSystemUnit() { return KM; }
}
''',
"de/audi/atip/interapp/combi/bap/navi/CombiBAPServiceNavi.java": r'''package de.audi.atip.interapp.combi.bap.navi;
import de.audi.atip.interapp.combi.bap.navi.data.*;
public interface CombiBAPServiceNavi {
    void updateRGStatus(int v);
    void updateActiveRGType(int v);
    void updateDistanceToNextManeuver(int value, int unit, boolean barOn, int bar);
    void updateCurrentPositionInfo(String value);
    void updateManeuverDescriptor(CombiBAPNaviManeuverDescriptor[] value);
    void updateLaneGuidance(boolean active, CombiBAPNaviLaneGuidanceData[] value);
    void updateExitView(int variant, int number);
    void updateManeuverState(int value);
    void updateDistanceToDestination(int value, int unit, boolean stopover);
    void updateTimeToDestination(int infoType, int format, long value);
    void updateDestinationInfo(CombiBAPDestinationInfo value);
}
''',
"de/audi/atip/interapp/combi/bap/navi/data/CombiBAPNaviManeuverDescriptor.java": r'''package de.audi.atip.interapp.combi.bap.navi.data;
public class CombiBAPNaviManeuverDescriptor {
    public CombiBAPNaviManeuverDescriptor(int main, int dir, int z, byte[] sides) {}
}
''',
"de/audi/atip/interapp/combi/bap/navi/data/CombiBAPNaviLaneGuidanceData.java": r'''package de.audi.atip.interapp.combi.bap.navi.data;
public class CombiBAPNaviLaneGuidanceData {
    public CombiBAPNaviLaneGuidanceData(short pos, short dir, byte[] sides, short reserved,
        byte a, byte b, byte c, byte info) {}
}
''',
"de/audi/atip/interapp/combi/bap/navi/data/CombiBAPNaviDestination.java": r'''package de.audi.atip.interapp.combi.bap.navi.data;
public class CombiBAPNaviDestination {
    public CombiBAPNaviDestination(String a, String b, String c, String d,
        String e, String f, String g) {}
}
''',
"de/audi/atip/interapp/combi/bap/navi/data/CombiBAPDestinationInfo.java": r'''package de.audi.atip.interapp.combi.bap.navi.data;
public class CombiBAPDestinationInfo {
    public CombiBAPDestinationInfo(CombiBAPNaviDestination d) {}
}
''',
"de/audi/tghu/navi/app/command/DSIResponseContainer.java": r'''package de.audi.tghu.navi.app.command;
public class DSIResponseContainer { public void setRgActive(boolean active) {} }
''',
"de/audi/tghu/navi/app/cluster/KOMOService.java": r'''package de.audi.tghu.navi.app.cluster;
public class KOMOService {}
''',
"de/audi/tghu/navi/app/cluster/BAPDistanceFormatter.java": r'''package de.audi.tghu.navi.app.cluster;
import de.audi.atip.log.LogChannel;
public class BAPDistanceFormatter {
    public static class BAPDistance {
        public int getValue() { return 0; }
        public int getUnit() { return 0; }
    }
    public BAPDistanceFormatter(LogChannel log) {}
    public BAPDistance formatDistanceToTurn(int meters, boolean metric) { return new BAPDistance(); }
    public BAPDistance formatDistanceToDestination(int meters, boolean metric) { return new BAPDistance(); }
}
''',
"de/audi/tghu/navi/app/cluster/ClusterService.java": r'''package de.audi.tghu.navi.app.cluster;
import de.audi.atip.interapp.combi.bap.navi.CombiBAPServiceNavi;
import de.audi.tghu.navi.app.command.DSIResponseContainer;
public class ClusterService {
    public KOMOService getKomoService() { return null; }
    public CombiBAPServiceNavi getCombiBAPListenerCombiService() { return null; }
    public void setCombiBAPListenerCombiService(CombiBAPServiceNavi s) {}
    public void setRouteGuidanceAborted() {}
    public DSIResponseContainer getDSIResponseContainer() { return null; }
    public void updateRGIString(short[] value) {}
    public void triggerRefreshRGIValid() {}
    public void deactivateCustomRendererPipeline() {}
    public String activateCustomRendererPipeline() { return "OK"; }
}
''',
"de/audi/tghu/navi/app/routeguidance/IRouteManager.java": r'''package de.audi.tghu.navi.app.routeguidance;
import org.dsi.ifc.navigation.Route;
public interface IRouteManager {
    Route getRoute();
    void stopRouteGuidance();
}
''',
"de/audi/tghu/navi/app/Navigation.java": r'''package de.audi.tghu.navi.app;
import de.audi.tghu.navi.app.cluster.ClusterService;
import de.audi.tghu.navi.app.routeguidance.IRouteManager;
public class Navigation {
    public static Navigation getInstance() { return null; }
    public ClusterService getClusterService() { return null; }
    public IRouteManager getRouteManager() { return null; }
}
''',
"org/dsi/ifc/navigation/Route.java": r'''package org.dsi.ifc.navigation;
public class Route {}
''',
"de/audi/atip/util/CommandLineExecuter.java": r'''package de.audi.atip.util;
public class CommandLineExecuter {
    public static void executeCommand(String command, String[] args) {}
}
''',
}


def run(cmd, **kwargs):
    print("+", " ".join(str(x) for x in cmd))
    subprocess.run(cmd, check=True, **kwargs)


def write_stubs(root: Path) -> None:
    for rel, content in STUBS.items():
        p = root / rel
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(content, encoding="utf-8")


def patch_class_utf8(data: bytes, new_build_id: str) -> bytes:
    if data[:4] != b"\xca\xfe\xba\xbe":
        raise RuntimeError("not a class file")
    cp_count = struct.unpack(">H", data[8:10])[0]
    pos = 10
    out = bytearray(data[:10])
    i = 1
    changed = False
    while i < cp_count:
        tag = data[pos]
        out.append(tag)
        pos += 1
        if tag == 1:
            length = struct.unpack(">H", data[pos:pos+2])[0]
            raw = data[pos+2:pos+2+length]
            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError:
                text = ""
            if text.startswith("Build: 2026-") and "r4" in text.lower():
                raw = ("Build: " + new_build_id).encode("utf-8")
                changed = True
            elif text.startswith("2026-") and "r4" in text.lower():
                raw = new_build_id.encode("utf-8")
                changed = True
            out += struct.pack(">H", len(raw)) + raw
            pos += 2 + length
        elif tag in (3, 4):
            out += data[pos:pos+4]; pos += 4
        elif tag in (5, 6):
            out += data[pos:pos+8]; pos += 8; i += 1
        elif tag in (7, 8, 16, 19, 20):
            out += data[pos:pos+2]; pos += 2
        elif tag in (9, 10, 11, 12, 17, 18):
            out += data[pos:pos+4]; pos += 4
        elif tag == 15:
            out += data[pos:pos+3]; pos += 3
        else:
            raise RuntimeError("unsupported constant-pool tag %d" % tag)
        i += 1
    out += data[pos:]
    if not changed:
        raise RuntimeError("Build ID UTF8 constant not found in CarPlayHook.class")
    return bytes(out)


def class_major(data: bytes) -> int:
    return struct.unpack(">H", data[6:8])[0]


def main() -> None:
    if len(sys.argv) != 2 or sys.argv[1] not in VARIANTS:
        raise SystemExit("usage: build_r4_variant.py r4.2.1|r4.2.2|r4.3")
    variant = sys.argv[1]
    build_id = VARIANTS[variant]
    base_jar = ROOT / "dist/r4.1/carplay_hook.jar"
    if not base_jar.exists():
        raise RuntimeError("missing base JAR: %s" % base_jar)

    work = ROOT / "build" / variant
    if work.exists():
        shutil.rmtree(work)
    stub_src = work / "stubs-src"
    stub_cls = work / "stubs-classes"
    out_cls = work / "classes"
    stub_cls.mkdir(parents=True)
    out_cls.mkdir(parents=True)
    write_stubs(stub_src)

    javac = os.environ.get("JAVAC", "javac")
    stub_files = [str(p) for p in sorted(stub_src.rglob("*.java"))]
    run([javac, "-encoding", "UTF-8", "-source", "1.2", "-target", "1.2",
         "-d", str(stub_cls)] + stub_files)

    sources = [
        ROOT / "java_patch/com/luka/carplay/routeguidance/BAPBridge.java",
        ROOT / "java_patch/com/luka/carplay/routeguidance/RouteGuidance.java",
    ]
    cp = str(stub_cls) + os.pathsep + str(base_jar)
    run([javac, "-encoding", "UTF-8", "-source", "1.2", "-target", "1.2",
         "-cp", cp, "-sourcepath", str(work / "empty-sourcepath"),
         "-d", str(out_cls)] + [str(p) for p in sources])

    compiled = sorted((out_cls / "com/luka/carplay/routeguidance").glob("*.class"))
    wanted = [p for p in compiled if p.name.startswith("BAPBridge") or p.name.startswith("RouteGuidance")]
    if not wanted:
        raise RuntimeError("no replacement classes compiled")
    for p in wanted:
        major = class_major(p.read_bytes())
        if major != 46:
            raise RuntimeError("%s has class major %d, expected 46" % (p.name, major))

    dist = ROOT / "dist" / variant
    dist.mkdir(parents=True, exist_ok=True)
    out_jar = dist / "carplay_hook.jar"
    temp_jar = work / "carplay_hook.jar"

    with zipfile.ZipFile(base_jar, "r") as zin, zipfile.ZipFile(temp_jar, "w", zipfile.ZIP_DEFLATED) as zout:
        for info in zin.infolist():
            name = info.filename
            if name.startswith("com/luka/carplay/routeguidance/BAPBridge") and name.endswith(".class"):
                continue
            if name.startswith("com/luka/carplay/routeguidance/RouteGuidance") and name.endswith(".class"):
                continue
            data = zin.read(name)
            if name == "com/luka/carplay/CarPlayHook.class":
                data = patch_class_utf8(data, build_id)
            zout.writestr(info, data)
        for p in wanted:
            arc = "com/luka/carplay/routeguidance/" + p.name
            zout.write(p, arc)

    shutil.copy2(temp_jar, out_jar)
    digest = hashlib.sha256(out_jar.read_bytes()).hexdigest()
    (dist / "SHA256SUMS").write_text(digest + "  carplay_hook.jar\n", encoding="utf-8")

    with zipfile.ZipFile(out_jar, "r") as z:
        hook = z.read("com/luka/carplay/CarPlayHook.class")
        if build_id.encode("utf-8") not in hook:
            raise RuntimeError("Build ID constant verification failed")
        if ("Build: " + build_id).encode("utf-8") not in hook:
            raise RuntimeError("Build ID log-string verification failed")
        for required in (
            "com/luka/carplay/routeguidance/BAPBridge.class",
            "com/luka/carplay/routeguidance/RouteGuidance.class",
        ):
            if required not in z.namelist():
                raise RuntimeError("missing %s" % required)
            if class_major(z.read(required)) != 46:
                raise RuntimeError("wrong class version for %s" % required)

    print("Built", out_jar)
    print("Build ID:", build_id)
    print("SHA-256:", digest)
    print("Replacement classes:")
    for p in wanted:
        print(" -", p.name)


if __name__ == "__main__":
    main()
