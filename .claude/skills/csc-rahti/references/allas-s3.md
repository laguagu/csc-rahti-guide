# CSC Allas S3 Storage

## Contents
- [Connection Details](#connection-details)
- [Client configuration (critical)](#client-configuration-critical)
- [Credential Retrieval](#credential-retrieval)
- [Environment Variables](#environment-variables)
- [Python (boto3)](#python-boto3)
- [JavaScript (AWS SDK v3)](#javascript-aws-sdk-v3)
- [Presigned URLs](#presigned-urls)
- [Injecting credentials into a Rahti pod](#injecting-credentials-into-a-rahti-pod)
- [Dockerfile ARG placeholders (Next.js specific)](#dockerfile-arg-placeholders-nextjs-specific)

CSC Allas is an S3-compatible object storage service.

## Connection Details

| Service | Endpoint | Region |
|---------|----------|--------|
| S3 API | `https://a3s.fi` | `regionOne` |
| Swift API | `https://a3s.fi:443/swift/v1/AUTH_<project-id>` | `regionOne` |

Note: Region is always `regionOne` regardless of physical location.

**Use S3, not Swift, for applications.** Both protocols are supported, but CSC is
moving to S3 as the default (it is the default on Roihu; Puhti/Mahti tooling still
defaults to Swift). S3 credentials are long-lived, whereas a Swift token expires
after ~8 hours — which makes Swift a poor fit for a long-running Rahti pod. Do not
mix protocols on the same bucket.

## Client configuration (critical)

Allas only supports **path-style** URLs (`a3s.fi/<bucket>/<key>`), not virtual-host-style (`<bucket>.a3s.fi`). The AWS SDK v3 defaults to virtual-host — you **must** override:

- AWS SDK v3 (JS/TS): `forcePathStyle: true`
- boto3 (Python): `config=Config(s3={"addressing_style": "path"})`

Without this the client will fail with DNS or signature errors against Allas.

## Credential Retrieval

### 1. Create S3 Bucket (prerequisite)

1. Login to [Allas UI](https://allas.csc.fi/)
2. Select the correct project from the left menu
3. Click **+ Create bucket** and give it a unique name

**Bucket naming:** Use `<project-id>-<purpose>` format (e.g., `1234567-raw-data`). Lowercase, numbers, hyphens only — no umlauts or special characters.

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
openstack configuration show          # auth.project_id must match bucket's project
openstack project list
openstack project set project_XXXXXXX # switch if needed
```

### 5. Get Credentials

```bash
openstack ec2 credentials list
openstack ec2 credentials create
```

## Environment Variables

Recommended convention: `ALLAS_S3_*` prefix (clear, namespaced, matches production projects). A short `ALLAS_*` form (`ALLAS_ENDPOINT_URL`, `ALLAS_ACCESS_KEY_ID`, `ALLAS_SECRET_ACCESS_KEY`, `ALLAS_BUCKET_NAME`) is also in use in existing projects. Pick one convention per project and stick with it — a codebase carrying both silently reads the wrong bucket.

```bash
ALLAS_S3_ENDPOINT=https://a3s.fi
ALLAS_S3_REGION=regionOne
ALLAS_S3_BUCKET=your-bucket-name
ALLAS_S3_ACCESS_KEY_ID=your-access-key
ALLAS_S3_SECRET_ACCESS_KEY=your-secret-key
ALLAS_S3_PRESIGNED_TTL_SECONDS=900
```

## Python (boto3)

```python
import os
import boto3
from botocore.config import Config

s3 = boto3.client(
    "s3",
    endpoint_url=os.environ["ALLAS_S3_ENDPOINT"],
    aws_access_key_id=os.environ["ALLAS_S3_ACCESS_KEY_ID"],
    aws_secret_access_key=os.environ["ALLAS_S3_SECRET_ACCESS_KEY"],
    region_name=os.getenv("ALLAS_S3_REGION", "regionOne"),
    config=Config(s3={"addressing_style": "path"}, retries={"max_attempts": 3}),
)

s3.upload_file("local_file.txt", os.environ["ALLAS_S3_BUCKET"], "remote_file.txt")
s3.download_file(os.environ["ALLAS_S3_BUCKET"], "remote_file.txt", "downloaded.txt")
```

## JavaScript (AWS SDK v3)

```typescript
import { S3Client, PutObjectCommand } from "@aws-sdk/client-s3";

export const s3Client = new S3Client({
  region: process.env.ALLAS_S3_REGION ?? "regionOne",
  endpoint: process.env.ALLAS_S3_ENDPOINT,
  credentials: {
    accessKeyId: process.env.ALLAS_S3_ACCESS_KEY_ID!,
    secretAccessKey: process.env.ALLAS_S3_SECRET_ACCESS_KEY!,
  },
  forcePathStyle: true, // Required for CSC Allas
  maxAttempts: 3,
});

await s3Client.send(new PutObjectCommand({
  Bucket: process.env.ALLAS_S3_BUCKET,
  Key: "test-file.txt",
  Body: "Hello Allas!",
}));
```

## Presigned URLs

Browsers upload/download directly to Allas without routing bytes through the app server. Requires `@aws-sdk/s3-request-presigner`.

```typescript
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";
import { GetObjectCommand, PutObjectCommand } from "@aws-sdk/client-s3";
import { s3Client } from "./s3";

const ttl = Number(process.env.ALLAS_S3_PRESIGNED_TTL_SECONDS ?? 900);

export function presignUpload(key: string, contentType: string) {
  return getSignedUrl(
    s3Client,
    new PutObjectCommand({ Bucket: process.env.ALLAS_S3_BUCKET, Key: key, ContentType: contentType }),
    { expiresIn: ttl },
  );
}

export function presignDownload(key: string) {
  return getSignedUrl(
    s3Client,
    new GetObjectCommand({ Bucket: process.env.ALLAS_S3_BUCKET, Key: key }),
    { expiresIn: ttl },
  );
}
```

CORS on the bucket must allow the app's origin for browser uploads.

## Injecting credentials into a Rahti pod

Never bake Allas keys into the image. Push them in as a Kubernetes secret and reference the secret from the deployment.

```bash
# From a local .env.local file (fastest)
oc create secret generic <app>-env --from-env-file=.env.local -n <namespace>
oc set env deployment/<app> --from=secret/<app>-env -n <namespace>

# Or set individual vars directly
oc set env deployment/<app> -n <namespace> \
  ALLAS_S3_ENDPOINT=https://a3s.fi \
  ALLAS_S3_REGION=regionOne \
  ALLAS_S3_BUCKET=your-bucket \
  ALLAS_S3_ACCESS_KEY_ID=... \
  ALLAS_S3_SECRET_ACCESS_KEY=...
```

Rotating keys: re-run `oc create secret ... --dry-run=client -o yaml | oc apply -f -` to update the secret, then `oc rollout restart deployment/<app>` so pods pick up the new values.

## Dockerfile ARG placeholders (Next.js specific)

Next.js bakes `NEXT_PUBLIC_*` values into the client bundle at build time, but Allas keys must be runtime-only. Use dummy ARG values for the build and let the Rahti secret override at runtime:

```dockerfile
# Build stage: dummy values so `next build` doesn't fail on missing env
ARG ALLAS_S3_ENDPOINT=https://a3s.fi
ARG ALLAS_S3_BUCKET=placeholder
ARG ALLAS_S3_ACCESS_KEY_ID=placeholder
ARG ALLAS_S3_SECRET_ACCESS_KEY=placeholder
ENV ALLAS_S3_ENDPOINT=$ALLAS_S3_ENDPOINT \
    ALLAS_S3_BUCKET=$ALLAS_S3_BUCKET \
    ALLAS_S3_ACCESS_KEY_ID=$ALLAS_S3_ACCESS_KEY_ID \
    ALLAS_S3_SECRET_ACCESS_KEY=$ALLAS_S3_SECRET_ACCESS_KEY
RUN bun run build
```

At runtime the K8s secret replaces these placeholders. See also [dockerfile-examples.md](dockerfile-examples.md).
