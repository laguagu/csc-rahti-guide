# CSC-Rahti Instructions

## Table of Contents

1. [Deploying an application to CSC Rahti 2 using Docker - Simple guide](#deploying-an-application-to-csc-rahti-2-using-docker---simple-guide)
2. [Deploying an application to CSC Rahti 2 with GitHub integration](#deploying-an-application-to-csc-rahti-2-with-github-integration)
3. [Production versions of a React (Vite) + Node.js application](#production-versions-of-a-react-vite--nodejs-application)
4. [Changing a Rahti application URL](#changing-a-rahti-application-url)
5. [Installing the PostgreSQL pgVector database](#installing-the-postgresql-pgvector-database)
6. [Retrieving CSC Allas S3 Credentials](#retrieving-csc-allas-s3-credentials)

## Deploying an application to CSC Rahti 2 using Docker - Simple guide

### Important note before you start!

There are two options for using the Rahti 2 container registry:

1. Create an ImageStream manually in your project (instructions below)
2. OR push the first application via DockerHub:
   - Use the DockerHub registry for the first deployment
   - After a successful deployment, Rahti automatically creates an ImageStream for your application
   - After this, you can switch to using Rahti's own container registry
   - The ImageStream can be found in the Builds → ImageStreams menu

### 1. Logging into Rahti

1. Go to the Rahti 2 web interface.
2. Click your name in the top right corner -> "Copy login command"
3. Copy and run the login command in your terminal:

```bash
oc login --token=sha256~[your-token] --server=https://api.2.rahti.csc.fi:6443
```

### 2. Building and testing the container

1. Build the Docker image:

```bash
# Basic command
docker build -t your-app-name .

# OR if you want to avoid using the cache (optional)
docker build --no-cache -t your-app-name .
```

2. Test locally (optional step):

```bash
# Without environment variables
docker run -p 3000:3000 your-app-name

# With environment variables
docker run --env-file .env -p 3000:3000 your-app-name
```

### 3. Pushing the image to a registry

Choose EITHER Rahti 2's own container registry OR DockerHub:

#### Option A: Rahti 2 container registry

(Available once an ImageStream has been created or the first application has been pushed via DockerHub)

1. Log in to the Rahti 2 registry:

```bash
docker login -u unused -p $(oc whoami -t) image-registry.apps.2.rahti.csc.fi
```

2. Tag and push the image:

```bash
docker tag your-app-name image-registry.apps.2.rahti.csc.fi/your-project-name/your-app-name:latest
docker push image-registry.apps.2.rahti.csc.fi/your-project-name/your-app-name:latest
```

#### Option B: DockerHub

```bash
docker tag your-app-name username/your-app-name:latest
docker push username/your-app-name:latest
```

### 4. Deploying the application in Rahti 2

#### Option 1: Direct deployment from a container registry

1. Navigate to the Rahti 2 web console and your project.
2. Select "Add" → "Container images"
3. In the "Deploy Image" view:

   **Image settings:**

   - Select "Deploy an existing Image from an Image Stream or Image registry"
   - Use either:
     - **DockerHub image**: Enter directly in the format `username/app:latest` (e.g., `laguagu/alya:latest`)
     - OR **Rahti registry**: Select from the internal registry

   **Note on private DockerHub images:**

   - For a private DockerHub image, you need to create an "Image pull secret"
   - Specify the secret name, registry (docker.io), username, and password
   - This is not needed for public images

   **General settings:**

   - **Application**: Select/create an application configuration (e.g., "alya-avustaja")
   - **Name**: Give the component a unique name
   - **Target port**: Specify the port your application listens on (e.g., 3000)

Rahti automatically creates a public URL for your application with default settings:

- Automatically generates a hostname
- Uses Edge TLS termination
- Redirects HTTP traffic to HTTPS

#### Option 2: Creating and using an ImageStream

1. Go to Builds → ImageStreams → Create ImageStream
2. Create the ImageStream:

```yaml
apiVersion: image.openshift.io/v1
kind: ImageStream
metadata:
  name: your-app-name
  namespace: your-project-name
```

Note! You can also push an image directly to the Rahti 2 registry without creating an ImageStream beforehand! Rahti will create it automatically in that case.

3. Use the created ImageStream when deploying the application

### 5. Deployment settings

Define the following during deployment:

- **Deployment strategy**: Rolling Update
- **Auto deploy**: Turn on "Auto deploy when new Image is available"
- **Environment Variables**: Add necessary environment variables as Name/Value pairs

## Deploying an application to CSC Rahti 2 with GitHub integration

This guide covers:

- Deploying an application to Rahti 2 using GitHub integration (BuildConfig)
- Configuring an automatic build process using a GitHub webhook

### Important note (8.11.2024)

**Current Rahti 2 limitation/bug:** When you try to create a project directly with GitHub integration and your own Dockerfile, you get a "URL is valid but cannot be reached" error, even if the SSH connection is configured correctly.

#### Builder Image vs. Your own Dockerfile

You can choose between two approaches:

1. **Use Rahti's Builder Image (simpler):**

   - Suitable for traditional Node.js applications
   - Sufficient for most simple web applications
   - Does not require a custom Dockerfile
   - Quicker to set up

2. **Use your own Dockerfile (more flexible):**
   - Needed if the application has special requirements
   - Required for example with React Vite
   - Gives full control over the build process
   - Requires a two-step setup:
     1. First, create the project using Rahti's pre-built Builder Image
     2. Then, modify the BuildConfig to use the Dockerfile from your own repository

Choose the approach based on your application's requirements. If you are not sure, start with the Builder Image - you can always switch to using your own Dockerfile later.

### Table of Contents

1. [Creating and configuring an SSH key](#creating-and-configuring-an-ssh-key)
2. [Configuring Rahti](#configuring-rahti)
3. [Configuring a Dockerfile (optional)](#configuring-a-dockerfile-optional)
4. [Defining a Webhook](#defining-a-webhook)

### Creating and configuring an SSH key

1. **Create an SSH key pair:**

```bash
ssh-keygen -t rsa -b 4096 -C "your-project@example.com" -f ./rahti_github_key
```

- Press Enter when asked for a passphrase (empty is ok)

2. **GitHub configuration:**

- Go to your GitHub repository's settings → Deploy keys
- Click "Add deploy key"
- Copy the public key from the file: `cat rahti_github_key.pub`
- Give the key a descriptive name (e.g., "Rahti Deploy Key")
- Select "Allow write access"

### Configuring Rahti

1. **Create a new project in Rahti:**

- Select +Add → Import from Git
- Git Repo URL: Use the SSH format URL (e.g., `git@github.com:username/repo.git`)
  - You can get the SSH format from your repository by clicking the Code button and selecting SSH
- Click "Show advanced Git options"

2. **Add the SSH key to Rahti:**

- Source Secret → Create new Secret
- Authentication type: SSH key
- Copy the private key (`cat rahti_github_key`)
- **Important:** Include the BEGIN and END lines as well

**NOTE!** At this point, Rahti will show the error "URL is valid but cannot be reached" even if you have added the SSH keys correctly to both Rahti and GitHub. Due to this limitation, we cannot use the Import Strategy → Dockerfile option, but must instead choose a pre-built Builder Image (e.g., Node.js). You can proceed despite the error and select a Builder Image in the following steps.

3. **Defining the Builder Image:**

- Select a suitable Builder Image (e.g., Node.js 18 (UBI 8))
- Specify the application's port in the Advanced options
- Select "Create a route" for a public URL
- Finally, click "Create"

**Note:** If your application works with this configuration, you can continue using it and do not need to define your own Dockerfile.

### Configuring a Dockerfile (optional)

If the Builder Image is not sufficient for your application's needs:

1. **Modifying the BuildConfig from Builder Image to your own Dockerfile:**

- Go to Builds → BuildConfig → YAML
- Change the strategy section to use the Dockerfile in your repository:

```yaml
strategy:
  type: Docker
  dockerStrategy:
    dockerfilePath: Dockerfile
```

This replaces the Builder Image configuration and starts using the Dockerfile in your repository.

**Note!** Creating a Dockerfile is outside the scope of this guide. If you need help creating a Dockerfile for your application, you can use:

- ChatGPT/Claude
- Docker's official documentation, etc.

### Defining a Webhook

Define a webhook for automatic builds.

1. **Get webhook information from Rahti:**

- The BuildConfig will have automatically generated webhook secrets
- Copy the GitHub webhook secret (`<buildconfig-name>-generic-webhook-secret`)

2. **Add the webhook to GitHub:**

- GitHub repository → Settings → Webhooks → Add webhook
- Payload URL format:

```https://api.2.rahti.csc.fi:6443/apis/build.openshift.io/v1/namespaces/<project>/buildconfigs/<buildconfig>/webhooks/<secret>/generic
```

> You can copy the URL from the Rahti UI under Webhooks -> "Copy URL with Secret"

- Content type: `application/json`
- Secret: The same secret as in the URL
- SSL verification: Enable
- Just the push event: ✓
- Active: ✓

### Testing

1. Make a change to the GitHub repository
2. Push to the main branch
3. Check in Rahti that a build starts automatically

### Notes

- Rahti 2 may show a "URL is valid but cannot be reached" error with SSH connections.
- The problem can be circumvented by first using a Builder Image and then configuring the BuildConfig to use a Dockerfile.
- Make sure the ports match in the configuration.

### Useful tips for the Rahti/Docker environment

#### Using tags

Rahti builds the image based on the specified tag. You can define the tag yourself:

```bash
# Example of publishing a new version with a specific tag
docker tag your-app-name image-registry.apps.2.rahti.csc.fi/your-project-name/your-app-name:v1.0.0
docker push image-registry.apps.2.rahti.csc.fi/your-project-name/your-app-name:v1.0.0
```

- You can define the tag in Rahti that triggers an auto deploy. For example: `:latest`

#### Useful commands

**ImageStream and builds (persistent resources):**

```bash
# Check ImageStream and its tags
oc get imagestream
oc describe imagestream your-app-name
```

**Pods (temporary execution environments):**

```bash
# Check pod status
oc get pods
# Pods can be in the following states:
# - Running
# - Pending
# - CrashLoopBackOff (startup problems)

# View pod logs
oc logs pods/pod-name

# Check deployment status (manages pods)
oc get deployment

# Delete a pod (Rahti will automatically create a new one)
oc delete pod pod-name

# List everything
oc get all
```

**Note on Pods:**

- Pods are temporary execution environments that can be destroyed and restarted.
- Rahti manages pods automatically through Deployments.
- If a pod is destroyed, Rahti automatically starts a new one.
- Do not save data to a pod, as it will be lost when the pod is destroyed.

#### General practices

1. **Use internal service names when possible**
   - Keep the backend as an internal service without a public route
   - Use Kubernetes service names (e.g., `http://backend-service-name:8080`)
2. Check application logs after deployment.
3. Keep the image as small as possible (use .dockerignore).

## Production versions of a React (Vite) + Node.js application

> **NOTE!** This guide contains theoretical solution options that have not yet been fully tested in the Rahti 2 production environment. The principles are correct, but the details may need fine-tuning. Use this guide as a basis and modify it as needed for your own use.

This guide covers three different ways to deploy a React (Vite) + Node.js application in Rahti.

### Option A: Simple solution (without a separate Dockerfile)

This is the easiest way if you don't want to use Docker yourself and prefer to let Rahti handle the containerization:

1. Build the React application:

```bash
cd frontend-repo
npm run build
```

2. Prepare the backend:

```bash
cd backend-repo
mkdir client      # Create a folder for the frontend build
```

3. Copy the frontend build to the backend:

- Copy the `frontend-repo/dist` folder to the `backend-repo/client/dist` folder

4. Modify `backend/index.js`:

```javascript
const express = require("express");
const path = require("path");
const app = require("./app");
require("dotenv").config();

// Serve the frontend build
app.use(express.static(path.join(__dirname, "client/dist")));

// This must be after the API routes
// Handles client-side routing
app.get("*", (req, res) => {
  res.sendFile(path.join(__dirname, "client/dist", "index.html"));
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
```

**Note!**

- When you start the application with the `npm start` command (assuming this starts your backend server), both the backend and frontend will run on the same port (8080).
- The frontend build is static content served by the backend.
- No need for a separate frontend server.
- All API calls go to the same address where the frontend is running.

### Option B: Docker Compose (monorepo solution)

1. Project structure:

```
project/
├── backend/
│   ├── index.js
│   └── package.json
├── frontend/
│   ├── src/
│   └── package.json
├── docker-compose.yml
└── Dockerfile
```

2. Dockerfile:

```dockerfile
FROM node:18-alpine
WORKDIR /app

# Copy package.json files
COPY package*.json ./
COPY frontend/package*.json ./frontend/
COPY backend/package*.json ./backend/

# Install dependencies
RUN npm install
RUN cd frontend && npm install
RUN cd backend && npm install

# Copy and build
COPY . .
RUN cd frontend && npm run build
RUN mkdir -p backend/client
RUN cp -r frontend/dist backend/client/

EXPOSE 8080
CMD ["node", "backend/index.js"]
```

3. docker-compose.yml:

```yaml
version: "3.8"
services:
  app:
    build: .
    ports:
      - "8080:8080"
    environment:
      - NODE_ENV=production
      - PORT=8080
      - OPENAI_KEY=your_key_here
```

### Option C: Separate Backend API

The backend acts as an independent API built using Rahti's Node.js sample. The frontend needs its own Dockerfile if you just want to containerize the Vite application and call the backend API.

#### 1. Using the Backend API

The backend is already running in Rahti (e.g., URL: https://backend-yourproject.rahtiapp.fi):

```javascript
const express = require("express");
const cors = require("cors");
const app = require("./app");
require("dotenv").config();

// CORS settings - add frontend URL
app.use(
  cors({
    origin: ["https://frontend-yourproject.rahtiapp.fi"],
  })
);

// API routes...
app.get("/api/status", (req, res) => {
  res.json({ status: "ok" });
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`Server running on port ${PORT}`);
});
```

> **Best Practice:** For security reasons, the best practice in Rahti is to keep the backend service completely internal without a public route. In this case, the frontend calls the backend via its internal service name (e.g., `http://backend-service-name:8080`). When you define the backend as a service without routes, it is only accessible from within the Rahti project. In the frontend application, you can set the environment variable `API_URL=http://backend-service-name:8000` to point to the internal service.

#### 2. Frontend setup (Vite)

1. Add a Dockerfile to the frontend folder:

```dockerfile
# Build stage
FROM node:20-alpine AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

# Production stage
FROM node:20-alpine
WORKDIR /app
COPY --from=builder /app/dist ./dist
RUN npm install -g serve
EXPOSE 8080
CMD ["serve", "-s", "dist", "-p", "8080"]
```

##### Using the `serve` tool

- The command `serve -s dist` used in the Dockerfile is intended for Single Page Applications (SPAs).
- The `-s` or `--single` flag:
  - Redirects all requests to `index.html`.
  - Essential for SPA routing to work (React Router, Vue Router, etc.).
- **If your application is NOT an SPA:**
  - Remove the `-s` flag from the command.
  - Use: `CMD ["serve", "dist", "-p", "8080"]`
  - Suitable for regular static sites (multi-page).

2. Add `.dockerignore` to the frontend folder:

```
node_modules
dist
.env
```

3. Configure the backend URL in the frontend:

```javascript
// src/config.js
export const BACKEND_URL =
  import.meta.env.VITE_BACKEND_URL || "http://localhost:8080";

// Usage in components
const response = await fetch(`${BACKEND_URL}/api/endpoint`, {
  method: "POST",
  body: formData,
});
```

### Notes

- The frontend uses port 8080 (a requirement in this example for Rahti).
- CORS settings must allow the frontend URL.
- Rahti automatically creates a public URL for the frontend.

### Environment Variables and Security

- **Securing API routes:** Always use appropriate security.
  - API key (VITE_API_KEY)
  - JWT token
  - Other authentication methods

```env
VITE_BACKEND_URL=https://backend-yourproject.rahtiapp.fi
VITE_API_KEY=your-secret-api-key
```

### Summary

Choose the solution according to your needs:

A. **Simple solution**: Serve the Vite build from the backend.

- Easiest to implement
- Does not require Docker
- Everything in one service

B. **Docker solution**: Combine frontend and backend.

- Monorepo approach
- Easy to maintain
- Good for a development environment

C. **Separate API**: Keep frontend and backend separate.

- Clear separation between services
- Scales well
- Requires CORS configuration

Key things to remember:

1. Use the correct port in Rahti. In this example, 8080.
2. Define API paths correctly.
3. Consider CORS settings if necessary.

### API Path Usage

#### In a combined solution (Options A and B):

```javascript
// Use relative paths
const response = await fetch("/api/endpoint", {
  method: "POST",
  body: formData,
});
```

#### In a separate API solution (Option C):

```javascript
// Use the full URL from the configuration
const response = await fetch(`${BACKEND_URL}/api/endpoint`, {
  method: "POST",
  body: formData,
});
```

### Automation in a monorepo environment

```
monorepo/
├── package.json           # Top-level package.json
├── node_modules/
├── frontend/             # Frontend project
│   ├── package.json
│   ├── src/
│   └── dist/            # Build folder
└── backend/             # Backend project
    ├── package.json
    ├── src/
    └── client/          # Frontend build is copied here
        └── dist/
```

If you keep the frontend and backend in the same repository, you can automate the build process by adding the following script to the top-level `package.json` file:

```json
{
  "scripts": {
    "build:frontend": "cd frontend && npm install && npm run build",
    "postbuild:frontend": "rm -rf backend/client/dist && cp -r frontend/dist backend/client/",
    "prebuild": "npm install",
    "build": "npm run build:frontend",
    "start": "cd backend && npm start"
  }
}
```

This allows you to:

1. Build the frontend.
2. Automatically copy the build to the `backend/client` folder.
3. Run the entire process with a single command: `npm run build`


## Changing a Rahti application URL

In Rahti, you can add a new URL or change the existing URL of an application by creating a new Route object. Multiple routes can point to the same service with different hostnames.

### YAML file method (Recommended)

#### Step 1: Create a YAML file for the new route

Create a file named `new-route.yaml` with the following content:

```yaml
kind: Route
apiVersion: route.openshift.io/v1
metadata:
  name: <route-name>
  namespace: <namespace>
  labels:
    app: <app-name>
    app.kubernetes.io/component: <app-name>
    app.kubernetes.io/instance: <app-name>
    app.kubernetes.io/name: <app-name>
    app.kubernetes.io/part-of: <project-name>
  annotations:
    openshift.io/host.generated: "false"
spec:
  host: <custom-name>.2.rahtiapp.fi
  to:
    kind: Service
    name: <service-name>
    weight: 100
  port:
    targetPort: <port>-tcp
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
```

Replace:

- `<route-name>`: The name of the route object
- `<namespace>`: Your project's namespace
- `<app-name>`: Your application's name
- `<project-name>`: Your project's name
- `<custom-name>`: Your desired URL prefix
- `<service-name>`: The name of the service the route connects to
- `<port>`: The port number your service uses (e.g., 3000, 8080)

#### Step 2: Create the new route

1. First, make sure you are in the correct project:

```bash
oc project
```

2. Then, create the new route:

```bash
oc create -f new-route.yaml
```

#### Step 3: Test the new route

Visit your new URL to ensure it works correctly.

#### Step 4: Optionally, delete the old route

If you no longer need the old route, you can delete it:

```bash
oc delete route <old-route-name> -n <namespace>
```

**Note:** You can keep multiple routes active simultaneously. Each route can have a different hostname, even if they point to the same service. This allows you to keep both old and new URLs active during transition periods.

### Example

For an application "upbeat" whose service name is "upbeat" and runs on port 3000:

```yaml
kind: Route
apiVersion: route.openshift.io/v1
metadata:
  name: learning-assistant
  namespace: upbeat-apps
  labels:
    app: upbeat
    app.kubernetes.io/component: upbeat
    app.kubernetes.io/instance: upbeat
    app.kubernetes.io/name: upbeat
    app.kubernetes.io/part-of: learning-assistant
  annotations:
    openshift.io/host.generated: "false"
spec:
  host: learning-assistant.2.rahtiapp.fi
  to:
    kind: Service
    name: upbeat
    weight: 100
  port:
    targetPort: 3000-tcp
  tls:
    termination: edge
    insecureEdgeTerminationPolicy: Redirect
  wildcardPolicy: None
```

**Note:** Rahti hostnames must end with the `.2.rahtiapp.fi` suffix, and the prefix must be unique across the entire Rahti environment.

## Installing the PostgreSQL pgVector database

A PostgreSQL database with the pgVector extension can be installed in the Rahti environment using a Red Hat compatible container image designed to work in an OpenShift environment.

1. Log in to the Rahti 2 web interface.
2. Select a project or create a new one.
3. Select the "Deploy Image" function.
4. Select "Image name from external registry" and enter:
   ```
   quay.io/rh-aiservices-bu/postgresql-15-pgvector-c9s
   ```
5. Give the deployment a name (e.g., "postgresql-pgvector").
6. Set the required environment variables:
   - POSTGRESQL_USER=postgres
   - POSTGRESQL_PASSWORD=strong_password
   - POSTGRESQL_DATABASE=vectordb
7. **DO NOT** create a Route for the database for security reasons.

### Adding persistent storage

The database needs persistent storage so that data persists between pod restarts:

1. Open the Deployment you created.
2. Select "Actions" → "Add Storage".
3. Create a new PersistentVolumeClaim (PVC):
   - Name: "pgvector-data"
   - Access mode: Single user (RWO)
   - Size: 5 GiB or more depending on needs
   - Mount path: `/var/lib/pgsql/data`
4. Save the changes.

### Enabling the pgVector extension

You can easily activate the pgVector extension through the pgAdmin interface:

1. **Connect to the database with pgAdmin** using a port-forward connection or a direct connection within the cluster.

2. **Expand the server connection**, right-click on "Databases" and select "Create" → "Database..."
3. **Create a new database** (if it doesn't already exist):

   - Name it "vectordb"
   - Click "Save"

4. **Expand the vectordb database**, right-click on "Extensions" → "Create" → "Extension..."

5. **Select the pgVector extension**:

   - Choose "vector" from the dropdown menu
   - Click "Save"

6. **Check that the extension is activated**:
   - Expand the "Extensions" folder under the vectordb database
   - The list will now show the "vector" extension

Alternatively, you can also run an SQL command in pgAdmin's query window:

1. Open the Query Tool (from the toolbar or Ctrl+Shift+Q)
2. Type:

   ```sql
   CREATE EXTENSION vector;
   ```

3. Execute the query (F5 or the Execute button)

### Using the pgVector extension

Once the extension is activated, you can use vector features:

```sql
-- Create a table with a vector property (3-dimensional vector)
CREATE TABLE items (id bigserial PRIMARY KEY, embedding vector(3));

-- Insert data into the table
INSERT INTO items (embedding) VALUES (''), ('');

-- Perform a vector search (finds the nearest vectors to a given vector)
SELECT * FROM items ORDER BY embedding <-> '' LIMIT 5;
```

### Managing the database with the pgAdmin application

The PostgreSQL database can be managed with the pgAdmin application using a port-forward connection:

1. Install pgAdmin locally (https://www.pgadmin.org/download/)

2. Create a port-forward connection to the PostgreSQL service using the OpenShift CLI:

   ```bash
   # First, connect to Rahti
   oc login

   # Select the project
   oc project [project-name]

   # Create a port-forward connection
   oc port-forward svc/postgresql-pgvector 5432:5432
   ```

   Leave the command-line window open to maintain the connection.

3. Start your local pgAdmin application and create a new server connection:

   - Name: Rahti PostgreSQL
   - Host: localhost (127.0.0.1)
   - Port: 5432
   - Maintenance database: vectordb
   - Username: postgres
   - Password: (the POSTGRESQL_PASSWORD you defined)

4. Connect and start managing the database.

### Connecting the database to an application in Rahti

When both the application and the PostgreSQL database are running in the same Rahti project, the application can connect to the database using the service name as the host name:

```
DATABASE_URL=postgresql://postgres:password@postgresql-pgvector:5432/vectordb
```

This connection string can be set in the application's environment variables.

### Notes

- The port-forward connection is temporary and will be disconnected if the command-line window is closed. It is intended primarily for management use.


## Retrieving CSC Allas S3 Credentials

This guide explains how to get S3 credentials for the CSC Allas object storage service in a Windows 11 environment.

**Quick option:** Use the ready-made Python script `get_s3_credentials.py` found in the root directory of this project (Option B). The script automates the entire process and retrieves the credentials with a single command.

### Prerequisites

- ✅ CSC user account and a project with Allas enabled
- ✅ Python 3.8+ installed
- ✅ Access to the CSC Pouta service ([my.csc.fi](https://my.csc.fi))

### Option A: Manual credential retrieval with OpenStack CLI

### 1. Create an S3 Bucket in the Allas user interface

Before retrieving credentials, create the bucket(s) you need:

1. Log in to the [CSC Allas user interface](https://allas.csc.fi/).
2. Select the correct project from the left menu.
3. Click **"+ Create bucket"** to create a new bucket.
4. Give the bucket a unique name.

#### Bucket naming

Bucket names must be unique across all Allas users. CSC recommends using the project ID in the name, e.g., `2000620-raw-data`. Use only lowercase letters, numbers, and hyphens - do not use ä, ö, or other special characters.

### 2. Download the clouds.yaml configuration

1. Log in to the [CSC Pouta service](https://pouta.csc.fi/).
2. Go to the **API Access** section.
3. Click **Download OpenStack RC File** and select **OpenStack clouds.yaml file**.
4. Save the downloaded `clouds.yaml` file.

### 3. Configure clouds.yaml

#### Create the configuration folder

```powershell
mkdir "$HOME\.config\openstack"```

#### Save the clouds.yaml file

Move the downloaded `clouds.yaml` file to the folder:

```C:\Users\[username]\.config\openstack\clouds.yaml
```

#### Example clouds.yaml content

```yaml
clouds:
  openstack:
    auth:
      auth_url: https://pouta.csc.fi:5001/v3
      username: "username"
      project_id: "2fb68cf252gg40a8bv51d86d922f5977"
      project_name: "project_2111111"
      user_domain_name: "Default"
      # password: "password"  # Optional - will be prompted for automatically
    regions:
      - regionOne
    interface: "public"
    identity_api_version: 3```

**Note:** The password can be omitted - the program will prompt for it automatically.

### 4. Install the OpenStack Client

#### Install the Python package

```powershell
python -m pip install --user python-openstackclient
```

#### Fix the PATH (important!)

The OpenStack client may not be in the PATH after installation. Add the Python Scripts folder to the PATH:

```powershell
$env:PATH = "C:\Users\[username]\AppData\Local\Programs\Python\Python313\Scripts;" + $env:PATH
```

**NOTE:** Paths vary depending on the Python installation! Check your own paths first with the command:

```powershell
python -c "import sys; import os; print(os.path.dirname(sys.executable) + '\\Scripts')"
```

Use the printed path instead of the command above.

**I recommend setting the PATH permanently:**

- Windows key + R → `sysdm.cpl`
- Advanced → Environment Variables
- System variables → PATH → Edit → New
- Add: The path to the Scripts folder you found above
- OK, OK, OK → Open a new PowerShell

#### Test the installation

```powershell
openstack.exe --version
```

Should display something like: `openstack 8.1.0`

### 5. Get S3 Credentials

#### Check and change project if necessary

Before creating S3 credentials, make sure you are in the correct project:

##### Check the current project

```powershell
openstack.exe configuration show
```

Look for the line `auth.project_id` - this value must match the Object Store endpoint URL. In the Object Store URL, it appears in the format: `AUTH_[project-id]`

##### List available projects

```powershell
openstack.exe project list
```

##### Change project

If you are not in the correct project:

```powershell
openstack.exe project set [project-name]
```

Example: `openstack.exe project set project_2013111`

##### Confirm project change

```powershell
openstack.exe project show [project-name]
```

**IMPORTANT:** S3 credentials and buckets are project-specific. Make sure you create the credentials in the same project where the bucket is located!

#### Set the cloud environment

```powershell
$env:OS_CLOUD = "openstack"
```

#### List existing credentials

```powershell
openstack.exe ec2 credentials list
```

The program will ask for your CSC password. Enter it and you will get a list of existing S3 credentials:

```
+----------------------------------+----------------------------------+----------------------------------+----------+
| Access                           | Secret                           | Project ID                       | User ID  |
+----------------------------------+----------------------------------+----------------------------------+----------+
| abc123def456ghi789jkl012mno345pq | xyz789uvw456rst123qpo890lmn567abc | def456abc789ghi012jkl345mno678pqr | user     |
+----------------------------------+----------------------------------+----------------------------------+----------+
```

#### Create new credentials (if needed)

If you do not have existing credentials:

```powershell
openstack.exe ec2 credentials create
```

### 6. Save Credentials

Copy the **Access** and **Secret** values and save them securely. You can use them as environment variables:

```powershell
$env:ALLAS_ACCESS_KEY_ID="abc123def456ghi789jkl012mno345pq"
$env:ALLAS_SECRET_ACCESS_KEY="xyz789uvw456rst123qpo890lmn567abc"
$env:ALLAS_ENDPOINT_URL="https://a3s.fi"
$env:ALLAS_BUCKET_NAME="your-bucket-name"
```

### 7. Usage in code

#### Python (boto3)

```python
import boto3
import os

# Install: pip install boto3
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
bucket_name = os.getenv('ALLAS_BUCKET_NAME')
s3.upload_file('local_file.txt', bucket_name, 'remote_file.txt')

# Download file
s3.download_file(bucket_name, 'remote_file.txt', 'downloaded_file.txt')
```

#### JavaScript (Node.js)

```javascript
import {
  S3Client,
  ListBucketsCommand,
  PutObjectCommand,
} from "@aws-sdk/client-s3";

// Install: npm install @aws-sdk/client-s3
const s3Client = new S3Client({
  endpoint: process.env.ALLAS_ENDPOINT_URL,
  region: "regionOne",
  credentials: {
    accessKeyId: process.env.ALLAS_ACCESS_KEY_ID,
    secretAccessKey: process.env.ALLAS_SECRET_ACCESS_KEY,
  },
});

// List buckets
const { Buckets } = await s3Client.send(new ListBucketsCommand({}));
Buckets.forEach((bucket) => console.log(`Bucket: ${bucket.Name}`));

// Upload
const uploadParams = {
  Bucket: process.env.ALLAS_BUCKET_NAME,
  Key: "test-file.txt",
  Body: "Hello Allas!",
};
await s3Client.send(new PutObjectCommand(uploadParams));
```

### 8. .env file (recommended)

Create a `.env` file in your project folder:

```ini
ALLAS_ACCESS_KEY_ID=abc123def456ghi789jkl012mno345pq
ALLAS_SECRET_ACCESS_KEY=xyz789uvw456rst123qpo890lmn567abc
ALLAS_ENDPOINT_URL=https://a3s.fi
ALLAS_BUCKET_NAME=your-bucket-name
```

**Remember to add the `.env` file to `.gitignore` for security!**

### Option B: Automatic credential retrieval with a Python script

The project's root folder contains a ready-made `get_s3_credentials.py` script that automates the entire process:

#### 1. Install necessary Python packages

```bash
pip install keystoneauth1 python-keystoneclient pyyaml
```

#### 2. Download the clouds.yaml configuration

1. Log in to the [CSC Pouta service](https://pouta.csc.fi/).
2. Go to the **API Access** section.
3. Click **Download OpenStack RC File** and select **OpenStack clouds.yaml file**.
4. Save the downloaded file as `clouds.yaml` in one of the following locations:
   - `~/.config/openstack/clouds.yaml` (recommended)
   - `~/clouds.yaml`
   - In the project's root folder `./clouds.yaml`

#### 3. Run the Python script

```bash
python get_s3_credentials.py
```

The script will:

- Ask for your CSC password
- List existing S3 credentials
- Create new credentials if necessary
- Display the Access Key and Secret Key for you to copy into your application

#### 4. Copy the credentials into your application

The script displays the credentials in the format:

```
Access Key: abc123def456ghi789jkl012mno345pq
Secret Key: xyz789uvw456rst123qpo890lmn567abc
Endpoint: https://a3s.fi
Region: regionOne
```

### Troubleshooting

#### `openstack` command does not work

If you get the error `openstack : The term 'openstack' is not recognized`:

1. Check the location of the Python Scripts folder:

   ```powershell
   python -c "import sys; print(sys.executable)"
   ```

   Add `\Scripts\` to the end and set it in your PATH.

2. Try with the full path:
   ```powershell
   "C:\Users\[user]\AppData\Local\Programs\Python\Python313\Scripts\openstack.exe" --version
   ```

#### `pip` does not work

Use it as a Python module:

```powershell
python -m pip install python-openstackclient
```

### Region information

**Note:** CSC Allas uses `regionOne` as the name - this cannot be changed. Even though the service is located in Finland, the region name is always `regionOne`, not `eu-north-1` or similar.

### Endpoint information

| Service   | Endpoint                                        | Region      |
| --------- | ----------------------------------------------- | ----------- |
| S3 API    | `https://a3s.fi`                                | `regionOne` |
| Swift API | `https://a3s.fi:443/swift/v1/AUTH_[PROJECT_ID]` | `regionOne` |

---

**Useful links:**

- [CSC Allas user interface](https://allas.csc.fi/)
- [CSC Allas documentation](https://docs.csc.fi/data/Allas/)
- [CSC Pouta](https://pouta.csc.fi/)
- [CSC How to get Allas S3 credentials](https://docs.csc.fi/support/faq/how-to-get-Allas-s3-credentials/)
