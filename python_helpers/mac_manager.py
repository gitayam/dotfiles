#!/usr/bin/env python3
"""
Enhanced MAC Address Manager
Provides cross-platform MAC address operations with validation
"""

import re
import sys
import subprocess
import platform
from typing import Optional, List, Tuple

class MACAddressManager:
    """Manages MAC address operations across different platforms"""
    
    # IEEE OUI (Organizationally Unique Identifier) database (sample)
    KNOWN_VENDORS = {
        "00:00:5E": "IANA",
        "00:50:56": "VMware",
        "08:00:27": "VirtualBox",
        "52:54:00": "QEMU/KVM",
        "00:16:3E": "Xen",
        "00:1C:42": "Parallels",
        "AC:DE:48": "Apple",
        "00:03:93": "Apple",
    }
    
    def __init__(self):
        self.platform = platform.system()
        
    def validate_mac(self, mac: str) -> Tuple[bool, str]:
        """
        Validate MAC address format
        Returns: (is_valid, normalized_mac)
        """
        # Remove common separators
        clean = mac.replace(':', '').replace('-', '').replace('.', '').upper()
        
        # Check length
        if len(clean) != 12:
            return False, ""
            
        # Check hex characters
        if not all(c in '0123456789ABCDEF' for c in clean):
            return False, ""
            
        # Format as colon-separated
        normalized = ':'.join(clean[i:i+2] for i in range(0, 12, 2))
        return True, normalized.lower()
    
    def get_vendor(self, mac: str) -> Optional[str]:
        """Get vendor from MAC address OUI"""
        oui = ':'.join(mac.upper().split(':')[:3])
        return self.KNOWN_VENDORS.get(oui, "Unknown Vendor")
    
    def is_locally_administered(self, mac: str) -> bool:
        """Check if MAC is locally administered (random)"""
        first_octet = int(mac.split(':')[0], 16)
        return bool(first_octet & 0x02)
    
    def is_multicast(self, mac: str) -> bool:
        """Check if MAC is multicast"""
        first_octet = int(mac.split(':')[0], 16)
        return bool(first_octet & 0x01)
    
    def generate_random_mac(self, locally_administered: bool = True) -> str:
        """
        Generate a random MAC address
        If locally_administered=True, sets the local bit
        """
        import random
        
        # Generate 6 random bytes
        mac_bytes = [random.randint(0, 255) for _ in range(6)]
        
        if locally_administered:
            # Set bit 1 (locally administered) and clear bit 0 (unicast)
            mac_bytes[0] = (mac_bytes[0] & 0xFE) | 0x02
        else:
            # Clear both bits (universally administered, unicast)
            mac_bytes[0] = mac_bytes[0] & 0xFC
            
        return ':'.join(f'{b:02x}' for b in mac_bytes)
    
    def get_current_mac(self, interface: str) -> Optional[str]:
        """Get current MAC address for interface"""
        try:
            if self.platform == 'Darwin':  # macOS
                cmd = ['networksetup', '-getmacaddress', interface]
                result = subprocess.run(cmd, capture_output=True, text=True)
                if result.returncode == 0:
                    # Parse output: "Ethernet Address: xx:xx:xx:xx:xx:xx (Device: en0)"
                    match = re.search(r'([0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2})', result.stdout)
                    if match:
                        return match.group(1).lower()
                        
            elif self.platform == 'Linux':
                cmd = ['ip', 'link', 'show', interface]
                result = subprocess.run(cmd, capture_output=True, text=True)
                if result.returncode == 0:
                    match = re.search(r'link/ether\s+([0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2})', result.stdout)
                    if match:
                        return match.group(1).lower()
                        
        except Exception as e:
            print(f"Error getting MAC: {e}", file=sys.stderr)
            
        return None
    
    def list_interfaces(self) -> List[Tuple[str, str]]:
        """List all network interfaces with their MAC addresses"""
        interfaces = []
        
        try:
            if self.platform == 'Darwin':
                # Use networksetup to list all hardware ports
                cmd = ['networksetup', '-listallhardwareports']
                result = subprocess.run(cmd, capture_output=True, text=True)
                
                lines = result.stdout.split('\n')
                current_device = None
                
                for line in lines:
                    if line.startswith('Device:'):
                        current_device = line.split(':', 1)[1].strip()
                    elif line.startswith('Ethernet Address:') and current_device:
                        mac = line.split(':', 1)[1].strip()
                        if mac and mac != 'N/A':
                            interfaces.append((current_device, mac))
                        current_device = None
                        
            elif self.platform == 'Linux':
                cmd = ['ip', 'link', 'show']
                result = subprocess.run(cmd, capture_output=True, text=True)
                
                current_iface = None
                for line in result.stdout.split('\n'):
                    # Match interface line
                    iface_match = re.match(r'^\d+:\s+([^:]+):', line)
                    if iface_match:
                        current_iface = iface_match.group(1)
                    # Match MAC address line
                    elif current_iface and 'link/ether' in line:
                        mac_match = re.search(r'([0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2})', line)
                        if mac_match:
                            interfaces.append((current_iface, mac_match.group(1)))
                        current_iface = None
                        
        except Exception as e:
            print(f"Error listing interfaces: {e}", file=sys.stderr)
            
        return interfaces
    
    def analyze_mac(self, mac: str) -> dict:
        """Analyze MAC address and return detailed information"""
        is_valid, normalized = self.validate_mac(mac)
        
        if not is_valid:
            return {'valid': False, 'error': 'Invalid MAC address format'}
            
        return {
            'valid': True,
            'mac': normalized,
            'vendor': self.get_vendor(normalized),
            'locally_administered': self.is_locally_administered(normalized),
            'multicast': self.is_multicast(normalized),
            'type': 'Random/Custom' if self.is_locally_administered(normalized) else 'Manufacturer Assigned',
        }


