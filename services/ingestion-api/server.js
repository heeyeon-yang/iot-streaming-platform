const express = require('express');
const { KinesisClient, PutRecordCommand } = require('@aws-sdk/client-kinesis');

const app = express();
app.use(express.json());

const PORT = process.env.PORT || 3000;
const STREAM_NAME = process.env.KINESIS_STREAM_NAME || 'iot-sensor-stream';
const AWS_REGION = process.env.AWS_REGION || 'ap-northeast-2';

const kinesisClient = new KinesisClient({ region: AWS_REGION });

// Kubernetes liveness/readiness probes hit this
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

// Simulated devices POST sensor readings here
app.post('/ingest', async (req, res) => {
  const { deviceId, sensorType, value, timestamp } = req.body;

  if (!deviceId || !sensorType || value === undefined) {
    return res.status(400).json({
      error: 'deviceId, sensorType, and value are required'
    });
  }

  const record = {
    deviceId,
    sensorType,
    value,
    timestamp: timestamp || new Date().toISOString()
  };

  try {
    await kinesisClient.send(new PutRecordCommand({
      StreamName: STREAM_NAME,
      Data: Buffer.from(JSON.stringify(record)),
      PartitionKey: deviceId
    }));

    res.status(202).json({ status: 'accepted' });
  } catch (err) {
    console.error('Failed to write to Kinesis:', err.message);
    res.status(502).json({ error: 'failed to forward record' });
  }
});

app.listen(PORT, () => {
  console.log(`ingestion-api listening on port ${PORT}`);
});
