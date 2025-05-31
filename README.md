# Deploy Firebase Functions with Workload Identity Federation

GitHub Action for deploying Firebase Functions using Google Cloud [Workload Identity Federation](https://cloud.google.com/iam/docs/workload-identity-federation) for secure, keyless authentication.

## Prerequisites

Before using this action, you need to set up Workload Identity Federation between GitHub and Google Cloud in your Google Cloud project. The setup instructions are summarised from the [official Google GitHub Actions auth documentation](https://github.com/google-github-actions/auth#indirect-wif).

> [!NOTE]
> The official Google GitHub Actions auth documentation mentions that Workload Identity Federation is not supported by the Firebase Admin SDK. However, as of November 12, 2024, [it is supported](https://github.com/firebase/firebase-admin-node/issues/1377#issuecomment-2471104457).

**Authentication Methods:** There are multiple ways to authenticate GitHub Actions to Google Cloud:

1. **Direct Workload Identity Federation**
2. **Workload Identity Federation through a Service Account** (recommended and used here)
3. **Service Account Key JSON** (not recommended for security reasons)

This guide covers **Workload Identity Federation through a Service Account**. For other methods, see the [official Google GitHub Actions auth documentation](https://github.com/google-github-actions/auth#direct-wif).

### Setup Instructions

These instructions use the `gcloud` command-line tool. Replace the placeholder variables with your actual values:

- `${PROJECT_ID}`: Your Google Cloud project ID
- `${GITHUB_ORG}`: Your GitHub organisation/username
- `${REPO}`: Your full repository name (e.g., "username/repo-name" or "org/repo-name")

> [!TIP]
> You can set these as environment variables in your shell to make copying commands easier:
>
> ```sh
> export PROJECT_ID="your-project-id"
> export GITHUB_ORG="your-github-org"
> export REPO="your-github-org/your-repo-name"
> ```

### 1. Create a Google Cloud Service Account (Optional)

If you already have a service account for deploying Firebase Functions, note its email and skip to step 2.

Create a service account:

```sh
gcloud iam service-accounts create "deploy-firebase-functions" \
  --project="${PROJECT_ID}" \
  --display-name="Deploy Firebase Functions Service Account"
```

**Required Roles:** The service account needs these minimum roles for deploying Firebase Functions:

- `roles/cloudfunctions.admin` - Full access to functions, operations, and locations
- `roles/iam.serviceAccountUser` - Run operations as the service account

Add the required roles:

```sh
gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:deploy-firebase-functions@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/cloudfunctions.admin"

gcloud projects add-iam-policy-binding "${PROJECT_ID}" \
  --member="serviceAccount:deploy-firebase-functions@${PROJECT_ID}.iam.gserviceaccount.com" \
  --role="roles/iam.serviceAccountUser"
```

### 2. Create a Workload Identity Pool

```sh
gcloud iam workload-identity-pools create "github" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --display-name="GitHub Actions Pool"
```

### 3. Get the Workload Identity Pool ID

```sh
gcloud iam workload-identity-pools describe "github" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --format="value(name)"
```

Save the output from this command; you'll need it for step 5. It will look something like:

```
projects/123456789/locations/global/workloadIdentityPools/github
```

### 4. Create a Workload Identity Provider

Create an OIDC provider in the pool (the pool name must match step 2):

```sh
gcloud iam workload-identity-pools providers create-oidc "repo" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --workload-identity-pool="github" \
  --display-name="GitHub repo provider" \
  --attribute-mapping="google.subject=assertion.sub,attribute.actor=assertion.actor,attribute.repository=assertion.repository,attribute.repository_owner=assertion.repository_owner" \
  --attribute-condition="assertion.repository_owner == '${GITHUB_ORG}'" \
  --issuer-uri="https://token.actions.githubusercontent.com"
```

> [!IMPORTANT]
> Always add an `--attribute-condition` to restrict access to the Workload Identity Pool. This example restricts access to repositories owned by your organisation/username. You can add additional restrictions in IAM bindings, but always include a basic condition here.

### 5. Allow Workload Identity Pool Access to Service Account

Replace `${WORKLOAD_IDENTITY_POOL_ID}` with the value from step 3.

If you skipped step 1 and are using an existing service account, replace `deploy-firebase-functions@${PROJECT_ID}.iam.gserviceaccount.com` with the email of your service account.

```sh
gcloud iam service-accounts add-iam-policy-binding \
  "deploy-firebase-functions@${PROJECT_ID}.iam.gserviceaccount.com" \
  --project="${PROJECT_ID}" \
  --role="roles/iam.workloadIdentityUser" \
  --member="principalSet://iam.googleapis.com/${WORKLOAD_IDENTITY_POOL_ID}/attribute.repository/${REPO}"
```

### 6. Get the Workload Identity Provider Resource Name

```sh
gcloud iam workload-identity-pools providers describe "repo" \
  --project="${PROJECT_ID}" \
  --location="global" \
  --workload-identity-pool="github" \
  --format="value(name)"
```

Save the output from this command; you'll use it as `WORKLOAD_IDENTITY_PROVIDER` in your GitHub Actions workflow. It will look something like:

```
projects/123456789/locations/global/workloadIdentityPools/github/providers/repo
```

## Configuration

Below are the inputs available for configuring the Firebase Functions deployment action. All inputs are passed through the `with` clause in your GitHub Actions workflow.

### Available Inputs

| Input | Description | Required | Default | Notes |
|-------|-------------|----------|---------|-------|
| `project-id` | Firebase project ID | ✅ | - | Must match the project configured in your Workload Identity Federation |
| `functions-dir` | Directory containing Firebase functions | ❌ | `functions` | Relative path from repository root. Must contain `package.json` and Firebase functions |
| `force` | Whether to use `--force` flag for deployment | ❌ | `false` | Use with caution; this will delete functions not in current deployment |
| `debug` | Whether to use `--debug` flag for deployment | ❌ | `false` | Provides verbose logging for troubleshooting deployment issues |

## Usage

### Environment Variables

Set the following variables in your GitHub Actions workflow or repository secrets:

- `PROJECT_ID`: Your Firebase project ID
- `WORKLOAD_IDENTITY_PROVIDER`: The provider resource name from Workload Identity Federation setup in step 6
- `SERVICE_ACCOUNT`: Your service account email (e.g., `deploy-firebase-functions@your-project-id.iam.gserviceaccount.com`)

### Basic Usage

```yaml
name: Deploy Firebase Functions
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4

      - uses: google-github-actions/auth@v2
        with:
          project_id: ${{ vars.PROJECT_ID }}
          workload_identity_provider: ${{ vars.WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ vars.SERVICE_ACCOUNT }}

      - uses: mwpryer/deploy-firebase-functions@v1
        with:
          project-id: ${{ vars.PROJECT_ID }}
```

### Advanced Usage

```yaml
name: Deploy Firebase Functions
on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      id-token: write
    steps:
      - uses: actions/checkout@v4

      - uses: google-github-actions/auth@v2
        with:
          project_id: ${{ vars.PROJECT_ID }}
          workload_identity_provider: ${{ vars.WORKLOAD_IDENTITY_PROVIDER }}
          service_account: ${{ vars.SERVICE_ACCOUNT }}

      - uses: mwpryer/deploy-firebase-functions@v1
        with:
          project-id: ${{ vars.PROJECT_ID }}
          functions-dir: "firebase/functions"
          force: "true"
          debug: "true"
```
