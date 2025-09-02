# Cloudflare Quick Commands Reference

## Most Common Commands

### File Sharing
```bash
cfpublic FILE     # Share file publicly (instant URL)
cfshare FILE      # Same as cfpublic
cfpu FILE         # Short version of cfpublic

cfps              # Screenshot directly to public Pages
cfpscreen         # Same as cfps
```

### Private Storage
```bash
cfu FILE          # Upload to private R2 bucket
cfshot            # Screenshot to private R2
cfscreen          # Same as cfshot
cfss              # Short for screenshot
```

### File Management
```bash
cfls              # List files in R2 bucket
cfpl              # List public files on Pages
cfpls             # Same as cfpl
cfdown FILE       # Download from R2
cfrm FILE         # Delete from R2
```

### Temporary Sharing
```bash
cftemp FILE       # Create temporary share link (24h)
cftmp FILE        # Same as cftemp
cfclean           # Clean expired temp shares
```

### Secrets Management
```bash
cfs               # Sync secrets from .env
cfg KEY           # Get secret value
cflist            # List all secrets
```

### Development
```bash
cfdev             # Start local dev server
cfd               # Deploy to production
cflog             # View worker logs
cfinfo            # Show Cloudflare setup info
```

### Help
```bash
cf                # Show help menu
cfhelp            # Full help menu
```

## Examples

### Share a file publicly
```bash
cfpublic report.pdf
# Output: 🔗 Public URL: https://public-files-5kg.pages.dev/report.pdf
```

### Take and share a screenshot
```bash
cfps
# Press Cmd+Shift+4, select area
# Output: 🔗 Public URL: https://public-files-5kg.pages.dev/screenshot_20250902_123456.png
```

### Upload private file
```bash
cfu confidential.doc
# Output: ✅ Uploaded to R2: files/confidential.doc
```

### Create temporary share
```bash
cftemp private-doc.pdf
# Output: 🔗 Temporary URL (24h): https://public-files-5kg.pages.dev/temp_1234567890_private-doc.pdf
```

## Setup

First time setup:
```bash
source ~/.zsh_network
cfpage-init       # Initialize Pages project
```

## Tips

- All public URLs are automatically copied to clipboard
- Screenshots are taken with macOS native tool (Cmd+Shift+4)
- Temporary shares expire after 24 hours by default
- Use `cfhelp` or `cf` anytime to see quick commands