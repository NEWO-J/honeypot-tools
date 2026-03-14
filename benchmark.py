#!/usr/bin/env python3
"""
Honeypot recon benchmark script.
Tests whether a target SSH host will pass the bot recon check
used by common IoT/botnet malware droppers.

Usage:
    python3 benchmark.py <host> <port> <user> <password>

Example:
    python3 benchmark.py 127.0.0.1 2223 root root
"""

import sys
import time
import paramiko

RECON_SCRIPT = (
    "export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH; "
    "uname=$(uname -s -v -n -m 2>/dev/null); "
    "arch=$(uname -m 2>/dev/null); "
    "uptime=$(cat /proc/uptime 2>/dev/null | cut -d. -f1); "
    "cpus=$( (nproc 2>/dev/null || /usr/bin/nproc 2>/dev/null || grep -c '^processor' /proc/cpuinfo 2>/dev/null) | head -1); "
    "cpu_model=$(grep 'model name' /proc/cpuinfo 2>/dev/null | head -1 | awk -F': ' '{print $2}'); "
    "gpu_info=$( (lspci 2>/dev/null | grep -i vga; lspci 2>/dev/null | grep -i nvidia) | head -n50); "
    "cat_help=$( (cat --help 2>&1 | tr '\\n' ' ') ); "
    "ls_help=$( (ls --help 2>&1 | tr '\\n' ' ') ); "
    "last_output=$(last 2>/dev/null | head -n 10); "
    "echo \"UNAME:$uname\"; "
    "echo \"ARCH:$arch\"; "
    "echo \"UPTIME:$uptime\"; "
    "echo \"CPUS:$cpus\"; "
    "echo \"CPU_MODEL:$cpu_model\"; "
    "echo \"GPU:$gpu_info\"; "
    "echo \"CAT_HELP:$cat_help\"; "
    "echo \"LS_HELP:$ls_help\"; "
    "echo \"LAST:$last_output\""
)

HONEYPOT_SIGNATURES = {
    "cowrie_default_kernel":   lambda r: "3.2.0-4-amd64" in r.get("UNAME", ""),
    "cowrie_default_hostname": lambda r: "svr04" in r.get("UNAME", "") or "nas04" in r.get("UNAME", ""),
    "docker_bridge_ip":        lambda r: "172.17.0." in r.get("LAST", ""),
    "short_uptime":            lambda r: r.get("UPTIME", "").strip().isdigit() and int(r.get("UPTIME", "9999999")) < 300,
    "empty_uname":             lambda r: not r.get("UNAME", "").strip(),
    "empty_cpu":               lambda r: not r.get("CPU_MODEL", "").strip(),
    "busybox_cat":             lambda r: "BusyBox" in r.get("CAT_HELP", ""),
    "busybox_ls":              lambda r: "BusyBox" in r.get("LS_HELP", ""),
    "no_last_output":          lambda r: not r.get("LAST", "").strip(),
}

PASS_CHECKS = {
    "UNAME":     lambda v: bool(v.strip()) and "Linux" in v,
    "ARCH":      lambda v: v.strip() in ("x86_64", "aarch64", "armv7l", "i686"),
    "UPTIME":    lambda v: v.strip().isdigit() and int(v.strip()) > 300,
    "CPUS":      lambda v: v.strip().isdigit() and int(v.strip()) > 0,
    "CPU_MODEL": lambda v: bool(v.strip()),
    "CAT_HELP":  lambda v: "Usage: cat" in v and "BusyBox" not in v,
    "LS_HELP":   lambda v: "Usage: ls" in v and "BusyBox" not in v,
    "LAST":      lambda v: bool(v.strip()),
}


def parse_output(raw: str) -> dict:
    results = {}
    keys = ["UNAME", "ARCH", "UPTIME", "CPUS", "CPU_MODEL", "GPU", "CAT_HELP", "LS_HELP", "LAST"]
    for line in raw.splitlines():
        for key in keys:
            if line.startswith(f"{key}:"):
                results[key] = line[len(key)+1:].strip()
                break
    return results


