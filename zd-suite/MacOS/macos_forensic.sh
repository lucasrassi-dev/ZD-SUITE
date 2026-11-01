#!/usr/bin/env bash
# collect_forensic_artifacts_sonoma.sh
# Usage: sudo ./macos_forensic.sh /path/to/output_dir
# Non-destructive forensic collection for macOS Sonoma (reads only).

set -euo pipefail
echo
echo "======================================"
echo "----LR's macOS Forensic Extraction----"
echo "======================================"

IFS=$'\n\t'

if [ "$EUID" -ne 0 ]; then
  echo "Please run as root: sudo $0 /path/to/output_dir"
  exit 2
fi

OUTDIR="${1:-/tmp/forensic_output}"
mkdir -p "$OUTDIR"
echo "Collecting artifacts to: $OUTDIR"
date > "$OUTDIR/collection_timestamp.txt"

# Small helper to check command exists
cmd_exists() {
  command -v "$1" >/dev/null 2>&1
}

echo -e "\n== Basic system info ==" | tee -a "$OUTDIR/README.txt"
uname -a > "$OUTDIR/uname.txt" 2>/dev/null || true
sw_vers > "$OUTDIR/sw_vers.txt" 2>/dev/null || true
system_profiler SPHardwareDataType SPSoftwareDataType > "$OUTDIR/system_profiler.txt" 2>/dev/null || true

echo -e "\n== Check for required tooling =="
REQUIRED_CMDS=(log kmutil kextstat launchctl vmmap ioreg nvram spctl csrutil security lsof netstat tcpdump sysdiagnose diskutil tar shasum)
for c in "${REQUIRED_CMDS[@]}"; do
  if cmd_exists "$c"; then
    echo "found: $c" >> "$OUTDIR/tool_check.txt"
  else
    echo "missing: $c" >> "$OUTDIR/tool_check.txt"
  fi
done

echo -e "\n== Unified logs (log collect) =="
LOGARCHIVE="$OUTDIR/logs_$(date +%Y%m%d_%H%M%S).tar.gz"
if cmd_exists log; then
  echo "Attempting: log collect --output $LOGARCHIVE"
  # log collect may require Full Disk Access; tolerate failures
  log collect --output "$LOGARCHIVE" 2>>"$OUTDIR/log_collect_errors.txt" || echo "log collect failed or partial (see log_collect_errors.txt)" >> "$OUTDIR/README.txt"
else
  echo "log command not available, skipping" >> "$OUTDIR/README.txt"
fi

