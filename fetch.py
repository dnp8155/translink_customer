import urllib.request
import json

url = "https://ydmkelswmewcyewpprtf.supabase.co/rest/v1/return_requirements?select=*"
headers = {
    "apikey": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlkbWtlbHN3bWV3Y3lld3BwcnRmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEwNTA4NzYsImV4cCI6MjEwNjYyNjg3Nn0.Qa5U6BMdtpxqspR772VCdHQ7yS4nYADZ5y3zbapGjqY",
    "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlkbWtlbHN3bWV3Y3lld3BwcnRmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEwNTA4NzYsImV4cCI6MjEwNjYyNjg3Nn0.Qa5U6BMdtpxqspR772VCdHQ7yS4nYADZ5y3zbapGjqY"
}

req = urllib.request.Request(url, headers=headers)
try:
    with urllib.request.urlopen(req) as response:
        data = json.loads(response.read().decode())
        print(json.dumps(data, indent=2))
except Exception as e:
    print("Error:", e)
