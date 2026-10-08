const https = require('https');
const options = {
  hostname: 'ydmkelswmewcyewpprtf.supabase.co',
  path: '/rest/v1/truck_availability?select=*',
  method: 'GET',
  headers: {
    'apikey': 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlkbWtlbHN3bWV3Y3lld3BwcnRmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEwNTA4NzYsImV4cCI6MjEwNjYyNjg3Nn0.Qa5U6BMdtpxqspR772VCdHQ7yS4nYADZ5y3zbapGjqY',
    'Authorization': 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InlkbWtlbHN3bWV3Y3lld3BwcnRmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3OTEwNTA4NzYsImV4cCI6MjEwNjYyNjg3Nn0.Qa5U6BMdtpxqspR772VCdHQ7yS4nYADZ5y3zbapGjqY'
  }
};
const req = https.request(options, res => {
  let data = '';
  res.on('data', chunk => data += chunk);
  res.on('end', () => console.log('SUPABASE_RESULT:', data));
});
req.on('error', e => console.error(e));
req.end();
