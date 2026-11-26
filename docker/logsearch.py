import sys, json, re

RED    = "\033[31m"
YELLOW = "\033[33m"
GREEN  = "\033[32m"
CYAN   = "\033[36m"
BOLD   = "\033[1m"
RESET  = "\033[0m"

if len(sys.argv) < 2:
    print("Usage: logsearch.py <keyword>")
    sys.exit(1)

keyword = sys.argv[1].lower()
count = 0

for line in sys.stdin:
    line = line.rstrip('\n')
    try:
        d = json.loads(line)
        t   = d.get("@t", "")[11:19]
        l   = d.get("@l", "Information") or "Information"
        m   = d.get("@m", "")
        svc = d.get("ServiceName", "")

        full = json.dumps(d).lower()
        if keyword not in full:
            continue

        label = l[:3].upper()
        color = RED if l in ("Error","Fatal") else YELLOW if l == "Warning" else GREEN

        # highlight keyword in message
        hi_msg = re.sub(f'(?i){re.escape(keyword)}', f'{BOLD}{CYAN}\\g<0>{RESET}{color}', m)
        print(f"{color}[{t}] [{label}] [{svc}] {hi_msg}{RESET}", flush=True)
        count += 1
    except:
        if keyword in line.lower():
            hi = re.sub(f'(?i){re.escape(keyword)}', f'{BOLD}{CYAN}\\g<0>{RESET}', line)
            print(hi, flush=True)
            count += 1

print(f"\n{CYAN}Found {count} matches for '{keyword}'{RESET}", flush=True)
