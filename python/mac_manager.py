#!/usr/bin/env python3
"""
Advanced MAC Address Manager
Provides detailed, cross-platform MAC address operations with live vendor lookup and rich formatting.
"""

import re
import sys
import subprocess
import platform
import argparse
import requests
from typing import Optional, List, Tuple

try:
    from rich.console import Console
    from rich.table import Table
    from rich.panel import Panel
    from rich.text import Text
except ImportError:
    print("Error: 'rich' library not found. Please install it with 'pip install rich'", file=sys.stderr)
    sys.exit(1)

console = Console()

class MACAddressManager:
    """Manages MAC address operations with advanced features."""
    
    VENDOR_API_URL = "https://api.macvendors.com/"
    
    def __init__(self):
        self.platform = platform.system()
        
    def validate_mac(self, mac: str) -> Tuple[bool, str]:
        """Validate and normalize a MAC address."""
        clean = re.sub(r'[^0-9a-fA-F]', '', mac)
        if len(clean) != 12:
            return False, ""
        normalized = ':'.join(clean[i:i+2] for i in range(0, 12, 2)).lower()
        return True, normalized
    
    def get_vendor(self, mac: str) -> str:
        """Fetch vendor information from an online API."""
        try:
            response = requests.get(f"{self.VENDOR_API_URL}{mac}")
            if response.status_code == 200:
                return response.text
            elif response.status_code == 404:
                return "Vendor not found in public registry"
        except requests.RequestException:
            return "Unable to connect to vendor API"
        return "Unknown Vendor"
    
    def is_locally_administered(self, mac: str) -> bool:
        """Check if MAC is locally administered (random)."""
        first_octet = int(mac.split(':')[0], 16)
        return bool(first_octet & 0x02)
    
    def is_multicast(self, mac: str) -> bool:
        """Check if MAC is a multicast address."""
        first_octet = int(mac.split(':')[0], 16)
        return bool(first_octet & 0x01)

    def generate_random_mac(self, locally_administered: bool = True) -> str:
        """Generate a cryptographically secure random MAC address."""
        import secrets
        mac_bytes = [secrets.randbits(8) for _ in range(6)]
        
        if locally_administered:
            mac_bytes[0] = (mac_bytes[0] & 0xFE) | 0x02
        else:
            mac_bytes[0] = mac_bytes[0] & 0xFC
            
        return ':'.join(f'{b:02x}' for b in mac_bytes)
    
    def get_current_mac(self, interface: str) -> Optional[str]:
        """Get the current MAC address for a given interface."""
        try:
            if self.platform == 'Darwin':
                cmd = ['ifconfig', interface]
            elif self.platform == 'Linux':
                cmd = ['ip', 'link', 'show', interface]
            else:
                return None

            result = subprocess.run(cmd, capture_output=True, text=True, check=True)
            mac_match = re.search(r'ether\s+([0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2})', result.stdout)
            if mac_match:
                return mac_match.group(1).lower()

        except (subprocess.CalledProcessError, FileNotFoundError):
            return None
        return None

    def list_interfaces(self) -> List[Tuple[str, str]]:
        """List all network interfaces with their MAC addresses."""
        interfaces = []
        try:
            if self.platform == 'Darwin':
                cmd = ['networksetup', '-listallhardwareports']
                result = subprocess.run(cmd, capture_output=True, text=True, check=True)
                lines = result.stdout.strip().split('\n\n')
                for block in lines:
                    device_match = re.search(r'Device: (en\d+)', block)
                    mac_match = re.search(r'Ethernet Address: ([0-9a-fA-F:]+)', block)
                    if device_match and mac_match:
                        interfaces.append((device_match.group(1), mac_match.group(1).lower()))

            elif self.platform == 'Linux':
                cmd = ['ip', '-o', 'link', 'show']
                result = subprocess.run(cmd, capture_output=True, text=True, check=True)
                for line in result.stdout.strip().split('\n'):
                    parts = line.split()
                    iface = parts[1].strip(':')
                    mac_index = -1
                    try:
                        mac_index = parts.index('link/ether') + 1
                        if mac_index < len(parts):
                            interfaces.append((iface, parts[mac_index]))
                    except ValueError:
                        continue
        except (subprocess.CalledProcessError, FileNotFoundError):
            pass
            
        return interfaces
    
    def analyze_mac(self, mac: str):
        """Analyze a MAC address and display a rich table of information."""
        is_valid, normalized = self.validate_mac(mac)
        if not is_valid:
            console.print(f"[bold red]Error:[/] Invalid MAC address format: '{mac}'")
            return

        vendor = self.get_vendor(normalized)
        is_local = self.is_locally_administered(normalized)
        
        table = Table(title=f"Analysis for [cyan]{normalized}[/]", show_header=False, box=None)
        table.add_column(style="magenta")
        table.add_column(style="green")
        
        table.add_row("Vendor:", vendor)
        table.add_row("Type:", "Locally Administered (Random)" if is_local else "Universally Unique (Manufacturer)")
        table.add_row("Transmission:", "Multicast/Broadcast" if self.is_multicast(normalized) else "Unicast")
        
        console.print(table)


