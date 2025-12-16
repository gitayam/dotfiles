#!/usr/bin/env python3
"""
Simple HTTP server that serves a single file or directory.
For single files, redirects root to the file.
For directories, shows listing.
"""

import http.server
import socketserver
import sys
import os
from urllib.parse import unquote

class SingleFileHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, single_file=None, **kwargs):
        self.single_file = single_file
        super().__init__(*args, **kwargs)
    
    def do_GET(self):
        # If we're serving a single file and request is for root, redirect to the file
        if self.single_file and self.path in ['/', '/index.html']:
            # Redirect to the actual file
            self.send_response(302)
            self.send_header('Location', '/' + os.path.basename(self.single_file))
            self.end_headers()
            return
        
        # For image files, ensure proper content type
        if self.path.endswith(('.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg')):
            # Serve the image with proper headers
            return super().do_GET()
        
        # Default behavior for everything else
        return super().do_GET()
    
    def guess_type(self, path):
        """Ensure correct MIME types for images"""
        mimetype = super().guess_type(path)
        if path.endswith('.svg'):
            return 'image/svg+xml'
        return mimetype

def serve_file_or_directory(path, port):
    """Serve a single file or directory on the specified port"""
    
    # Check if path is a file or directory
    is_single_file = os.path.isfile(path)
    
    if is_single_file:
        # Serve from the file's directory
        directory = os.path.dirname(os.path.abspath(path))
        filename = os.path.basename(path)
        os.chdir(directory)
        
        # Create handler with single file info
        handler = lambda *args, **kwargs: SingleFileHandler(
            *args, 
            single_file=filename,
            **kwargs
        )
        print(f"Serving file: {filename} from {directory}")
    else:
        # Serve directory
        os.chdir(path if path else '.')
        handler = SingleFileHandler
        print(f"Serving directory: {os.getcwd()}")
    
    with socketserver.TCPServer(("", port), handler) as httpd:
        print(f"Server running on port {port}")
        httpd.serve_forever()

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: serve-file.py <port> [file_or_directory]")
        sys.exit(1)
    
    port = int(sys.argv[1])
    path = sys.argv[2] if len(sys.argv) > 2 else '.'
    
    try:
        serve_file_or_directory(path, port)
    except KeyboardInterrupt:
        print("\nServer stopped")
        sys.exit(0)