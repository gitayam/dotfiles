# macOS System Configuration Guide

This document explains the 20 system configurations applied by the initial macOS setup script.

## Security Settings (1-8)

### 1. FileVault Disk Encryption
**What it does:** Encrypts your entire disk with XTS-AES-128 encryption  
**Why:** Protects data if your Mac is stolen or lost  
**Impact:** Slight performance overhead, requires password on boot  

### 2. Firewall with Stealth Mode
**What it does:** Blocks incoming network connections and hides your Mac from network scans  
**Why:** Prevents unauthorized network access and makes your Mac invisible to attackers  
**Impact:** Some apps may prompt for network access permissions  

### 3. Disable Automatic Login
**What it does:** Requires password/Touch ID to log in after restart  
**Why:** Prevents unauthorized access if someone has physical access to your Mac  
**Impact:** Must enter credentials after every restart  

### 4. Immediate Password After Sleep
**What it does:** Requires password immediately when waking from sleep/screensaver  
**Why:** Prevents unauthorized access when you step away briefly  
**Impact:** More frequent password entry, but better security  

### 5. Disable Remote Login Services
**What it does:** Turns off SSH, screen sharing, and other remote access  
**Warning:** Disabling remote login services will prevent all remote access methods, including SSH, screen sharing, and remote desktop. This may impact your ability to access your Mac remotely for legitimate purposes.  
**Why:** Eliminates remote attack vectors  
**Impact:** Cannot remotely access this Mac via SSH, screen sharing, or other methods. However, this setting is now optional, and you can choose to enable remote login services if you need them for work or other purposes.  

### 6. Secure Keyboard Entry in Terminal
**What it does:** Prevents other apps from monitoring what you type in Terminal  
**Why:** Protects passwords, API keys, and sensitive commands from keyloggers  
**Impact:** Slightly more secure terminal usage  

### 7. Disable Siri Data Collection
**What it does:** Turns off Siri suggestions and data sharing with Apple  
**Why:** Improves privacy by not sending usage data to Apple  
**Impact:** Fewer contextual suggestions, more privacy  

### 8. Enable Gatekeeper
**What it does:** Only allows apps from identified developers to run  
**Why:** Prevents malware and unsigned applications from running  
**Impact:** May need to explicitly allow some legitimate apps  

## Privacy & Cleanup (9-11)

### 9. Disable Location Services for System Services
**What it does:** Stops system services from accessing your location  
**Why:** Improves privacy by not sharing location data unnecessarily  
**Impact:** Some location-based features may not work  

### 10. Configure Safari Privacy Settings
**What it does:** Enables developer tools and "Do Not Track" headers  
**Why:** Better web development tools and reduced tracking  
**Impact:** More privacy online, better debugging capabilities  

### 11. Enable Security Auditing
**What it does:** Logs security-relevant system events and user sessions  
**Why:** Creates audit trails for security monitoring and forensics  
**Impact:** Slightly more disk usage for logs, better security monitoring  

## Convenience & Performance (12-17)

### 12. Disable Spotlight Indexing of External Drives
**What it does:** Prevents Spotlight from indexing USB drives, SD cards, etc.  
**Why:** Faster external drive access, less background activity  
**Impact:** Cannot search contents of external drives via Spotlight  

### 13. Enable Tap to Click and Three-Finger Drag
**What it does:** Makes trackpad more responsive and adds gesture support  
**Why:** Faster, more intuitive trackpad usage  
**Impact:** More efficient navigation and window management  

### 14. Show Hidden Files and Extensions
**What it does:** Displays .files and file extensions in Finder  
**Why:** Better understanding of file system, safer file handling  
**Impact:** More cluttered Finder view, but more informative  

### 15. Speed Up Animations
**What it does:** Reduces window animation times and Mission Control delays  
**Why:** Faster, more responsive interface  
**Impact:** Snappier UI, less visual polish  

### 16. Enhanced Finder Features
**What it does:** Shows path bar, status bar, and sets list view as default  
**Why:** More information and better file management  
**Impact:** More informative but busier Finder interface  

### 17. Organized Screenshots
**What it does:** Saves screenshots to ~/Pictures/Screenshots in PNG format  
**Why:** Keeps desktop clean and uses lossless image format  
**Impact:** Screenshots don't clutter desktop, better image quality  

## System Preferences (18-20)

### 18. Optimized Energy Settings
**What it does:** Sets display sleep to 10min, system sleep to 30min, disables hibernation  
**Why:** Balances battery life with performance and faster wake times  
**Impact:** Slightly more battery usage, much faster wake from sleep  

### 19. Automatic Time Sync
**What it does:** Sets timezone to Eastern and syncs with Apple's time servers  
**Why:** Ensures accurate time for security certificates and logging  
**Impact:** Always accurate time, may need timezone adjustment for other regions  

### 20. Developer-Friendly Text Input
**What it does:** Disables smart quotes, auto-correct, and auto-capitalization  
**Why:** Prevents text substitution that breaks code and commands  
**Impact:** Less "helpful" text correction, but safer for technical work  

## Post-Configuration Notes

- **Restart Required:** Some settings need a logout/restart to fully activate
- **Reversible:** All settings can be manually changed in System Preferences
- **Customizable:** Edit the script to skip settings you don't want
- **Security:** These settings prioritize security and privacy over convenience

## Troubleshooting

If you experience issues after configuration:

1. **FileVault Problems:** Can be disabled in System Preferences > Security & Privacy
2. **Network Issues:** Check Firewall settings in System Preferences > Security & Privacy
3. **App Permissions:** Some apps may need explicit permission in Security & Privacy
4. **Performance:** Hibernation can be re-enabled with `sudo pmset -a hibernatemode 3`

## Verification

To check if settings were applied:
```bash
# Check FileVault status
fdesetup status

# Check firewall status
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --getglobalstate

# Check current defaults
defaults read com.apple.finder AppleShowAllFiles
```