def run_benchmark(host: str, port: int, user: str, password: str) -> None:
    print(f"\n{'='*60}")
    print(f"  Honeypot Recon Benchmark")
    print(f"  Target: {user}@{host}:{port}")
    print(f"{'='*60}\n")

    client = paramiko.SSHClient()
    client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
    try:
        client.connect(host, port=port, username=user, password=password, timeout=15)
    except Exception as e:
        print(f"[ERROR] Could not connect: {e}")
        sys.exit(1)

    print("[*] Connected. Running recon script...")

    try:
        # Use invoke_shell for better compatibility with proxy mode
        shell = client.invoke_shell(term="xterm", width=220, height=50)
        time.sleep(2)
        shell.recv(65535)  # clear banner/prompt

        shell.send(RECON_SCRIPT + "\n")
        time.sleep(8)  # wait for script to complete

        raw_output = ""
        while shell.recv_ready():
            raw_output += shell.recv(65535).decode("utf-8", errors="replace")
            time.sleep(0.5)

        shell.close()
    except Exception as e:
        print(f"[ERROR] Failed to run script: {e}")
        client.close()
        sys.exit(1)

    client.close()

    if not any(k in raw_output for k in ["UNAME:", "ARCH:", "UPTIME:"]):
        print("[ERROR] No recon output found in response.")
        print("[DEBUG] Raw output received:")
        print(raw_output[:500])
        sys.exit(1)

    results = parse_output(raw_output)

    # Raw results
    print(f"\n{'─'*60}")
    print("  Raw Recon Output")
    print(f"{'─'*60}")
    for key in ["UNAME", "ARCH", "UPTIME", "CPUS", "CPU_MODEL", "GPU", "CAT_HELP", "LS_HELP", "LAST"]:
        val = results.get(key, "")
        preview = val[:80].replace("\n", " ") + ("..." if len(val) > 80 else "")
        print(f"  {key:<12}: {preview}")

    # Pass/fail
    print(f"\n{'─'*60}")
    print("  Pass / Fail Checks")
    print(f"{'─'*60}")
    passed = 0
    total = len(PASS_CHECKS)
    for key, check in PASS_CHECKS.items():
        val = results.get(key, "")
        ok = check(val)
        status = "PASS" if ok else "FAIL"
        marker = "v" if ok else "x"
        if ok:
            passed += 1
        print(f"  [{marker}] {status:<6}  {key}")

    # Signatures
    print(f"\n{'─'*60}")
    print("  Honeypot Detection Signatures")
    print(f"{'─'*60}")
    detected = []
    for name, check in HONEYPOT_SIGNATURES.items():
        if check(results):
            detected.append(name)
            print(f"  [!] DETECTED: {name}")
    if not detected:
        print("  [v] No known honeypot signatures detected")

    # Verdict
    score = passed / total * 100
    print(f"\n{'='*60}")
    print(f"  Score: {passed}/{total} checks passed ({score:.0f}%)")
    if detected:
        print(f"  Signatures triggered: {len(detected)}")
        print(f"\n  VERDICT: [!] LIKELY HONEYPOT")
    elif score == 100:
        print(f"\n  VERDICT: [v] PASSES - looks like a real server")
    elif score >= 75:
        print(f"\n  VERDICT: [~] MOSTLY PASSES - some gaps")
    else:
        print(f"\n  VERDICT: [x] FAILS - likely detected as honeypot")
    print(f"{'='*60}\n")


if __name__ == "__main__":
    if len(sys.argv) != 5:
        print(f"Usage: {sys.argv[0]} <host> <port> <user> <password>")
        sys.exit(1)

    run_benchmark(sys.argv[1], int(sys.argv[2]), sys.argv[3], sys.argv[4])
