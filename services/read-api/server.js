const express = require('express');

const app = express();
const PORT = process.env.PORT || 3001;

// Kubernetes liveness/readiness probes hit this
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

// Placeholder data until a real data store (DynamoDB or RDS) is wired in.
// This lets the dashboard frontend start development against a stable shape
// before the storage decision is made.
const MOCK_READINGS = [
  { deviceId: 'sensor-001', sensorType: 'temperature', value: 23.4, timestamp: '2026-08-02T09:00:00Z' },
  { deviceId: 'sensor-002', sensorType: 'humidity', value: 55.1, timestamp: '2026-08-02T09:00:00Z' },
  { deviceId: 'sensor-001', sensorType: 'temperature', value: 23.6, timestamp: '2026-08-02T09:01:00Z' }
];

app.get('/readings', (req, res) => {
  const { deviceId } = req.query;

  const results = deviceId
    ? MOCK_READINGS.filter(r => r.deviceId === deviceId)
    : MOCK_READINGS;

  res.status(200).json({ count: results.length, readings: results });
});

app.get('/devices', (req, res) => {
  const deviceIds = [...new Set(MOCK_READINGS.map(r => r.deviceId))];
  res.status(200).json({ devices: deviceIds });
});

app.listen(PORT, () => {
  console.log(`read-api listening on port ${PORT}`);
});