def run_command(manager: MACAddressManager, args: argparse.Namespace):
    """Execute a command based on parsed arguments."""
    command = getattr(args, 'command', None)
    if command == 'validate':
        is_valid, normalized = manager.validate_mac(args.mac)
        if is_valid:
            console.print(f"[green]✓[/] Valid MAC address: [cyan]{normalized}[/]")
        else:
            console.print(f"[red]✗[/] Invalid MAC address: [yellow]{args.mac}[/]")
            
    elif command == 'generate':
        mac = manager.generate_random_mac(getattr(args, 'locally_administered', True))
        console.print(f"Generated MAC: [bold cyan]{mac}[/]")
        
    elif command == 'analyze':
        manager.analyze_mac(args.mac)
            
    elif command == 'list':
        interfaces = manager.list_interfaces()
        table = Table(title="Available Network Interfaces")
        table.add_column("Interface", style="cyan", no_wrap=True)
        table.add_column("MAC Address", style="magenta")
        table.add_column("Vendor", style="green")
        
        for iface, mac in interfaces:
            vendor = manager.get_vendor(mac)
            table.add_row(iface, mac, vendor)
        console.print(table)
            
    elif command == 'get':
        mac = manager.get_current_mac(args.interface)
        if mac:
            console.print(f"MAC for {args.interface}: [bold cyan]{mac}[/]")
        else:
            console.print(f"[red]Error:[/] Could not get MAC for interface '{args.interface}'")
    elif command in ['help', 'h']:
        print_interactive_help()
    else:
        console.print(f"[bold red]Unknown command:[/] '{command}'. Type 'help' for a list of commands.")

def print_interactive_help():
    """Prints the help message for interactive mode."""
    panel = Panel(
        Text.from_markup(
            """
[bold]Available Commands:[/bold]
  [cyan]list[/cyan]                            - List all network interfaces.
  [cyan]get[/cyan] [yellow]<interface>[/yellow]             - Get the MAC address for a specific interface.
  [cyan]analyze[/cyan] [yellow]<mac_address>[/yellow]       - Analyze a MAC address.
  [cyan]validate[/cyan] [yellow]<mac_address>[/yellow]      - Validate a MAC address format.
  [cyan]generate[/cyan] [yellow](--universal)[/yellow]    - Generate a new random MAC address.
  [cyan]help[/cyan]                            - Show this help message.
  [cyan]exit[/cyan], [cyan]quit[/cyan], [cyan]/q[/cyan]                  - Exit the interactive shell.
            """
        ),
        title="[bold green]Interactive Help[/]",
        border_style="blue"
    )
    console.print(panel)

def interactive_mode(manager: MACAddressManager):
    """Run the tool in interactive mode."""
    console.print(Panel("Welcome to the [bold green]Interactive MAC Manager[/]! Type 'help' for commands.",
                        expand=False, border_style="blue"))
    while True:
        try:
            cmd_input = console.input("[bold yellow]mac-manager>[/] ").strip()
            if not cmd_input:
                continue
            if cmd_input.lower() in ['exit', 'quit', '/q']:
                break
                
            parts = cmd_input.split()
            command = parts[0]
            
            # Simple argument parsing for interactive mode
            args_dict = {'command': command}
            if len(parts) > 1:
                if command in ['validate', 'analyze']:
                    args_dict['mac'] = parts[1]
                elif command == 'get':
                    args_dict['interface'] = parts[1]
                elif command == 'generate' and '--universal' in parts:
                    args_dict['locally_administered'] = False
            
            # Convert dict to Namespace to reuse the run_command function
            run_command(manager, argparse.Namespace(**args_dict))

        except KeyboardInterrupt:
            console.print("\nExiting interactive mode.")
            break
        except Exception as e:
            console.print(f"[bold red]An unexpected error occurred:[/] {e}")

def main():
    parser = argparse.ArgumentParser(
        description='Advanced MAC Address Manager.',
        formatter_class=argparse.RawTextHelpFormatter
    )
    parser.add_argument('command', nargs='?', choices=['validate', 'generate', 'analyze', 'list', 'get', 'interactive'],
                       default='interactive',
                       help='''Command to execute:
  validate      - Validate a MAC address format.
  generate      - Generate a new random MAC address.
  analyze       - Analyze a MAC, providing vendor and type info.
  list          - List network interfaces and their MACs.
  get           - Get the MAC for a specific interface.
  interactive   - (Default) Enter interactive mode.''')
    parser.add_argument('--mac', help='MAC address to use for validate/analyze')
    parser.add_argument('--interface', help='Network interface for the "get" command')
    parser.add_argument('--locally-administered', action='store_true',
                       help='Generate a locally administered MAC (for "generate")')

    args = parser.parse_args()
    manager = MACAddressManager()

    if args.command == 'interactive':
        interactive_mode(manager)
    else:
        if args.command in ['validate', 'analyze'] and not args.mac:
            parser.error(f"'--mac' is required for the '{args.command}' command.")
        if args.command == 'get' and not args.interface:
            parser.error(f"'--interface' is required for the '{args.command}' command.")
        
        run_command(manager, args)


if __name__ == '__main__':
    main()
