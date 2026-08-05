const express = require('express');
const { DynamoDBClient } = require('@aws-sdk/client-dynamodb');
const { DynamoDBDocumentClient, QueryCommand, ScanCommand } = require('@aws-sdk/lib-dynamodb');

const app = express();
const PORT = process.env.PORT || 3001;
const AWS_REGION = process.env.AWS_REGION || 'ap-northeast-2';
const TABLE_NAME = process.env.DYNAMODB_TABLE_NAME || 'sensor-readings';

const client = new DynamoDBClient({ region: AWS_REGION });
const docClient = DynamoDBDocumentClient.from(client);

// Kubernetes liveness/readiness probes hit this
app.get('/health', (req, res) => {
  res.status(200).json({ status: 'ok' });
});

app.get('/readings', async (req, res) => {
  const { deviceId } = req.query;

  try {
    if (deviceId) {
      const command = new QueryCommand({
        TableName: TABLE_NAME,
        KeyConditionExpression: 'device_id = :deviceId',
        ExpressionAttributeValues: { ':deviceId': deviceId },
        ScanIndexForward: false,
        Limit: 100,
      });
      const result = await docClient.send(command);
      return res.status(200).json({ count: result.Items.length, readings: result.Items });
    }

    // No deviceId filter -> scan across all devices. Fine at this data
    // volume; swap for a GSI-backed query if this becomes a hot path.
    const command = new ScanCommand({ TableName: TABLE_NAME, Limit: 100 });
    const result = await docClient.send(command);
    res.status(200).json({ count: result.Items.length, readings: result.Items });
  } catch (err) {
    console.error('Failed to read from DynamoDB:', err);
    res.status(500).json({ error: 'Failed to fetch readings' });
  }
});

app.get('/devices', async (req, res) => {
  try {
    const command = new ScanCommand({
      TableName: TABLE_NAME,
      ProjectionExpression: 'device_id',
    });
    const result = await docClient.send(command);
    const deviceIds = [...new Set(result.Items.map(item => item.device_id))];
    res.status(200).json({ devices: deviceIds });
  } catch (err) {
    console.error('Failed to read from DynamoDB:', err);
    res.status(500).json({ error: 'Failed to fetch devices' });
  }
});

app.listen(PORT, () => {
  console.log(`read-api listening on port ${PORT}`);
});