echo -e "\n== DiagnosticReports (crashes) =="
mkdir -p "$OUTDIR/DiagnosticReports"
cp -a /Library/Logs/DiagnosticReports/* "$OUTDIR/DiagnosticReports/" 2>/dev/null || true
cp -a ~/Library/Logs/DiagnosticReports/* "$OUTDIR/DiagnosticReports/" 2>/dev/null || true
ls -la "$OUTDIR/DiagnosticReports" > "$OUTDIR/diagnosticreports_listing.txt" 2>/dev/null || true

echo -e "\n== Kernel & kext information =="
if cmd_exists kmutil; then
  kmutil showloaded > "$OUTDIR/kmutil_showloaded.txt" 2>&1 || true
fi
if cmd_exists kextstat; then
  kextstat > "$OUTDIR/kextstat.txt" 2>&1 || true
fi

# Kernelcache directories (Sonoma may vary slightly)
mkdir -p "$OUTDIR/kernelcache"
KERNELCACHEDIRS=(
  "/System/Library/Caches/com.apple.kext.caches/Startup/"
  "/System/Library/Caches/com.apple.kext.caches/KernelCollections/"
  "/System/Library/Caches/com.apple.kernelcaches/"
)
for d in "${KERNELCACHEDIRS[@]}"; do
  if [ -d "$d" ]; then
    echo "Inspecting kernelcache dir: $d" >> "$OUTDIR/kernelcache/inspected_dirs.txt"
    ls -la "$d" > "$OUTDIR/kernelcache/dir_$(basename "$d").txt" 2>/dev/null || true
    for f in "$d"*; do
      if [ -f "$f" ]; then
        shasum -a 256 "$f" >> "$OUTDIR/kernelcache/kernelcache_shasums.txt" 2>/dev/null || true
        cp -a "$f" "$OUTDIR/kernelcache/" 2>/dev/null || true
      fi
    done
  fi
done

echo -e "\n== Launch agents & daemons =="
ls -la /Library/LaunchAgents/ > "$OUTDIR/launch_LA.txt" 2>/dev/null || true
ls -la /Library/LaunchDaemons/ > "$OUTDIR/launch_LD.txt" 2>/dev/null || true
ls -la /System/Library/LaunchAgents/ > "$OUTDIR/launch_sys_LA.txt" 2>/dev/null || true
ls -la /System/Library/LaunchDaemons/ > "$OUTDIR/launch_sys_LD.txt" 2>/dev/null || true
ls -la ~/Library/LaunchAgents/ > "$OUTDIR/launch_user_LA.txt" 2>/dev/null || true
# launchctl print for GUI session if SUDO_UID present
if [ -n "${SUDO_UID:-}" ]; then
  launchctl print gui/"$SUDO_UID" > "$OUTDIR/launchctl_gui_$(id -u).txt" 2>/dev/null || true
fi
launchctl list > "$OUTDIR/launchctl_list.txt" 2>/dev/null || true

echo -e "\n== Running processes and vmmap samples =="
ps -Ao pid,ppid,user,%cpu,%mem,rss,vsz,etime,command > "$OUTDIR/ps_full.txt" 2>/dev/null || true

echo "Top 20 by CPU" > "$OUTDIR/ps_top_cpu.txt"
ps -Ao pid,ppid,user,%cpu,%mem,rss,vsz,etime,command | sort -rn -k4 | head -n 20 >> "$OUTDIR/ps_top_cpu.txt" 2>/dev/null || true

echo "Top 20 by RSS" > "$OUTDIR/ps_top_rss.txt"
ps -Ao pid,ppid,user,%cpu,%mem,rss,vsz,etime,command | sort -rn -k6 | head -n 20 >> "$OUTDIR/ps_top_rss.txt" 2>/dev/null || true

mkdir -p "$OUTDIR/vmmap"
# Extract PIDs from ps_top_cpu.txt (skip header line)
awk 'NR>1{print $1}' "$OUTDIR/ps_top_cpu.txt" | head -n 10 | while read -r pid; do
  if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
    echo "Collecting vmmap for PID $pid"
    vmmap "$pid" > "$OUTDIR/vmmap/vmmap_${pid}.txt" 2>/dev/null || echo "vmmap failed for $pid" >> "$OUTDIR/vmmap/vmmap_errors.txt"
  fi
done

echo -e "\n== I/O Kit & device tree (IORegistry) =="
ioreg -lw0 > "$OUTDIR/ioreg_lw0.txt" 2>/dev/null || true
ioreg -p IODeviceTree -l > "$OUTDIR/ioreg_devicetree.txt" 2>/dev/null || true

echo -e "\n== NVRAM and firmware-related info =="
nvram -p > "$OUTDIR/nvram.txt" 2>/dev/null || true
system_profiler SPHardwareDataType > "$OUTDIR/hardware_profile.txt" 2>/dev/null || true

echo -e "\n== Security state & code signing =="
spctl --status > "$OUTDIR/spctl_status.txt" 2>/dev/null || true
# csrutil usually only runs in Recovery; capture output (graceful failure)
if cmd_exists csrutil; then
  csrutil status > "$OUTDIR/csrutil_status.txt" 2>/dev/null || echo "csrutil status not available outside Recovery" > "$OUTDIR/csrutil_status.txt"
fi

echo -e "\n== Keychain & certificates (list) =="
if cmd_exists security; then
  security find-certificate -a -p > "$OUTDIR/all_system_certificates.pem" 2>/dev/null || true
  security list-keychains > "$OUTDIR/security_list_keychains.txt" 2>/dev/null || true
fi

echo -e "\n== Networking: connections & routes =="
netstat -an > "$OUTDIR/netstat_an.txt" 2>/dev/null || true
lsof -i -n -P > "$OUTDIR/lsof_i.txt" 2>/dev/null || true
route -n get default > "$OUTDIR/route_default.txt" 2>/dev/null || true

# TCPDUMP capture (60s) using background + sleep + kill (safer cross-platform)
PCAPFILE="$OUTDIR/tcpdump_sample.pcap"
if cmd_exists tcpdump; then
  echo "Starting a 60-second tcpdump capture to $PCAPFILE (may require permission prompts)..."
  tcpdump -i any -w "$PCAPFILE" 2>"$OUTDIR/tcpdump_error.txt" &
  TCPDUMP_PID=$!
  sleep 60
  kill -2 "$TCPDUMP_PID" 2>/dev/null || true
  sleep 1
else
  echo "tcpdump not found; skipping pcap capture" >> "$OUTDIR/README.txt"
fi

echo -e "\n== Sysdiagnose (comprehensive Apple diagnostic) =="
SYSDIAG_DIR="$OUTDIR/sysdiagnose"
mkdir -p "$SYSDIAG_DIR"
if cmd_exists sysdiagnose; then
  # sysdiagnose may be interactive / take time
  sysdiagnose -f "$SYSDIAG_DIR" -q 2> "$OUTDIR/sysdiagnose_err.txt" || echo "sysdiagnose may have required interaction; check sysdiagnose_err.txt"
else
  echo "sysdiagnose not available, skipping" >> "$OUTDIR/README.txt"
fi

echo -e "\n== Copy relevant logs from /var/log =="
mkdir -p "$OUTDIR/varlog"
cp -a /var/log/system.log* "$OUTDIR/varlog/" 2>/dev/null || true
cp -a /var/log/diagnosticd.log* "$OUTDIR/varlog/" 2>/dev/null || true
cp -a /var/log/kernel* "$OUTDIR/varlog/" 2>/dev/null || true
ls -la "$OUTDIR/varlog" > "$OUTDIR/varlog_listing.txt" 2>/dev/null || true

echo -e "\n== APFS snapshots and volume info =="
diskutil list > "$OUTDIR/diskutil_list.txt" 2>/dev/null || true
# Attempt snapshot listing for root (may require different container ID)
diskutil apfs listSnapshots / > "$OUTDIR/apfs_snapshots_root.txt" 2>/dev/null || true

echo -e "\n== Optional: compute hashes for system binaries (may be large) =="
BINHASH_DIR="$OUTDIR/system_hashes"
mkdir -p "$BINHASH_DIR"
SYSTEM_BIN_DIRS=(
  "/System/Library"
  "/usr/lib"
)
for d in "${SYSTEM_BIN_DIRS[@]}"; do
  if [ -d "$d" ]; then
    find "$d" -type f -perm +111 -print0 2>/dev/null | xargs -0 -n1 sh -c 'f="$0"; shasum -a 256 "$f" 2>/dev/null || true' > "$BINHASH_DIR/hashes_$(basename "$d").txt" 2>/dev/null || true
  fi
done

echo -e "\n== Packaging results =="
# create final tarball; name includes timestamp
FINAL_TAR="${OUTDIR}_$(date +%Y%m%d_%H%M%S).tar.gz"
tar -czf "$FINAL_TAR" -C "$(dirname "$OUTDIR")" "$(basename "$OUTDIR")" 2>/dev/null || true
echo "Packaged archive: $FINAL_TAR" > "$OUTDIR/final_package_path.txt"

echo -e "\n== Done =="
echo "Collected artifacts are in: $OUTDIR"
echo "Packaged archive: $FINAL_TAR"
echo "Please copy the archive to a secure analysis host and analyze offline."
