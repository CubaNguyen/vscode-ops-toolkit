import sys, json

data = json.load(sys.stdin)
d = data[0]

print(f"Status:  {d['State']['Status']}")
print(f"Running: {d['State']['Running']}")
print(f"Started: {d['State']['StartedAt']}")
print(f"Image:   {d['Config']['Image']}")
print(f"Restart: {d['RestartCount']}")
