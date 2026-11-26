import sys, json, re, zlib

ONLY_ERRORS = "--only-errors" in sys.argv

RED    = "\033[31m"
YELLOW = "\033[33m"
GREEN  = "\033[32m"
CYAN   = "\033[36m"
GRAY   = "\033[90m"
BLUE   = "\033[34m"
BOLD   = "\033[1m"
RESET  = "\033[0m"

LEVEL_COLORS = {
    "Error":       RED,
    "Fatal":       RED,
    "Warning":     YELLOW,
    "Information": GREEN,
    "Debug":       CYAN,
    "Verbose":     GRAY,
}

# ── Highlight ID (chỉ dùng cho JSON log) ──────────────────────────
# bảng màu 256-color sáng, dễ đọc trên nền tối, tránh xanh lá/đỏ trùng màu level
ID_PALETTE = [
    # vàng / cam
    226, 220, 214, 208, 228, 222, 216, 179,
    # hồng / magenta
    199, 201, 205, 207, 211, 213, 218, 219,
    # tím
    129, 135, 141, 165, 171, 177, 99,  105,
    # xanh dương
    27,  33,  39,  63,  69,  75,  111, 117,
    # cyan / ngọc
    44,  45,  51,  80,  87,  123, 159, 122,
    # vàng chanh / be / pastel
    190, 191, 192, 186, 187, 209, 215, 217,
    223, 225, 229, 195, 189, 183, 147, 153,
]
ID_RE = re.compile(
    r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b'  # UUID
    r'|\b[0-9a-fA-F]{24}\b'                                                              # ObjectId
)

def id_color(id_str):
    # crc32 ổn định giữa các lần chạy: cùng ID luôn ra cùng màu
    c = ID_PALETTE[zlib.crc32(id_str.lower().encode()) % len(ID_PALETTE)]
    return f"\033[1;38;5;{c}m"

def hl_ids(text, base):
    # sau mỗi ID trả lại màu level để phần còn lại của dòng không mất màu
    return ID_RE.sub(lambda mt: f"{id_color(mt.group())}{mt.group()}{RESET}{base}", text)

# ── JSON log (Serilog) ────────────────────────────────────────────
def format_json_log(line):
    d = json.loads(line)
    t   = d.get("@t", "")[11:19]
    l   = d.get("@l", "Information") or "Information"
    m   = d.get("@m", "")
    svc = d.get("ServiceName", "")
    ex  = d.get("@x", "")
    color = LEVEL_COLORS.get(l, GREEN)
    label = l[:3].upper()
    svc_part = f"[{svc}] " if svc else ""
    m = hl_ids(str(m), color)
    out = f"{color}[{t}] [{label}] {svc_part}{m}{RESET}"
    if ex:
        out += f"\n{RED}{ex}{RESET}"
    return out

# ── Nginx error log ───────────────────────────────────────────────
def format_nginx_error(line):
    m = re.match(r'(\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2}) \[(\w+)\] (.+)', line)
    if m:
        t, level, msg = m.groups()
        t = t[11:]
        if level == "error":   return f"{RED}[{t}] [ERR] {msg}{RESET}"
        elif level == "warn":  return f"{YELLOW}[{t}] [WRN] {msg}{RESET}"
        elif level == "crit":  return f"{RED}{BOLD}[{t}] [CRT] {msg}{RESET}"
        else:                  return f"{GREEN}[{t}] [INF] {msg}{RESET}"
    return line

# ── Nginx access log ──────────────────────────────────────────────
def format_nginx_access(line):
    # format: IP - - [date] "METHOD /path HTTP" STATUS size "ref" "ua"
    m = re.match(r'(\S+) \S+ \S+ \[([^\]]+)\] "(\S+) (\S+)[^"]*" (\d{3}) (\d+)', line)
    if m:
        ip, date, method, path, status, size = m.groups()
        status = int(status)
        time = date[12:20] if len(date) > 12 else date
        if status >= 500:   color = RED
        elif status >= 400: color = YELLOW
        elif status >= 300: color = CYAN
        else:               color = GREEN
        return f"{color}[{time}] {status} {method} {path} ({size}b) ← {ip}{RESET}"
    return line

