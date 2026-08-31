# 8. Allas object storage (S3)

> Rahti pods are stateless: data written to a pod's disk is lost. Persistent data
> belongs either on a PVC or — for large files, shared access, backups — in CSC's
> Allas object storage.

## Contents

- [S3 vs Swift](#s3-vs-swift)
- [1. Create a bucket](#1-create-a-bucket)
- [2. Install the OpenStack tools](#2-install-the-openstack-tools)
- [3. Get S3 credentials](#3-get-s3-credentials)
- [4. Store the credentials](#4-store-the-credentials)
- [5. Usage from code](#5-usage-from-code)
- [Credentials for Rahti](#credentials-for-rahti)
- [Troubleshooting](#troubleshooting)

## S3 vs Swift

Allas supports two protocols. **Use S3 in applications.**

| | S3 | Swift |
| --- | --- | --- |
| Credential lifetime | long-lived keys | token expires after ~8 h |
| Fits Rahti | yes | poorly — the token would expire mid-run |
| Library support | boto3, AWS SDK, s3cmd, rclone | swift-client |

Don't mix protocols within the same bucket.

| Service | Endpoint | Region |
| --- | --- | --- |
| S3 API | `https://a3s.fi` | `regionOne` |
| Swift API | `https://a3s.fi:443/swift/v1/AUTH_<project-id>` | `regionOne` |

> The region is always `regionOne`, even though the server is in Finland. Not
> `eu-north-1`.

## 1. Create a bucket

1. Log in at [allas.csc.fi](https://allas.csc.fi/)
2. Select the right project on the left
3. **+ Create bucket**

**Naming:** bucket names must be unique **across all Allas users**. CSC recommends
prefixing with your project number, e.g. `1234567-raw-data`. Lowercase letters,
digits, and hyphens only — no special characters.

> **Credentials and buckets are project-scoped.** Make sure you create the credentials
> in the same project as the bucket — otherwise you'll get a 403 and won't know why.

## 2. Install the OpenStack tools

Credentials are obtained with the OpenStack command-line tool.

```powershell
python -m pip install --user python-openstackclient
```

If the `openstack` command isn't found after installation, the Scripts folder isn't on
your PATH. Find the correct path:

```powershell
python -c "import sys, os; print(os.path.dirname(sys.executable) + '\\Scripts')"
```

Add the output to your PATH (permanently: Windows + R → `sysdm.cpl` → *Advanced →
Environment Variables → Path → New*), open a new terminal, and verify:

```powershell
openstack --version
```

**Configuration:**

1. Log in at [pouta.csc.fi](https://pouta.csc.fi/)
2. **API Access → Download OpenStack RC File → OpenStack clouds.yaml file**
3. Save the file to `~/.config/openstack/clouds.yaml`
   (on Windows: `C:\Users\<username>\.config\openstack\clouds.yaml`)

```powershell
mkdir "$HOME\.config\openstack"
```

The file content looks like this:

```yaml
clouds:
  openstack:
    auth:
      auth_url: https://pouta.csc.fi:5001/v3
      username: "<csc-username>"
      project_id: "<project-id>"
      project_name: "project_XXXXXXX"
      user_domain_name: "Default"
      # password: leave this out — it's prompted for at run time
    regions:
      - regionOne
    interface: "public"
    identity_api_version: 3
```

## 3. Get S3 credentials

```powershell
$env:OS_CLOUD = "openstack"

# Make sure you're in the right project
openstack configuration show          # check auth.project_id
openstack project list                # all projects
openstack project set project_XXXXXXX # switch if needed

# List existing credentials
openstack ec2 credentials list

# Create new ones if needed
openstack ec2 credentials create
```

The command prompts for your CSC password. Output:

```
+----------------------------------+-----------------------------------+----------------------------------+---------+
| Access                           | Secret                            | Project ID                       | User ID |
+----------------------------------+-----------------------------------+----------------------------------+---------+
| abc123def456ghi789jkl012mno345pq | xyz789uvw456rst123qpo890lmn567abc | def456abc789ghi012jkl345mno678pq | tunnus  |
+----------------------------------+-----------------------------------+----------------------------------+---------+
```

`Access` = access key, `Secret` = secret key.

> On CSC's supercomputers (Roihu, LUMI) the same thing is one command:
> `allas-conf` prints the S3 connection details directly.

## 4. Store the credentials

Locally, in a `.env` file (which is in `.gitignore`):

```ini
ALLAS_ACCESS_KEY_ID=abc123def456ghi789jkl012mno345pq
ALLAS_SECRET_ACCESS_KEY=xyz789uvw456rst123qpo890lmn567abc
ALLAS_ENDPOINT_URL=https://a3s.fi
ALLAS_BUCKET_NAME=1234567-raw-data
```

## 5. Usage from code

**The single most important detail:** Allas only supports **path-style** addressing
(`a3s.fi/<bucket>/<key>`), not virtual-host style (`<bucket>.a3s.fi`). AWS SDK v3
defaults to virtual-host style, so you must override that setting.

### Python (boto3)

```python
import boto3, os

s3 = boto3.client(
    "s3",
    endpoint_url=os.getenv("ALLAS_ENDPOINT_URL"),
    aws_access_key_id=os.getenv("ALLAS_ACCESS_KEY_ID"),
    aws_secret_access_key=os.getenv("ALLAS_SECRET_ACCESS_KEY"),
    region_name="regionOne",
)

for b in s3.list_buckets()["Buckets"]:
    print(b["Name"])

bucket = os.getenv("ALLAS_BUCKET_NAME")
s3.upload_file("local.txt", bucket, "folder/remote.txt")
s3.download_file(bucket, "folder/remote.txt", "downloaded.txt")
```

boto3 handles path-style automatically for this endpoint. If you run into problems,
force it:

```python
from botocore.config import Config
s3 = boto3.client("s3", ..., config=Config(s3={"addressing_style": "path"}))
```

### JavaScript / TypeScript (AWS SDK v3)

```javascript
import { S3Client, ListBucketsCommand, PutObjectCommand } from "@aws-sdk/client-s3";

const s3 = new S3Client({
  endpoint: process.env.ALLAS_ENDPOINT_URL,   // https://a3s.fi
  region: "regionOne",
  forcePathStyle: true,                        // ← REQUIRED for Allas
  credentials: {
    accessKeyId: process.env.ALLAS_ACCESS_KEY_ID,
    secretAccessKey: process.env.ALLAS_SECRET_ACCESS_KEY,
  },
});

const { Buckets } = await s3.send(new ListBucketsCommand({}));

await s3.send(
  new PutObjectCommand({
    Bucket: process.env.ALLAS_BUCKET_NAME,
    Key: "test.txt",
    Body: "Hello Allas!",
  })
);
```

## Credentials for Rahti

```bash
oc create secret generic allas-credentials \
  --from-literal=ALLAS_ACCESS_KEY_ID='...' \
  --from-literal=ALLAS_SECRET_ACCESS_KEY='...' \
  --from-literal=ALLAS_ENDPOINT_URL='https://a3s.fi' \
  --from-literal=ALLAS_BUCKET_NAME='1234567-raw-data' \
  -n <project>

oc set env deployment/app --from=secret/allas-credentials -n <project>
```

These are runtime variables — **don't put them behind a `NEXT_PUBLIC_` or
`VITE_` prefix**, or the keys will end up in the browser (see
[05 Environment variables](05-environment-variables.md#build-time-vs-runtime)).

If the build fails on missing keys, give it an empty placeholder:

```dockerfile
ARG ALLAS_ACCESS_KEY_ID=""
ENV ALLAS_ACCESS_KEY_ID=$ALLAS_ACCESS_KEY_ID
RUN npm run build
```

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| `SignatureDoesNotMatch` | Wrong secret key, or virtual-host addressing is on → set `forcePathStyle: true` |
| `403 Forbidden` on the bucket | Credentials were created in a different project than the bucket |
| `NoSuchBucket` | The bucket is in a different project, or the name has a typo |
| `openstack: command not found` | The Python Scripts folder isn't on PATH (see above) |
| `pip: command not found` | Use `python -m pip install …` |
| Connection times out from Rahti | Check the endpoint doesn't use `http://` — only `https://a3s.fi` |

---

**Previous:** [7. Database](07-database.md) · **Next:** [9. Troubleshooting →](09-troubleshooting.md)

**Sources:** [CSC: Allas](https://docs.csc.fi/data/Allas/) ·
[CSC: How to get Allas S3 credentials](https://docs.csc.fi/support/faq/how-to-get-Allas-s3-credentials/)
