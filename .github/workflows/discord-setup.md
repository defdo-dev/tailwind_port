# Discord Notifications Setup

This document explains how to set up Discord notifications for the TailwindPort CI/CD pipeline.

## Overview

The CI/CD pipeline includes Discord notifications for:

- **CI Pipeline Results** (`.github/workflows/ci.yml`)
  - ✅ All tests pass
  - ❌ Build/test failures
  - ⚠️ Partial success/failure

- **Release Notifications** (`.github/workflows/release.yml`)
  - 🎉 Successful releases with installation instructions
  - ❌ Release failures with detailed job status

- **Documentation Updates** (`.github/workflows/docs.yml`)
  - 📚 Documentation deployments
  - ❌ Documentation build failures

## Setup Instructions

### 1. Create Discord Webhook

1. Go to your Discord server
2. Navigate to **Server Settings** → **Integrations** → **Webhooks**
3. Click **Create Webhook**
4. Configure the webhook:
   - **Name**: `TailwindPort CI/CD`
   - **Channel**: Choose your notifications channel (e.g., `#ci-cd`, `#dev-updates`)
   - **Avatar**: Optionally upload a custom avatar
5. Copy the **Webhook URL**

### 2. Add GitHub Secret

1. Go to your GitHub repository
2. Navigate to **Settings** → **Secrets and variables** → **Actions**
3. Click **New repository secret**
4. Add the secret:
   - **Name**: `DISCORD_WEBHOOK`
   - **Secret**: Paste the webhook URL from Discord
5. Click **Add secret**

### 3. Test the Setup

Create a test commit to trigger the CI pipeline:

```bash
git commit --allow-empty -m "test: trigger Discord notifications"
git push origin main
```

You should see Discord notifications in your configured channel.

## Notification Examples

### CI Success Notification
```
✅ CI Pipeline Success - TailwindPort

Branch: main
Commit: abc123de
Author: your-username
Message: feat: add new feature

🧪 All tests passed
🔍 Code quality checks passed
📚 Documentation generated
🔒 Security audit passed
⚡ Functional tests passed

[View Details](https://github.com/...)
```

### Release Success Notification
```
🎉 Release Published Successfully - TailwindPort v0.2.0

Version: v0.2.0
Type: Stable Release
Author: your-username

📦 Package: https://hex.pm/packages/tailwind_port
📚 Documentation: https://hexdocs.pm/tailwind_port/0.2.0
🏷️ GitHub Release: https://github.com/.../releases/tag/v0.2.0

Installation:
```elixir
def deps do
  [
    {:tailwind_port, "~> 0.2.0"}
  ]
end
```

Ready for production use! 🚀
```

### CI Failure Notification
```
❌ CI Pipeline Failed - TailwindPort

Branch: feature-branch
Commit: def456gh
Author: your-username
Message: fix: attempt to fix issue

Failed Jobs:
✅ Tests
❌ Dialyzer
✅ Documentation
✅ Security
✅ Functional Tests

[View Details](https://github.com/...)
```

## Customization

### Channel-Specific Notifications

You can create different webhooks for different types of notifications:

1. **Development Channel** (`#dev-updates`): CI results, documentation updates
2. **Releases Channel** (`#releases`): Release announcements only
3. **Alerts Channel** (`#alerts`): Failures and critical issues only

To use multiple webhooks, create additional GitHub secrets:
- `DISCORD_WEBHOOK_DEV`
- `DISCORD_WEBHOOK_RELEASES`
- `DISCORD_WEBHOOK_ALERTS`

Then modify the workflow files to use the appropriate webhook for each notification.

### Message Customization

You can customize the Discord messages by editing the `args` section in the workflow files:

```yaml
with:
  args: |
    🎯 **Custom Message** - TailwindPort
    
    Your custom content here...
    
    [Custom Link](https://your-link.com)
```

### Conditional Notifications

The workflows include conditions to control when notifications are sent:

- `if: always() && github.event_name == 'push'` - Only on pushes, regardless of job outcome
- `if: success()` - Only on successful completion
- `if: failure()` - Only on failures
- `if: github.ref == 'refs/heads/main'` - Only on main branch

## Troubleshooting

### Notifications Not Working

1. **Check the webhook URL**: Ensure the `DISCORD_WEBHOOK` secret is correctly set
2. **Verify channel permissions**: Make sure the webhook has permission to post in the channel
3. **Check workflow logs**: Look for Discord action errors in the GitHub Actions logs
4. **Test webhook manually**: Use a tool like curl to test the webhook URL

### Message Formatting Issues

- Discord uses Markdown formatting
- Use `**bold**`, `*italic*`, `` `code` ``, and `> quote` for formatting
- Code blocks use triple backticks with language specification:
  ````
  ```elixir
  code here
  ```
  ````

### Rate Limiting

Discord webhooks have rate limits:
- 30 requests per minute per webhook
- If you hit limits, notifications may be delayed or dropped

## Security Notes

- The webhook URL is sensitive - treat it like a password
- Use GitHub repository secrets, never commit webhook URLs to code
- Consider using environment-specific webhooks for different deployment stages
- Regularly rotate webhook URLs if they become compromised

## Additional Resources

- [Discord Webhook Documentation](https://discord.com/developers/docs/resources/webhook)
- [GitHub Actions Discord Action](https://github.com/Ilshidur/action-discord)
- [GitHub Secrets Documentation](https://docs.github.com/en/actions/security-guides/encrypted-secrets)