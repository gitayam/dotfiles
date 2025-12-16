#!/usr/bin/env python3
"""
A script to organize files in a directory by their extension.
"""
import os
import shutil
import argparse
from collections import defaultdict

def organize_directory(directory: str, dry_run: bool = False):
    """
    Organizes files in a directory by creating subdirectories for each file extension
    and moving the files into them.

    :param directory: The directory to organize.
    :param dry_run: If True, print the changes that would be made without actually making them.
    """
    print(f"Scanning directory: {directory}")
    files_by_extension = defaultdict(list)

    # Group files by extension
    for item in os.listdir(directory):
        item_path = os.path.join(directory, item)
        if os.path.isfile(item_path):
            _, extension = os.path.splitext(item)
            if extension:
                files_by_extension[extension[1:].lower()].append(item)

    if not files_by_extension:
        print("No files with extensions found to organize.")
        return

    print("Found files with the following extensions:")
    for ext, files in files_by_extension.items():
        print(f"  - .{ext}: {len(files)} file(s)")

    if dry_run:
        print("\n[DRY RUN] The following operations would be performed:")

    for ext, files in files_by_extension.items():
        ext_dir = os.path.join(directory, ext)
        if not os.path.exists(ext_dir):
            print(f"Creating directory: {ext_dir}")
            if not dry_run:
                os.makedirs(ext_dir)

        for file in files:
            src_path = os.path.join(directory, file)
            dest_path = os.path.join(ext_dir, file)
            print(f"Moving '{src_path}' to '{dest_path}'")
            if not dry_run:
                shutil.move(src_path, dest_path)

    print("\nOrganization complete.")

def main():
    parser = argparse.ArgumentParser(description="Organize files in a directory by their extension.")
    parser.add_argument(
        "directory",
        nargs="?",
        default=os.path.expanduser("~/Downloads"),
        help="The directory to organize (defaults to ~/Downloads)."
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Print the changes that would be made without actually moving any files."
    )
    args = parser.parse_args()

    if not os.path.isdir(args.directory):
        print(f"Error: Directory not found: {args.directory}")
        sys.exit(1)

    organize_directory(args.directory, args.dry_run)

if __name__ == "__main__":
    main()