def main():
    import argparse
    
    parser = argparse.ArgumentParser(description='Enhanced MAC Address Manager')
    parser.add_argument('command', choices=['validate', 'generate', 'analyze', 'list', 'get'],
                       help='Command to execute')
    parser.add_argument('--mac', help='MAC address to validate/analyze')
    parser.add_argument('--interface', help='Network interface name')
    parser.add_argument('--locally-administered', action='store_true',
                       help='Generate locally administered MAC')
    
    args = parser.parse_args()
    manager = MACAddressManager()
    
    if args.command == 'validate':
        if not args.mac:
            print("Error: --mac required for validate", file=sys.stderr)
            sys.exit(1)
        is_valid, normalized = manager.validate_mac(args.mac)
        if is_valid:
            print(f"✓ Valid MAC address: {normalized}")
            sys.exit(0)
        else:
            print(f"✗ Invalid MAC address", file=sys.stderr)
            sys.exit(1)
            
    elif args.command == 'generate':
        mac = manager.generate_random_mac(args.locally_administered)
        print(mac)
        
    elif args.command == 'analyze':
        if not args.mac:
            print("Error: --mac required for analyze", file=sys.stderr)
            sys.exit(1)
        info = manager.analyze_mac(args.mac)
        if info['valid']:
            print(f"MAC Address: {info['mac']}")
            print(f"Vendor: {info['vendor']}")
            print(f"Type: {info['type']}")
            print(f"Locally Administered: {'Yes' if info['locally_administered'] else 'No'}")
            print(f"Multicast: {'Yes' if info['multicast'] else 'No'}")
        else:
            print(info['error'], file=sys.stderr)
            sys.exit(1)
            
    elif args.command == 'list':
        interfaces = manager.list_interfaces()
        print("Network Interfaces:")
        for iface, mac in interfaces:
            vendor = manager.get_vendor(mac)
            print(f"  {iface:12} {mac:17} ({vendor})")
            
    elif args.command == 'get':
        if not args.interface:
            print("Error: --interface required for get", file=sys.stderr)
            sys.exit(1)
        mac = manager.get_current_mac(args.interface)
        if mac:
            print(mac)
        else:
            print(f"Error: Could not get MAC for {args.interface}", file=sys.stderr)
            sys.exit(1)


if __name__ == '__main__':
    main()
