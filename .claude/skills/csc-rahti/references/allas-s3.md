# CSC Allas S3 Storage

CSC Allas is an S3-compatible object storage service.

## Connection Details

| Parameter | Value |
|-----------|-------|
| Endpoint | `https://a3s.fi` |
| Region | `regionOne` |

## Get S3 Credentials

1. Login to [CSC Pouta](https://pouta.csc.fi)
2. Go to API Access
3. Download `clouds.yaml`
4. Use OpenStack CLI to generate credentials:

```bash
# Install OpenStack client
pip install python-openstackclient

# Set cloud config
$env:OS_CLOUD = "openstack"  # PowerShell
export OS_CLOUD=openstack    # Bash

# List existing credentials
openstack ec2 credentials list

# Create new credentials (if needed)
openstack ec2 credentials create
```

## Environment Variables

```bash
ALLAS_ENDPOINT_URL=https://a3s.fi
ALLAS_ACCESS_KEY_ID=your-access-key
ALLAS_SECRET_ACCESS_KEY=your-secret-key
ALLAS_BUCKET_NAME=your-bucket-name
```

## Python (boto3)

```python
import boto3
import os

s3 = boto3.client(
    's3',
    endpoint_url=os.getenv('ALLAS_ENDPOINT_URL'),
    aws_access_key_id=os.getenv('ALLAS_ACCESS_KEY_ID'),
    aws_secret_access_key=os.getenv('ALLAS_SECRET_ACCESS_KEY'),
    region_name='regionOne'
)

# List buckets
buckets = s3.list_buckets()
for bucket in buckets['Buckets']:
    print(f"Bucket: {bucket['Name']}")

# Upload file
s3.upload_file('local_file.txt', os.getenv('ALLAS_BUCKET_NAME'), 'remote_file.txt')

# Download file
s3.download_file(os.getenv('ALLAS_BUCKET_NAME'), 'remote_file.txt', 'downloaded.txt')
```

## JavaScript (AWS SDK v3)

```typescript
import { S3Client, ListBucketsCommand, PutObjectCommand } from "@aws-sdk/client-s3"

const s3 = new S3Client({
  endpoint: process.env.ALLAS_ENDPOINT_URL,
  region: "regionOne",
  credentials: {
    accessKeyId: process.env.ALLAS_ACCESS_KEY_ID!,
    secretAccessKey: process.env.ALLAS_SECRET_ACCESS_KEY!,
  },
})

// List buckets
const { Buckets } = await s3.send(new ListBucketsCommand({}))
Buckets?.forEach(bucket => console.log(`Bucket: ${bucket.Name}`))

// Upload
await s3.send(new PutObjectCommand({
  Bucket: process.env.ALLAS_BUCKET_NAME,
  Key: "test-file.txt",
  Body: "Hello Allas!",
}))
```

## Set Credentials in Rahti

```bash
oc set env deployment/<deployment> -n <namespace> \
  ALLAS_ENDPOINT_URL=https://a3s.fi \
  ALLAS_ACCESS_KEY_ID=your-access-key \
  ALLAS_SECRET_ACCESS_KEY=your-secret-key \
  ALLAS_BUCKET_NAME=your-bucket-name
```

## Bucket Naming

CSC recommends including project ID in bucket names:
- Format: `<project-id>-<purpose>` (e.g., `2000620-raw-data`)
- Use lowercase letters, numbers, and hyphens only
- No special characters (no umlauts: a, o)