# ── Docker stats ──────────────────────────────────────────────────
def format_stats(line):
    if "CONTAINER" in line or "NAME" in line:
        return f"{BOLD}{CYAN}{line}{RESET}"
    parts = line.split()
    for part in parts:
        if part.endswith('%'):
            try:
                cpu_val = float(part.replace('%',''))
                if cpu_val > 50:   return f"{RED}{line}{RESET}"
                elif cpu_val > 20: return f"{YELLOW}{line}{RESET}"
                else:              return f"{GREEN}{line}{RESET}"
            except: pass
    return line

# ── Disk usage (df -h) ────────────────────────────────────────────
def format_disk(line):
    if line.startswith("Filesystem"):
        return f"{BOLD}{CYAN}{line}{RESET}"
    m = re.search(r'(\d+)%', line)
    if m:
        pct = int(m.group(1))
        if pct >= 85:   return f"{RED}{line}{RESET}"
        elif pct >= 70: return f"{YELLOW}{line}{RESET}"
        else:           return f"{GREEN}{line}{RESET}"
    return f"{GRAY}{line}{RESET}"

# ── ps aux (process list) ─────────────────────────────────────────
def format_ps(line):
    if line.startswith("USER"):
        return f"{BOLD}{CYAN}{line}{RESET}"
    parts = line.split(None, 10)   # tach toi da 11 phan, giu nguyen COMMAND
    if len(parts) < 11:
        return f"{GRAY}{line}{RESET}"
    try:
        cpu = float(parts[2])
        mem = float(parts[3])
    except:
        return f"{GRAY}{line}{RESET}"

    # Mau cho CPU
    if cpu > 50:        cpu_color = RED
    elif cpu > 20:      cpu_color = YELLOW
    elif cpu > 5:       cpu_color = GREEN
    else:               cpu_color = GRAY

    # Mau cho MEM
    if mem > 20:        mem_color = RED
    elif mem > 10:      mem_color = YELLOW
    elif mem > 2:       mem_color = GREEN
    else:               mem_color = GRAY

    # Rut gon COMMAND cho de doc
    cmd = parts[10]
    if "dotnet" in cmd:
        # lay ten file .dll cuoi cung
        dll = [p for p in cmd.split() if p.endswith(".dll")]
        cmd = "dotnet " + dll[-1].split("/")[-1] if dll else "dotnet ..."
    elif "java" in cmd:
        # lay ten class/jar cuoi co nghia
        java_parts = cmd.split()
        name = next((p for p in reversed(java_parts) if not p.startswith("-") and "/" not in p), "java")
        cmd = "java [" + name + "]"
    elif "node" in cmd:
        node_parts = cmd.split()
        name = next((p for p in node_parts if p.endswith(".js") or ("node" not in p and not p.startswith("-"))), "node")
        cmd = "node " + name.split("/")[-1]
    elif "python" in cmd:
        cmd = "python " + cmd.split()[-1].split("/")[-1]

    # Cắt ngắn nếu vẫn còn dài
    if len(cmd) > 60:
        cmd = cmd[:57] + "..."

    if cmd.startswith("["):             cmd_color = GRAY    # kernel thread
    elif any(x in cmd for x in ["dotnet", "java", "python", "node"]):
                                        cmd_color = CYAN
    else:                               cmd_color = RESET

    # parts: USER PID CPU MEM VSZ RSS TTY STAT START TIME COMMAND
    stat  = parts[7]
    start = parts[8]
    time  = parts[9]

    user  = f"{GRAY}{parts[0]:<8}{RESET}"
    pid   = f"{GRAY}{parts[1]:>7}{RESET}"
    cpu_s = f"{cpu_color}{parts[2]:>5}{RESET}"
    mem_s = f"{mem_color}{parts[3]:>5}{RESET}"
    meta  = f"{GRAY}{stat:<4} {start:>6} {time:>8}{RESET}"
    cmd_s = f"{cmd_color}{cmd:<45}{RESET}"

    return f"{user} {pid} {cpu_s} {mem_s}  {meta}  {cmd_s}"

