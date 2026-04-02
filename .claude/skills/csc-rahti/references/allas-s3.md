# CSC Allas S3 Storage

CSC Allas is an S3-compatible object storage service.

## Connection Details

| Service | Endpoint | Region |
|---------|----------|--------|
| S3 API | `https://a3s.fi` | `regionOne` |
| Swift API | `https://a3s.fi:443/swift/v1/AUTH_<project-id>` | `regionOne` |

Note: Region is always `regionOne` regardless of physical location.

## Quick Option: Automated Script

The repo includes `get_s3_credentials.py` which automates credential retrieval:

```bash
pip install keystoneauth1 python-keystoneclient pyyaml
python get_s3_credentials.py
```

The script loads `clouds.yaml`, prompts for password, lists or creates credentials, and prints Access Key + Secret Key.

## Manual Credential Retrieval

### 1. Create S3 Bucket (prerequisite)

Before retrieving credentials, create your bucket:

1. Login to [Allas UI](https://allas.csc.fi/)
2. Select the correct project from the left menu
3. Click **+ Create bucket** and give it a unique name

**Bucket naming:** Use `<project-id>-<purpose>` format (e.g., `2000620-raw-data`). Lowercase, numbers, hyphens only — no umlauts or special characters.

### 2. Get clouds.yaml

1. Login to [CSC Pouta](https://pouta.csc.fi)
2. Go to **API Access**
3. Download **OpenStack clouds.yaml file**
4. Save to `~/.config/openstack/clouds.yaml`

### 3. Install OpenStack CLI

```bash
pip install python-openstackclient
```

### 4. Set Cloud Config and Verify Project

```bash
export OS_CLOUD=openstack   # Bash
$env:OS_CLOUD = "openstack" # PowerShell
```

S3 credentials are **project-specific** — verify you're in the right project:

```bash
# Check current project (auth.project_id must match bucket's project)
openstack configuration show

# List available projects
openstack project list

# Switch project if needed
openstack project set <project-name>
# e.g.: openstack project set project_2013111
```

### 5. Get Credentials

```bash
# List existing credentials
openstack ec2 credentials list

# Create new credentials (if none exist)
openstack ec2 credentials create
```

Output:
```
| Access                           | Secret                           | Project ID |
| abc123def456ghi789jkl012mno345pq | xyz789uvw456rst123qpo890lmn567abc | def456...  |
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