# ── ss / netstat (ports) ──────────────────────────────────────────
def format_ports(line):
    if "LISTEN" in line:   return f"{GREEN}{line}{RESET}"
    if "ESTAB" in line:    return f"{CYAN}{line}{RESET}"
    if "TIME-WAIT" in line: return f"{GRAY}{line}{RESET}"
    if line.startswith("State") or line.startswith("Netid"):
        return f"{BOLD}{CYAN}{line}{RESET}"
    return line

# ── auth log ──────────────────────────────────────────────────────
def format_auth(line):
    if "Failed" in line or "Invalid" in line or "BREAK" in line:
        return f"{RED}{line}{RESET}"
    elif "Accepted" in line or "session opened" in line:
        return f"{GREEN}{line}{RESET}"
    return f"{GRAY}{line}{RESET}"

# ── syslog ────────────────────────────────────────────────────────
def format_syslog(line):
    if re.search(r'error|fail|crit', line, re.IGNORECASE):
        return f"{RED}{line}{RESET}"
    elif re.search(r'warn', line, re.IGNORECASE):
        return f"{YELLOW}{line}{RESET}"
    return f"{GRAY}{line}{RESET}"

# ── Linux system overview (uptime/free/loadavg) ───────────────────
def format_system(line):
    if line.startswith("==="):
        return f"{BOLD}{CYAN}{line}{RESET}"
    if "Mem:" in line or "Swap:" in line:
        return f"{GREEN}{line}{RESET}"
    return line

# ── Router ────────────────────────────────────────────────────────
for line in sys.stdin:
    line = line.rstrip('\n')

    # JSON log
    try:
        print(format_json_log(line), flush=True); continue
    except: pass

    # Nginx error log
    if re.match(r'\d{4}/\d{2}/\d{2} \d{2}:\d{2}:\d{2} \[', line):
        print(format_nginx_error(line), flush=True); continue

    # Nginx access log
    if re.match(r'\d+\.\d+\.\d+\.\d+ .+ \[.+\] "', line):
        m = re.search(r'" (\d{3}) ', line)
        if ONLY_ERRORS and m and not m.group(1).startswith(('4','5')):
            continue
        print(format_nginx_access(line), flush=True); continue

    # Docker stats
    if re.search(r'\d+\.\d+%', line) or "CONTAINER" in line or "NAME" in line:
        print(format_stats(line), flush=True); continue

    # Disk usage
    if re.search(r'\d+%\s+/', line) or line.startswith("Filesystem"):
        print(format_disk(line), flush=True); continue

    # ps aux
    if re.match(r'\w+\s+\d+\s+[\d.]+\s+[\d.]+', line) or line.startswith("USER"):
        print(format_ps(line), flush=True); continue

    # ss/netstat ports
    if re.search(r'LISTEN|ESTAB|TIME-WAIT', line) or line.startswith("State") or line.startswith("Netid"):
        print(format_ports(line), flush=True); continue

    # auth log
    if re.search(r'Failed password|Accepted|Invalid user|BREAK-IN', line):
        print(format_auth(line), flush=True); continue

    # syslog
    if re.match(r'\w+ \d+ \d{2}:\d{2}:\d{2}', line):
        print(format_syslog(line), flush=True); continue

    # system overview headers
    if line.startswith("===") or "Mem:" in line or "Swap:" in line:
        print(format_system(line), flush=True); continue

    print(line, flush=True)
